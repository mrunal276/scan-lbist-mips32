-- lbist_top.vhd : STUMPS-style LBIST around the full-scan MIPS32 core
--   bist_ctrl -> prpg -> tc_gen -> 16 scan chains (mips_scan_core) -> misr
-- tc_en=0 : conventional LBIST (baseline).  tc_en=1 : proposed toggle control, rate = t/256.
library ieee;
use ieee.std_logic_1164.all;
use work.mips_pkg.all;
use work.lbist_pkg.all;

entity lbist_top is
  port (
    clk, rst   : in  std_logic;
    start      : in  std_logic;
    tc_en      : in  std_logic;
    t          : in  std_logic_vector(7 downto 0);
    n_patterns : in  std_logic_vector(15 downto 0);
    busy, done : out std_logic;
    signature  : out std_logic_vector(31 downto 0);
    -- observation points for the simulation testbench
    scan_en_o  : out std_logic;
    scan_in_o  : out std_logic_vector(N_CHAINS-1 downto 0);
    cells_o    : out std_logic_vector(N_CELLS-1 downto 0)
  );
end entity lbist_top;

architecture rtl of lbist_top is
  signal scan_en  : std_logic;
  signal r        : std_logic_vector(N_PS-1 downto 0);
  signal sin, sout: std_logic_vector(N_CHAINS-1 downto 0);
  signal d_imem_addr, d_dmem_addr, d_dmem_wdata : word_t;
  signal d_dmem_we : std_logic;
begin
  ctrl : entity work.bist_ctrl
    port map (clk => clk, rst => rst, start => start, n_patterns => n_patterns,
              scan_en => scan_en, busy => busy, done => done);

  gen : entity work.prpg
    port map (clk => clk, rst => rst, en => scan_en, r => r);

  tcg : entity work.tc_gen
    port map (clk => clk, rst => rst, en => scan_en, tc_en => tc_en, t => t, r => r, sin => sin);

  cut : entity work.mips_scan_core
    port map (clk => clk, rst => rst, scan_en => scan_en, test_mode => '1',
              scan_in => sin, scan_out => sout,
              imem_addr => d_imem_addr, imem_data => ZERO32,
              dmem_addr => d_dmem_addr, dmem_wdata => d_dmem_wdata, dmem_we => d_dmem_we,
              dmem_rdata => ZERO32, cells_o => cells_o);

  cmp : entity work.misr
    port map (clk => clk, rst => rst, en => scan_en, din => sout, sig => signature);

  scan_en_o <= scan_en;
  scan_in_o <= sin;
end architecture rtl;
