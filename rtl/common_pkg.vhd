package common_pkg is

  pure function log2 (num : natural) return natural;

  pure function to_integer (bool : boolean) return integer;

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

pure function to_integer (bool : boolean) return integer is
begin
  if (bool) then
    return 1;
  else
    return 0;
  end if;
end function to_integer;

end package body;