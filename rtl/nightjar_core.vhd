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

        wb_imem_addr : out std_logic_vector(log2ceil(G_IMEM_DEPTH) - 1 downto 0);
        wb_imem_data : in std_logic_vector(31 downto 0);
        wb_imem_stb  : out std_logic; -- STB_O
        wb_imem_ack  : in std_logic;  -- ACK_I
        wb_imem_cyc  : out std_logic; -- CYC_O

        --------------------------------------
        -- Data memory interface (Wishbone) --
        --------------------------------------

        wb_dmem_addr  : out std_logic_vector(log2ceil(G_IMEM_DEPTH) - 1 downto 0);
        wb_dmem_rdata : in std_logic_vector(31 downto 0); -- 1 x 32 bits
        wb_dmem_wdata : out std_logic_vector(31 downto 0);
        wb_dmem_req   : out std_logic; -- STB_O
        wb_dmem_ack   : in std_logic;  -- ACK_I
        wb_dmem_cyc   : out std_logic  -- CYC_O

    );
end entity nightjar_core;

architecture rtl of nightjar_core is
begin

    --------------
    -- Frontend --
    --------------

    x_frontend : entity work.frontend
        generic map(
            G_IMEM_DEPTH => G_IMEM_DEPTH
        )
        port map
        (
            clk => sys_clk,
            rst => sys_rst,

            instr_addr       => instr_addr,
            instr_addr_valid => instr_addr_valid,
            instr_addr_ready => instr_addr_ready,
            instr_data       => instr_data,
            instr_data_valid => instr_data_valid,
            instr_data_ready => instr_data_ready,
            wb_imem_addr     => wb_imem_addr,
            wb_imem_data     => wb_imem_data,
            wb_imem_stb      => wb_imem_stb,
            wb_imem_ack      => wb_imem_ack,
            wb_imem_cyc      => wb_imem_cyc
        );
end architecture rtl;