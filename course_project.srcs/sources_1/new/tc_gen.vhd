-- tc_gen.vhd : PROPOSED programmable Toggle-Controlled pattern modifier.
--   tc_en = 0 : conventional LBIST  -> scan_in(j) = phase-shifter bit (50 % toggle)
--   tc_en = 1 : toggle-controlled   -> tog = (r_j < T) ; d <= d xor tog ; scan_in = d
--               P(toggle) = T/256 ;  legal T = 1..255  (T=128 -> 50 %)
-- One 8-bit comparator + one T-flip-flop per chain; no extra shift cycles.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.lbist_pkg.all;

entity tc_gen is
  port (
    clk, rst : in  std_logic;
    en       : in  std_logic;                                -- shift enable
    tc_en    : in  std_logic;                                -- 1 = toggle control on
    t        : in  std_logic_vector(7 downto 0);             -- toggle threshold
    r        : in  std_logic_vector(N_PS-1 downto 0);        -- from PRPG
    sin      : out std_logic_vector(N_CHAINS-1 downto 0)     -- to scan chains
  );
end entity tc_gen;

architecture rtl of tc_gen is
  signal d   : std_logic_vector(N_CHAINS-1 downto 0) := (others => '0');
  signal tog : std_logic_vector(N_CHAINS-1 downto 0);
begin
  gen_ch : for j in 0 to N_CHAINS-1 generate
    tog(j) <= '1' when unsigned(r(8*j+7 downto 8*j)) < unsigned(t) else '0';
    sin(j) <= d(j) when tc_en = '1' else r(8*j);
  end generate gen_ch;

  process (clk)
  begin
    if rising_edge(clk) then
      if rst = '1' then
        d <= (others => '0');
      elsif en = '1' then
        d <= d xor tog;
      end if;
    end if;
  end process;
end architecture rtl;
