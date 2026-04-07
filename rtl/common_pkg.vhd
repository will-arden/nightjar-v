package common_pkg is

  pure function log2 (num : natural) return natural;

end package common_pkg;

package body common_pkg is

  pure function log2 (num : natural) return natural is
  variable q              : integer := num - 1;
  variable i              : integer := 0;
begin
  while (q > 0) loop
    q := (q / 2);
    i := i + 1;
  end loop;
  return i;
end function log2;

end package body;