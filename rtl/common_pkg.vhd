library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package common_pkg is

  function log2 (num        : natural) return natural;
  function to_integer (bool : boolean) return integer;
  function pad (slv : std_logic_vector; n : positive) return std_logic_vector;

end package common_pkg;

package body common_pkg is

  function log2 (num : natural) return natural is
    variable q         : integer := num - 1;
    variable i         : integer := 0;
  begin
    while (q > 0) loop
      q := (q / 2);
      i := i + 1;
    end loop;
    return i;
  end function log2;

  function to_integer (bool : boolean) return integer is
  begin
    if (bool) then
      return 1;
    else
      return 0;
    end if;
  end function to_integer;

  function pad (slv : std_logic_vector; n : positive) return std_logic_vector is
    variable padded : std_logic_vector(n - 1 downto 0) := (others => '0');
  begin
    padded(slv'length - 1 downto 0) := slv;
    return padded;
  end function pad;

end package body;