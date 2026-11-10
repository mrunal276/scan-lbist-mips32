-- misr.vhd : 32-bit multiple-input signature register (same polynomial as PRPG).
-- 16 scan-out bits are XORed into stages 0..15.
library ieee;
use ieee.std_logic_1164.all;
use work.lbist_pkg.all;

entity misr is
  port (
    clk, rst : in  std_logic;
    en       : in  std_logic;
    din      : in  std_logic_vector(N_CHAINS-1 downto 0);
    sig      : out std_logic_vector(31 downto 0)
  );
end entity misr;

architecture rtl of misr is
  signal m : std_logic_vector(31 downto 0) := (others => '0');
begin
  process (clk)
    variable fb : std_logic;
    variable n  : std_logic_vector(31 downto 0);
  begin
    if rising_edge(clk) then
      if rst = '1' then
        m <= (others => '0');
      elsif en = '1' then
        fb := m(31) xor m(21) xor m(1) xor m(0);
        n  := m(30 downto 0) & fb;
        n(N_CHAINS-1 downto 0) := n(N_CHAINS-1 downto 0) xor din;
        m <= n;
      end if;
    end if;
  end process;
  sig <= m;
end architecture rtl;
