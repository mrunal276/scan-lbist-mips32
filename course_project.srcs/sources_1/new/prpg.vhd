-- prpg.vhd : 32-bit LFSR (x^32+x^22+x^2+x+1, primitive) + XOR phase shifter.
-- Advances only when en='1' (during scan shift).  Output r = 128 pseudo-random
-- bits per cycle (8 per scan chain), each the XOR of 3 LFSR bits.
library ieee;
use ieee.std_logic_1164.all;
use work.lbist_pkg.all;

entity prpg is
  port (
    clk, rst : in  std_logic;
    en       : in  std_logic;
    r        : out std_logic_vector(N_PS-1 downto 0)
  );
end entity prpg;

architecture rtl of prpg is
  constant SEED : std_logic_vector(31 downto 0) := x"1A2B3C4D";   -- must be non-zero
  signal q : std_logic_vector(31 downto 0) := SEED;
begin
  process (clk)
    variable fb : std_logic;
  begin
    if rising_edge(clk) then
      if rst = '1' then
        q <= SEED;
      elsif en = '1' then
        fb := q(31) xor q(21) xor q(1) xor q(0);
        q  <= q(30 downto 0) & fb;
      end if;
    end if;
  end process;

  gen_ps : for m in 0 to N_PS-1 generate
    r(m) <= q(PS_TAB(m,0)) xor q(PS_TAB(m,1)) xor q(PS_TAB(m,2));
  end generate gen_ps;
end architecture rtl;
