-- regfile.vhd : 32 x 32 register file, 2 async read ports, 1 sync write port.
-- Write-through: a read of the register being written in the same cycle
-- returns the new data (resolves the WB -> ID hazard). $0 is hard-wired to 0.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.mips_pkg.all;

entity regfile is
  port (
    clk, rst  : in  std_logic;
    we        : in  std_logic;
    ra1, ra2  : in  reg_addr_t;
    wa        : in  reg_addr_t;
    wd        : in  word_t;
    rd1, rd2  : out word_t
  );
end entity regfile;

architecture rtl of regfile is
  type reg_array_t is array (0 to 31) of word_t;
  signal regs : reg_array_t := (others => ZERO32);
begin
  process (clk)
  begin
    if rising_edge(clk) then
      if rst = '1' then
        regs <= (others => ZERO32);
      elsif we = '1' and wa /= "00000" then
        regs(to_integer(unsigned(wa))) <= wd;
      end if;
    end if;
  end process;

  rd1 <= ZERO32 when ra1 = "00000" else
         wd     when (we = '1' and wa = ra1) else
         regs(to_integer(unsigned(ra1)));

  rd2 <= ZERO32 when ra2 = "00000" else
         wd     when (we = '1' and wa = ra2) else
         regs(to_integer(unsigned(ra2)));
end architecture rtl;
