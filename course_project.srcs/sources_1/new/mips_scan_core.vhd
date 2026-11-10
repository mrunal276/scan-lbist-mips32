-- mips_scan_core.vhd : full-scan version of the MIPS32 core.
--   * Every pipeline/PC/register-file flop is a scan cell (1390 cells)
--   * +64 input wrapper cells (imem_data, dmem_rdata) so test mode can control them
--   * +2 dummy cells to balance 16 chains x 91 cells = 1456
--   scan_en = 1 : every chain shifts one position (cell 0 <- scan_in)
--   scan_en = 0 : capture / functional clock (cells load next_state)
--   test_mode=1 : core inputs come from the wrapper cells instead of the pins
-- Cell map: cells(1389:0)=state, (1421:1390)=imem wrapper, (1453:1422)=dmem wrapper, rest dummy.
-- Chain j = cells(j*91 .. j*91+90); position 0 is nearest scan_in.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.mips_pkg.all;
use work.lbist_pkg.all;

entity mips_scan_core is
  port (
    clk, rst   : in  std_logic;
    scan_en    : in  std_logic;
    test_mode  : in  std_logic;
    scan_in    : in  std_logic_vector(N_CHAINS-1 downto 0);
    scan_out   : out std_logic_vector(N_CHAINS-1 downto 0);
    imem_addr  : out word_t;
    imem_data  : in  word_t;
    dmem_addr  : out word_t;
    dmem_wdata : out word_t;
    dmem_we    : out std_logic;
    dmem_rdata : in  word_t;
    cells_o    : out std_logic_vector(N_CELLS-1 downto 0)  -- for simulation monitoring
  );
end entity mips_scan_core;

architecture rtl of mips_scan_core is
  constant IMEM_CELL : integer := STATE_W;
  constant DMEM_CELL : integer := STATE_W + 32;
  signal cells : std_logic_vector(N_CELLS-1 downto 0) := (others => '0');
  signal next_state : std_logic_vector(STATE_W-1 downto 0);
  signal core_imem, core_dmem : word_t;
begin
  core_imem <= cells(IMEM_CELL+31 downto IMEM_CELL) when test_mode = '1' else imem_data;
  core_dmem <= cells(DMEM_CELL+31 downto DMEM_CELL) when test_mode = '1' else dmem_rdata;

  comb : entity work.mips_comb
    port map (rst => rst, state => cells(STATE_W-1 downto 0),
              imem_data => core_imem, dmem_rdata => core_dmem,
              next_state => next_state, imem_addr => imem_addr,
              dmem_addr => dmem_addr, dmem_wdata => dmem_wdata, dmem_we => dmem_we);

  scan_ffs : process (clk)
  begin
    if rising_edge(clk) then
      if rst = '1' then
        cells <= (others => '0');
      elsif scan_en = '1' then
        for j in 0 to N_CHAINS-1 loop
          cells(j*CHAIN_LEN) <= scan_in(j);
          for p in 1 to CHAIN_LEN-1 loop
            cells(j*CHAIN_LEN + p) <= cells(j*CHAIN_LEN + p - 1);
          end loop;
        end loop;
      else
        cells(STATE_W-1 downto 0)                 <= next_state;
        cells(IMEM_CELL+31 downto IMEM_CELL)      <= imem_data;
        cells(DMEM_CELL+31 downto DMEM_CELL)      <= dmem_rdata;
        cells(N_CELLS-1 downto DMEM_CELL+32)      <= (others => '0');
      end if;
    end if;
  end process scan_ffs;

  gen_so : for j in 0 to N_CHAINS-1 generate
    scan_out(j) <= cells(j*CHAIN_LEN + CHAIN_LEN - 1);
  end generate gen_so;

  cells_o <= cells;
end architecture rtl;
