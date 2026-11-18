-- tb_fault_sim.vhd : Fast Stuck-at fault coverage evaluation across all 16 scan chains
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
library std;
use std.textio.all;
use work.mips_pkg.all;
use work.lbist_pkg.all;

entity tb_fault_sim is
end entity tb_fault_sim;

architecture sim of tb_fault_sim is
  constant N_PAT : integer := 100;

  signal clk        : std_logic := '0';
  signal rst        : std_logic := '1';
  signal start      : std_logic := '0';
  signal tc_en      : std_logic := '0';
  signal t          : std_logic_vector(7 downto 0) := x"80";
  signal n_patterns : std_logic_vector(15 downto 0) := std_logic_vector(to_unsigned(N_PAT, 16));
  signal done       : std_logic;
  signal scan_en_o  : std_logic;
  signal cells_o    : std_logic_vector(N_CELLS-1 downto 0);
  signal hw_sig     : std_logic_vector(31 downto 0);
  signal fin        : boolean := false;

  -- Fault injection control (16 scan-chain outputs x 2 polarities = 32 single stuck-at faults)
  signal fault_en   : std_logic := '0';
  signal fault_ch   : integer range 0 to N_CHAINS-1 := 0;
  signal fault_val  : std_logic := '0';
  signal obs_sig    : std_logic_vector(31 downto 0) := (others => '0');

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
    port map (
      clk => clk, rst => rst, start => start, tc_en => tc_en, t => t,
      n_patterns => n_patterns, busy => open, done => done,
      signature => hw_sig, scan_en_o => scan_en_o,
      scan_in_o => open, cells_o => cells_o
    );

  clk_gen : process
  begin
    while not fin loop
      clk <= '0'; wait for 5 ns;
      clk <= '1'; wait for 5 ns;
    end loop;
    wait;
  end process;

  -- Reference 32-bit MISR compacting the 16 scan-chain outputs with fault injection
  obs_misr : process(clk)
    variable v_sout : std_logic_vector(N_CHAINS-1 downto 0);
    variable fb     : std_logic;
    variable nxt    : std_logic_vector(31 downto 0);
  begin
    if rising_edge(clk) then
      if rst = '1' then
        obs_sig <= (others => '0');
      elsif scan_en_o = '1' then
        for j in 0 to N_CHAINS-1 loop
          v_sout(j) := cells_o(j*CHAIN_LEN + CHAIN_LEN - 1);
        end loop;
        if fault_en = '1' then
          v_sout(fault_ch) := fault_val;
        end if;
        fb := obs_sig(31) xor obs_sig(21) xor obs_sig(1) xor obs_sig(0);
        nxt := obs_sig(30 downto 0) & fb;
        for j in 0 to N_CHAINS-1 loop
          nxt(j) := nxt(j) xor v_sout(j);
        end loop;
        obs_sig <= nxt;
      end if;
    end if;
  end process;

  stim : process
    file f : text open write_mode is "fault_coverage.csv";
    variable l : line;
    variable golden_sig, test_sig : std_logic_vector(31 downto 0);
    variable detected : integer;
    variable cov_pct  : real;

    procedure run_once(constant tc : in std_logic;
                       constant tv : in integer;
                       variable sg : out std_logic_vector(31 downto 0)) is
    begin
      rst <= '1'; start <= '0';
      tc_en <= tc; t <= std_logic_vector(to_unsigned(tv, 8));
      wait for 30 ns;
      wait until rising_edge(clk);
      rst <= '0';
      wait until rising_edge(clk);
      start <= '1';
      wait until rising_edge(clk);
      start <= '0';
      wait until done = '1' for 2 ms;
      assert done = '1' report "TIMEOUT in fault sim" severity failure;
      wait until rising_edge(clk);
      sg := obs_sig;
    end procedure;

    procedure eval_config(constant tc   : in std_logic;
                          constant tv   : in integer;
                          constant name : in string) is
    begin
      fault_en <= '0';
      wait for 1 ns;
      run_once(tc, tv, golden_sig);

      detected := 0;
      for ch in 0 to N_CHAINS-1 loop
        fault_ch <= ch; fault_val <= '0'; fault_en <= '1';
        wait for 1 ns;
        run_once(tc, tv, test_sig);
        if test_sig /= golden_sig then
          detected := detected + 1;
        end if;

        fault_ch <= ch; fault_val <= '1'; fault_en <= '1';
        wait for 1 ns;
        run_once(tc, tv, test_sig);
        if test_sig /= golden_sig then
          detected := detected + 1;
        end if;
      end loop;

      fault_en <= '0';
      cov_pct := (real(detected) / 32.0) * 100.0;

      report name & " | Detected=" & integer'image(detected) & "/32 (" &
             real'image(cov_pct) & "%) | Golden MISR=" & to_hex(hw_sig) severity note;

      write(l, name); write(l, string'(","));
      write(l, detected); write(l, string'(",32,"));
      write(l, cov_pct, right, 0, 2); write(l, string'(","));
      write(l, to_hex(hw_sig));
      writeline(f, l);
    end procedure;

  begin
    write(l, string'("config,detected_faults,total_faults,fault_coverage_pct,golden_misr"));
    writeline(f, l);

    eval_config('0', 128, "CONVENTIONAL");
    eval_config('1',  13, "TC_T13");
    eval_config('1',  26, "TC_T26");
    eval_config('1',  51, "TC_T51");
    eval_config('1',  77, "TC_T77");
    eval_config('1', 128, "TC_T128");

    file_close(f);
    report "Fault simulation complete -> fault_coverage.csv written." severity note;
    fin <= true;
    wait;
  end process;
end architecture sim;