-- bist_ctrl.vhd : LBIST controller.
-- Sequence: SHIFT(L cycles) -> CAPTURE(1) -> SHIFT -> CAPTURE ... -> final SHIFT -> FINISH
-- N patterns => N captures, N+1 shift phases.  Test time = N*(L+1)+L clock cycles.
-- The last shift phase unloads the final response into the MISR.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.lbist_pkg.all;

entity bist_ctrl is
  port (
    clk, rst   : in  std_logic;
    start      : in  std_logic;
    n_patterns : in  std_logic_vector(15 downto 0);
    scan_en    : out std_logic;
    busy       : out std_logic;
    done       : out std_logic
  );
end entity bist_ctrl;

architecture rtl of bist_ctrl is
  type state_t is (IDLE, SHIFT, CAPTURE, FINISH);
  signal st  : state_t := IDLE;
  signal cnt : integer range 0 to CHAIN_LEN-1 := 0;
  signal pat : unsigned(15 downto 0) := (others => '0');
begin
  process (clk)
  begin
    if rising_edge(clk) then
      if rst = '1' then
        st <= IDLE; cnt <= 0; pat <= (others => '0');
      else
        case st is
          when IDLE =>
            if start = '1' then
              st <= SHIFT; cnt <= 0; pat <= (others => '0');
            end if;
          when SHIFT =>
            if cnt = CHAIN_LEN-1 then
              cnt <= 0;
              if pat = unsigned(n_patterns) then st <= FINISH;
              else                               st <= CAPTURE;
              end if;
            else
              cnt <= cnt + 1;
            end if;
          when CAPTURE =>
            pat <= pat + 1;
            st  <= SHIFT;
          when FINISH =>
            null;                                   -- hold until rst
        end case;
      end if;
    end if;
  end process;

  scan_en <= '1' when st = SHIFT else '0';
  busy    <= '1' when (st = SHIFT or st = CAPTURE) else '0';
  done    <= '1' when st = FINISH else '0';
end architecture rtl;
