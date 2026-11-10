-- alu.vhd : 32-bit combinational ALU
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.mips_pkg.all;

entity alu is
  port (
    a, b  : in  word_t;
    shamt : in  std_logic_vector(4 downto 0);
    op    : in  alu_op_t;
    y     : out word_t
  );
end entity alu;

architecture rtl of alu is
begin
  process (a, b, shamt, op)
  begin
    case op is
      when ALU_AND => y <= a and b;
      when ALU_OR  => y <= a or b;
      when ALU_ADD => y <= std_logic_vector(unsigned(a) + unsigned(b));
      when ALU_XOR => y <= a xor b;
      when ALU_NOR => y <= a nor b;
      when ALU_SUB => y <= std_logic_vector(unsigned(a) - unsigned(b));
      when ALU_SLT =>
        if signed(a) < signed(b) then y <= x"00000001";
        else                          y <= ZERO32;
        end if;
      when ALU_SLL => y <= std_logic_vector(shift_left (unsigned(b), to_integer(unsigned(shamt))));
      when ALU_SRL => y <= std_logic_vector(shift_right(unsigned(b), to_integer(unsigned(shamt))));
      when ALU_LUI => y <= b(15 downto 0) & x"0000";
      when others  => y <= ZERO32;
    end case;
  end process;
end architecture rtl;
