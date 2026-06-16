library ieee;
use ieee.std_logic_1164.all;

use work.common_pkg.all;

entity nightjar_core is
    generic (
        G_IMEM_DEPTH : positive := 1024
    );
    port (

        sys_clk : in std_logic;
        sys_rst : in std_logic;

        ---------------------------------------------
        -- Instruction memory interface (Wishbone) --
        ---------------------------------------------

        -- Read bus
        wb_imem_raddr : out std_logic_vector(log2ceil(G_IMEM_DEPTH) - 1 downto 0);
        wb_imem_rdata : in std_logic_vector(63 downto 0); -- 2 x 32 bits

        -- Handshake signals
        wb_imem_rreq : out std_logic; -- STB_O
        wb_imem_ack  : in std_logic;  -- ACK_I

        --------------------------------------
        -- Data memory interface (Wishbone) --
        --------------------------------------

        -- Read bus
        wb_dmem_raddr : out std_logic_vector(log2ceil(G_IMEM_DEPTH) - 1 downto 0);
        wb_dmem_rdata : in std_logic_vector(31 downto 0);

        -- Write bus
        wb_dmem_waddr : out std_logic_vector(log2ceil(G_IMEM_DEPTH) - 1 downto 0);
        wb_dmem_wdata : out std_logic_vector(31 downto 0); -- 1 x 32 bits

        -- Handshake signals
        wb_dmem_req : out std_logic; -- STB_O
        wb_dmem_ack : in std_logic   -- ACK_I

    );
end entity nightjar_core;

architecture rtl of nightjar_core is
begin

    ----------------------------------------
    -- Instruction Memory Cache (i-cache) --
    ----------------------------------------

end architecture rtl;