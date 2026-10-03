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
--              The G_PRIORITISE_READS generic is used to dictate which operation is prioritised,
--              when two are requested at once. For interfaces which can handle simultaneous
--              reading and writing, this only relates to address collisions.
-- Remarks:     Only one operation can happen on the Wishbone bus at a time.
--------------------------------------------------------------------------------------------------
--------------------------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity wb_mem_ctrl is
    generic (
        G_ADDR_WIDTH        : positive := 32;
        G_DATA_WIDTH        : positive := 32;
        G_PRIORITISE_READS  : boolean  := false;
        G_RETRY_TIMEOUT_CYC : positive := 10
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

    -- Declare rd/wr request buffers
    type req_buf_t is record
        valid   : std_logic;
        consume : std_logic; -- Combinational signal to trigger update
        addr    : std_logic_vector(G_ADDR_WIDTH - 1 downto 0);
        byte_en : std_logic_vector(((G_DATA_WIDTH + 7) / 8) - 1 downto 0); -- Write only
        data    : std_logic_vector(G_DATA_WIDTH - 1 downto 0);             -- Write only
    end record;
    signal rd_req_buf : req_buf_t;
    signal wr_req_buf : req_buf_t;

    -- FSM states
    type state_t is (IDLE, RD_STB, RD_ACK, RD_RTY_WAIT, WR_STB, WR_ACK, WR_RTY_WAIT, FSM_ERROR);
    signal state      : state_t;
    signal next_state : state_t;

begin

    -----------------------
    -- Request buffering --
    -----------------------

    -- Assert ready when the request buffer contents will be otherwise empty on the next rising edge
    rd_req_ready <= (not rd_req_buf.valid) or rd_req_buf.consume;
    wr_req_ready <= (not wr_req_buf.valid) or wr_req_buf.consume;

    -- Process to update the request buffers
    req_buf_proc : process (clk) is
    begin
        if (rising_edge(clk)) then

            -- Invalidate upon consumption (these statements can be overridden by an incoming request)
            if (rd_req_buf.consume = '1') then
                rd_req_buf.valid <= '0';
            end if;
            if (wr_req_buf.consume = '1') then
                wr_req_buf.valid <= '0';
            end if;

            -- Buffer read requests
            if (rd_req_valid = '1' and rd_req_ready = '1') then
                rd_req_buf.valid <= '1';
                rd_req_buf.addr  <= rd_req_addr;
            end if;

            -- Buffer write requests
            if (wr_req_valid = '1' and wr_req_ready = '1') then
                wr_req_buf.valid   <= '1';
                wr_req_buf.addr    <= wr_req_addr;
                wr_req_buf.byte_en <= wr_req_byte_en;
                wr_req_buf.data    <= wr_req_data;
            end if;

            -- Initialise upon reset
            if (rst = '1') then
                rd_req_buf.valid <= '0';
                wr_req_buf.valid <= '0';
            end if;
        end if;
    end process;

    --------------------------------
    -- Finite State Machine (FSM) --
    --------------------------------

    -- Combinational process to decide the next state
    next_state_proc : process (rst, state, rd_req_buf, wr_req_buf, rd_req_valid, rd_req_ready, wr_req_valid, wr_req_ready) is
    begin
        case (state) is

            when IDLE =>

                -- Respond to a read or write request
                if (G_PRIORITISE_READS) then
                    if (rd_req_buf.valid = '1' or (rd_req_valid = '1' and rd_req_ready = '1')) then
                        next_state <= RD_STB;
                    elsif (wr_req_buf.valid = '1' or (wr_req_valid = '1' and wr_req_ready = '1')) then
                        next_state <= WR_STB;
                    end if;
                else
                    if (wr_req_buf.valid = '1' or (wr_req_valid = '1' and wr_req_ready = '1')) then
                        next_state <= WR_STB;
                    elsif (rd_req_buf.valid = '1' or (rd_req_valid = '1' and rd_req_ready = '1')) then
                        next_state <= RD_STB;
                    end if;
                end if;

            when RD_STB =>
                next_state <= RD_ACK;

            when RD_ACK =>
                if (wb_mem_ack = '1' or wb_mem_err = '1') then

                    -- Respond to a write or read request, or simply return to IDLE
                    if (G_PRIORITISE_READS) then
                        if (rd_req_buf.valid = '1' or (rd_req_valid = '1' and rd_req_ready = '1')) then
                            next_state <= RD_STB;
                        elsif (wr_req_buf.valid = '1' or (wr_req_valid = '1' and wr_req_ready = '1')) then
                            next_state <= WR_STB;
                        else
                            next_state <= IDLE;
                        end if;
                    else
                        if (wr_req_buf.valid = '1' or (wr_req_valid = '1' and wr_req_ready = '1')) then
                            next_state <= WR_STB;
                        elsif (rd_req_buf.valid = '1' or (rd_req_valid = '1' and rd_req_ready = '1')) then
                            next_state <= RD_STB;
                        else
                            next_state <= IDLE;
                        end if;
                    end if;

                    -- If a retry is needed, wait for a while
                elsif (wb_mem_rty = '1') then
                    next_state <= RD_RTY_WAIT;
                end if;

            when RD_RTY_WAIT => -- TODO

            when WR_STB =>
                next_state <= WR_ACK;

            when WR_ACK =>
                if (wb_mem_ack = '1' or wb_mem_err = '1') then

                    -- Respond to a write or read request, or simply return to IDLE
                    if (G_PRIORITISE_READS) then
                        if (rd_req_buf.valid = '1' or (rd_req_valid = '1' and rd_req_ready = '1')) then
                            next_state <= RD_STB;
                        elsif (wr_req_buf.valid = '1' or (wr_req_valid = '1' and wr_req_ready = '1')) then
                            next_state <= WR_STB;
                        else
                            next_state <= IDLE;
                        end if;
                    else
                        if (wr_req_buf.valid = '1' or (wr_req_valid = '1' and wr_req_ready = '1')) then
                            next_state <= WR_STB;
                        elsif (rd_req_buf.valid = '1' or (rd_req_valid = '1' and rd_req_ready = '1')) then
                            next_state <= RD_STB;
                        else
                            next_state <= IDLE;
                        end if;
                    end if;

                    -- If a retry is needed, wait for a while
                elsif (wb_mem_rty = '1') then
                    next_state <= WR_RTY_WAIT;
                end if;

            when WR_RTY_WAIT => -- TODO

            when FSM_ERROR =>
                next_state <= IDLE;

            when others =>
                next_state <= FSM_ERROR;
        end case;
    end process;

    -- Process to advance the state
    adv_state_proc : process (clk) is
    begin
        if (rising_edge(clk)) then
            state <= next_state;
            if (rst = '1') then
                state <= IDLE;
            end if;
        end if;
    end process;

    -- Process to drive signals in response to the state machine
    ctrl_proc : process (clk) is
    begin
        if (rising_edge(clk)) then
            rd_req_buf.consume <= '0';
            wr_req_buf.consume <= '0';

            -- Consume the read/write requests
            if (next_state = RD_STB) then
                rd_req_buf.consume <= '1';
            end if;
            if (next_state = WR_STB) then
                wr_req_buf.consume <= '1';
            end if;

            -- Assert CYC_O and STB_O during the RD_STB and WR_STB states
            if (next_state = RD_STB or next_state = WR_STB) then
                wb_mem_cyc <= '1';
                wb_mem_stb <= '1';
            end if;

            -- When an acknowledgement or an error is received, de-assert CYC_O and STB_O
            if (wb_mem_ack = '1' or wb_mem_err = '1') then
                wb_mem_cyc <= '0';
                wb_mem_stb <= '0';
            end if;

            -- Initialise upon reset
            if (rst = '1') then
                wb_mem_cyc         <= '0';
                wb_mem_stb         <= '0';
                rd_req_buf.consume <= '0';
                wr_req_buf.consume <= '0';
            end if;
        end if;
    end process;

    -- TODO:
    -- rd_req_buf.consume <= '0';
    -- wr_req_buf.consume <= '0';

end architecture;