-- tb_mips32_scan.vhd : functional testbench for mips_scan_core (scan_en=0, test_mode=0)
-- Program: sum = 5+4+3+2+1 (loop, bne), store/load (load-use stall),
--          double, shift, slt, and store results.
-- Expected data memory: [0]=15 [1]=30 [2]=120 [3]=1

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.mips_pkg.all;
use work.lbist_pkg.all;

entity tb_mips32_scan is
end entity tb_mips32_scan;

architecture sim of tb_mips32_scan is
  signal clk  : std_logic := '0';
  signal rst  : std_logic := '1';
  signal done : boolean   := false;
  signal imem_addr, imem_data, dmem_addr, dmem_wdata, dmem_rdata : word_t := ZERO32;
  signal dmem_we : std_logic;
  signal scan_out : std_logic_vector(N_CHAINS-1 downto 0);
  signal cells_o  : std_logic_vector(N_CELLS-1 downto 0);

  type imem_t is array (0 to 63)  of word_t;
  type dmem_t is array (0 to 255) of word_t;

  constant PROG : imem_t := (
     0 => x"20010005",  -- addi $1,$0,5
     1 => x"20020000",  -- addi $2,$0,0
     2 => x"00411020",  -- loop: add  $2,$2,$1     (forwarding)
     3 => x"2021FFFF",  --       addi $1,$1,-1
     4 => x"1420FFFD",  --       bne  $1,$0,loop   (branch + flush)
     5 => x"AC020000",  -- sw   $2,0($0)
     6 => x"8C030000",  -- lw   $3,0($0)
     7 => x"00632020",  -- add  $4,$3,$3           (load-use stall)
     8 => x"AC040004",  -- sw   $4,4($0)
     9 => x"00042880",  -- sll  $5,$4,2
    10 => x"0044302A",  -- slt  $6,$2,$4
    11 => x"AC050008",  -- sw   $5,8($0)
    12 => x"AC06000C",  -- sw   $6,12($0)
    13 => x"0800000D",  -- halt: j 13
    others => x"00000000");

  signal dmem : dmem_t := (others => ZERO32);
begin
  dut : entity work.mips_scan_core
    port map (clk => clk, rst => rst, scan_en => '0', test_mode => '0',
              scan_in => (others => '0'), scan_out => scan_out,
              imem_addr => imem_addr, imem_data => imem_data,
              dmem_addr => dmem_addr, dmem_wdata => dmem_wdata, dmem_we => dmem_we,
              dmem_rdata => dmem_rdata, cells_o => cells_o);

  clk_gen : process
  begin
    while not done loop
      clk <= '0'; wait for 5 ns;
      clk <= '1'; wait for 5 ns;
    end loop;
    wait;
  end process;

  imem_data  <= PROG(to_integer(unsigned(imem_addr(7 downto 2))));
  dmem_rdata <= dmem(to_integer(unsigned(dmem_addr(9 downto 2))));

  dmem_wr : process (clk)
  begin
    if rising_edge(clk) and dmem_we = '1' then
      dmem(to_integer(unsigned(dmem_addr(9 downto 2)))) <= dmem_wdata;
    end if;
  end process;

  stim : process
  begin
    wait for 22 ns;  rst <= '0';
    wait for 1000 ns;
    assert dmem(0) = x"0000000F" report "FAIL mem[0] /= 15"  severity error;
    assert dmem(1) = x"0000001E" report "FAIL mem[1] /= 30"  severity error;
    assert dmem(2) = x"00000078" report "FAIL mem[2] /= 120" severity error;
    assert dmem(3) = x"00000001" report "FAIL mem[3] /= 1"   severity error;
    if dmem(0) = x"0000000F" and dmem(1) = x"0000001E" and
       dmem(2) = x"00000078" and dmem(3) = x"00000001" then
      report "SCAN-CORE functional test PASSED (scan insertion preserved behaviour)" severity note;
    end if;
    done <= true;
    wait;
  end process;
end architecture sim;
