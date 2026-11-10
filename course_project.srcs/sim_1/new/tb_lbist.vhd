-- tb_lbist.vhd : LBIST experiment testbench (simulation only)
-- Runs: conventional LBIST, then toggle-controlled LBIST at T = 13,26,51,77,128,
-- then repeats T=26 to confirm the MISR signature is reproducible.
-- For each run it measures:
--   * scan-in toggle rate  = transitions of the PATTERN bits entering the chains
--   * cell toggle rate     = transitions of ALL scan cells during shift (includes
--                            the previous response being shifted out)
--   * test time in clock cycles, and the MISR signature
-- Results are printed to the Tcl console AND written to lbist_results.csv.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
library std;
use std.textio.all;
use work.lbist_pkg.all;

entity tb_lbist is
end entity tb_lbist;

architecture sim of tb_lbist is
  constant N_PAT : integer := 100;      -- patterns per run (raise for longer runs)

  signal clk      : std_logic := '0';
  signal rst      : std_logic := '1';
  signal start    : std_logic := '0';
  signal tc_en    : std_logic := '0';
  signal t        : std_logic_vector(7 downto 0) := x"80";
  signal n_patterns : std_logic_vector(15 downto 0) := std_logic_vector(to_unsigned(N_PAT, 16));
  signal busy, done, scan_en_o : std_logic;
  signal signature : std_logic_vector(31 downto 0);
  signal scan_in_o : std_logic_vector(N_CHAINS-1 downto 0);
  signal cells_o   : std_logic_vector(N_CELLS-1 downto 0);
  signal mon_clr   : std_logic := '1';
  signal fin       : boolean := false;
  signal cell_tog, cell_cyc, in_tog, in_pairs : integer := 0;

  function popcount(v : std_logic_vector) return integer is
    variable c : integer := 0;
  begin
    for i in v'range loop
      if v(i) = '1' then c := c + 1; end if;
    end loop;
    return c;
  end function;

  function to_hex(v : std_logic_vector(31 downto 0)) return string is
    constant H : string(1 to 16) := "0123456789ABCDEF";
    variable s : string(1 to 8);
    variable n : integer;
  begin
    for i in 0 to 7 loop
      n := to_integer(unsigned(v(31-4*i downto 28-4*i)));
      s(i+1) := H(n+1);
    end loop;
    return s;
  end function;
begin
  dut : entity work.lbist_top
    port map (clk => clk, rst => rst, start => start, tc_en => tc_en, t => t,
              n_patterns => n_patterns, busy => open, done => done,
              signature => signature, scan_en_o => scan_en_o,
              scan_in_o => scan_in_o, cells_o => cells_o);

  clk_gen : process
  begin
    while not fin loop
      clk <= '0'; wait for 5 ns;
      clk <= '1'; wait for 5 ns;
    end loop;
    wait;
  end process;

  ---------------------------------------------------------------- toggle monitor
  mon : process (clk)
    variable prev_cells : std_logic_vector(N_CELLS-1 downto 0) := (others => '0');
    variable prev_se    : std_logic := '0';
    variable prev_sin   : std_logic_vector(N_CHAINS-1 downto 0) := (others => '0');
    variable prev_valid : boolean := false;
    variable ct, cc, it, ip : integer := 0;
  begin
    if rising_edge(clk) then
      if mon_clr = '1' then
        ct := 0; cc := 0; it := 0; ip := 0;
        prev_valid := false; prev_se := '0'; prev_cells := cells_o;
      else
        -- cells_o now shows the result of the PREVIOUS edge; it was a shift edge iff prev_se='1'
        if prev_se = '1' then
          ct := ct + popcount(cells_o xor prev_cells);
          cc := cc + 1;
        end if;
        prev_cells := cells_o;
        prev_se    := scan_en_o;
        if scan_en_o = '1' then
          if prev_valid then
            it := it + popcount(scan_in_o xor prev_sin);
            ip := ip + N_CHAINS;
          end if;
          prev_sin := scan_in_o; prev_valid := true;
        else
          prev_valid := false;
        end if;
      end if;
      cell_tog <= ct; cell_cyc <= cc; in_tog <= it; in_pairs <= ip;
    end if;
  end process;

  ---------------------------------------------------------------- experiments
  stim : process
    file f : text open write_mode is "lbist_results.csv";
    variable l : line;
    variable sig_conv, sig_26, sig_26b, sig_tmp : std_logic_vector(31 downto 0);

    procedure run_cfg (constant tc   : in std_logic;
                       constant tv   : in integer;
                       constant name : in string;
                       variable sg   : out std_logic_vector(31 downto 0)) is
      variable t0, t1 : time;
      variable cyc    : integer;
      variable ir, cr, target : real;
    begin
      rst <= '1'; mon_clr <= '1'; start <= '0';
      tc_en <= tc; t <= std_logic_vector(to_unsigned(tv, 8));
      wait for 40 ns;
      wait until rising_edge(clk);
      rst <= '0'; mon_clr <= '0';
      wait until rising_edge(clk);
      start <= '1'; t0 := now;
      wait until rising_edge(clk);
      start <= '0';
      wait until done = '1' for 5 ms;
      assert done = '1' report "TIMEOUT waiting for LBIST done" severity failure;
      t1 := now;
      wait until rising_edge(clk);
      wait until rising_edge(clk);
      wait for 1 ns;
      cyc := (t1 - t0) / 10 ns;
      ir  := real(in_tog)   / real(in_pairs) * 100.0;
      cr  := real(cell_tog) / real(cell_cyc * N_CELLS) * 100.0;
      if tc = '1' then target := real(tv) / 256.0 * 100.0; else target := 50.0; end if;
      sg := signature;
      report name & " | target=" & real'image(target) & "% | scan-in toggle=" & real'image(ir) &
             "% | cell toggle=" & real'image(cr) & "% | cycles=" & integer'image(cyc) &
             " | MISR=" & to_hex(signature) severity note;
      write(l, name);  write(l, string'(","));
      write(l, target, right, 0, 3);  write(l, string'(","));
      write(l, ir, right, 0, 3);      write(l, string'(","));
      write(l, cr, right, 0, 3);      write(l, string'(","));
      write(l, cyc);                  write(l, string'(","));
      write(l, to_hex(signature));
      writeline(f, l);
    end procedure;
  begin
    write(l, string'("config,target_pct,scanin_toggle_pct,cell_toggle_pct,cycles,misr"));
    writeline(f, l);

    run_cfg('0', 128, "CONVENTIONAL", sig_conv);
    run_cfg('1',  13, "TC_T13",       sig_tmp);
    run_cfg('1',  26, "TC_T26",       sig_26);
    run_cfg('1',  51, "TC_T51",       sig_tmp);
    run_cfg('1',  77, "TC_T77",       sig_tmp);
    run_cfg('1', 128, "TC_T128",      sig_tmp);
    run_cfg('1',  26, "TC_T26_repeat", sig_26b);

    assert sig_26 = sig_26b report "FAIL: MISR signature not reproducible" severity error;
    if sig_26 = sig_26b then
      report "Signature reproducibility check PASSED" severity note;
    end if;
    report "Expected test cycles per run = N*(L+1)+L = " &
           integer'image(N_PAT*(CHAIN_LEN+1)+CHAIN_LEN) & " (+1 for start handshake)" severity note;
    file_close(f);
    fin <= true;
    wait;
  end process;
end architecture sim;
