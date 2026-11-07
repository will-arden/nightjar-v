--------------------------------------------------------------------------------------------------
--                                      ~   nightjar-v   ~                                      --
--------------------------------------------------------------------------------------------------
-- Filename:    nj_global_pkg.vhd
-- Author:      Will Arden
-- Date:        7th November 2026
-- Brief:       Global package for constants, definitions and declarations.
-- Description: Global package for constants, definitions and declarations.
-- Remarks:     
--------------------------------------------------------------------------------------------------
--------------------------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;

package nj_global_pkg is

    constant C_DEBUG_COMPONENT_WB_MASTER : std_logic_vector(7 downto 0) := x"00";

end package;

package body nj_global_pkg is
end package body;