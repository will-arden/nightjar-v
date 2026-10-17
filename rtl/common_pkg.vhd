library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package common_pkg is

    function log2 (num         : natural) return natural;
    function log2ceil (num     : natural) return natural;
    function to_integer (bool  : boolean) return integer;
    function to_uint (slv      : std_logic_vector) return integer;
    function to_std_logic(bool : boolean) return std_logic;
    function slv_uadd (slv : std_logic_vector; num : integer) return std_logic_vector;
    function pad (slv : std_logic_vector; n : positive) return std_logic_vector;
    function ones_count (slv   : std_logic_vector) return natural;
    function zeros_count (slv  : std_logic_vector) return natural;

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
    end function;

    function log2ceil(num : natural) return natural is
    begin
        for i in 0 to natural'high loop
            if (2 ** i) >= num then
                return i;
            end if;
        end loop;
    end function;

    function to_integer (bool : boolean) return integer is
    begin
        if (bool) then
            return 1;
        else
            return 0;
        end if;
    end function;

    function to_uint (slv : std_logic_vector) return integer is
    begin
        return to_integer(unsigned(slv));
    end function;

    function to_std_logic(bool : boolean) return std_logic is
    begin
        if (bool) then
            return '1';
        else
            return '0';
        end if;
    end function;

    function slv_uadd (slv : std_logic_vector; num : integer) return std_logic_vector is
    begin
        return std_logic_vector(to_unsigned(to_uint(slv) + num, slv'length));
    end function;

    function pad (slv : std_logic_vector; n : positive) return std_logic_vector is
        variable padded : std_logic_vector(n - 1 downto 0) := (others => '0');
    begin
        padded(slv'length - 1 downto 0) := slv;
        return padded;
    end function;

    function ones_count(slv : std_logic_vector) return natural is
        variable v_count        : natural := 0;
    begin
        for b in 0 to (slv'length - 1) loop
            if (slv(b) = '1') then
                v_count := v_count + 1;
            end if;
        end loop;
        return v_count;
    end function;

    function zeros_count(slv : std_logic_vector) return natural is
        variable v_count         : natural := 0;
    begin
        for b in 0 to (slv'length - 1) loop
            if (slv(b) = '0') then
                v_count := v_count + 1;
            end if;
        end loop;
        return v_count;
    end function;

end package body;
