--------------------------------------------------------------------------------------------------
--                                      ~   nightjar-v   ~                                      --
--------------------------------------------------------------------------------------------------
-- Filename:    wb_mem_ctrl.vhd
-- Author:      Will Arden
-- Date:        3rd October 2026
-- Brief:       Wishbone memory controller.
-- Description: This is a Wishbone memory controller which can accept read/write requests and act
--              accordingly over the Wishbone interface to external memory. This module is
--              designed such that it can be switched out (relatively painlessly) for an
--              alternative interface, such as AXI4-Lite.
-- Remarks:     Only one operation can happen on the Wishbone bus at a time.
--------------------------------------------------------------------------------------------------
--------------------------------------------------------------------------------------------------


library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity wb_mem_ctrl is
    generic (
        G_ADDR_WIDTH : positive := 32;
        G_DATA_WIDTH : positive := 32
    );
    port (
        
        clk : in std_logic;
        rst : in std_logic;

        --------------------
        -- CPU Interfaces --
        --------------------

        -- Read request interface
        rd_req_valid : in std_logic;
        rd_req_ready : out std_logic;
        rd_req_addr  : in std_logic_vector(G_ADDR_WIDTH - 1 downto 0);

        -- Write request interface
        wr_req_valid   : in std_logic;
        wr_req_ready   : out std_logic;
        wr_req_addr    : in std_logic_vector(G_ADDR_WIDTH - 1 downto 0);
        wr_req_byte_en : in std_logic_vector((((G_DATA_WIDTH + 7) / 8)) - 1 downto 0);
        wr_req_data    : in std_logic_vector(G_DATA_WIDTH - 1 downto 0);

        -- Read response interface
        rd_resp_valid : out std_logic;
        rd_resp_ready : in std_logic;
        rd_resp_data  : out std_logic_vector(G_DATA_WIDTH - 1 downto 0);
        rd_resp_err   : out std_logic;

        ------------------------------------------
        -- External memory interface (Wishbone) --
        ------------------------------------------

        wb_mem_stb     : out std_logic;                                                 -- STB_O
        wb_mem_ack     : in std_logic;                                                  -- ACK_I
        wb_mem_cyc     : out std_logic;                                                 -- CYC_O
        wb_mem_err     : in std_logic;                                                  -- ERR_I
        wb_mem_rty     : in std_logic;                                                  -- RTY_I
        wb_mem_wr_en   : out std_logic;                                                 -- WE_O
        wb_mem_byte_en : out std_logic_vector((((G_DATA_WIDTH + 7) / 8)) - 1 downto 0); -- SEL_O
        wb_mem_addr    : out std_logic_vector(G_ADDR_WIDTH - 1 downto 0);               -- ADR_O
        wb_mem_rd_data : in std_logic_vector(G_DATA_WIDTH - 1 downto 0);                -- DAT_I
        wb_mem_wr_data : out std_logic_vector(G_DATA_WIDTH - 1 downto 0)                -- DAT_O

    );
end entity;

architecture rtl of wb_mem_ctrl is
begin
end architecture;