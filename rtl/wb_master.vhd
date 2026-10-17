--------------------------------------------------------------------------------------------------
--                                      ~   nightjar-v   ~                                      --
--------------------------------------------------------------------------------------------------
-- Filename:    wb_master.vhd
-- Author:      Will Arden
-- Date:        11th October 2026
-- Brief:       Wishbone memory controller.
-- Description: This is a Wishbone memory controller which can accept read/write requests and act
--              accordingly over the Wishbone interface to external memory. This module is
--              designed such that it can be switched out (relatively painlessly) for an
--              alternative interface, such as AXI4-Lite.
--              The G_PRIORITISE_READS generic is used to dictate which operation is prioritised,
--              when two are requested at once. For interfaces that can handle simultaneous
--              reading and writing, this would only affect read-during-write collisions (check
--              implementation before assuming this behaviour).
-- Remarks:     Only one operation can happen on the Wishbone bus at a time.
--------------------------------------------------------------------------------------------------
--------------------------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.common_pkg.all;

entity wb_master is
    generic (
        G_ADDR_WIDTH        : positive := 32;
        G_DATA_WIDTH        : positive := 32;
        G_REQ_FIFO_SIZE     : natural  := 8;
        G_RESP_FIFO_SIZE    : natural  := 8;
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

        -- Response interface
        resp_valid   : out std_logic;
        resp_ready   : in std_logic;
        resp_rd      : out std_logic; -- '0': Write response; '1': Read response + data
        resp_rd_data : out std_logic_vector(G_DATA_WIDTH - 1 downto 0);
        resp_err     : out std_logic;

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

architecture rtl of wb_master is

    -- FSM states
    type state_t is (IDLE, STB, ACK, RTY, FSM_ERROR);
    signal state      : state_t;
    signal next_state : state_t;

    -- Declare a buffer to hold secondary requests while they are waiting to be executed
    type op_buf_t is record
        consume : std_logic;
        valid   : std_logic;
        wr_en   : std_logic;
        addr    : std_logic_vector(G_ADDR_WIDTH - 1 downto 0);
        data    : std_logic_vector(G_DATA_WIDTH - 1 downto 0);
        byte_en : std_logic_vector((((G_DATA_WIDTH + 7) / 8)) - 1 downto 0);
    end record;
    signal sec_buf : op_buf_t;

    -- FIFO data consists of (from MSB down to LSB):
    --      Read:
    --          - Valid
    --          - Address
    --      Write:
    --          - Valid
    --          - Address
    --          - Data
    --          - Byte-enable
    constant C_FIFO_WIDTH : natural := (2 * (1 + G_ADDR_WIDTH)) + G_DATA_WIDTH + ((G_DATA_WIDTH + 7) / 8);

    -- Declare FIFO interfacing signals
    type fifo_ctrl_t is record
        wr_valid : std_logic;
        wr_ready : std_logic;
        wr_data  : std_logic_vector(C_FIFO_WIDTH - 1 downto 0);
        rd_valid : std_logic;
        rd_ready : std_logic;
        rd_data  : std_logic_vector(C_FIFO_WIDTH - 1 downto 0);
        full     : std_logic;
        empty    : std_logic;
    end record;
    signal req_fifo : fifo_ctrl_t;

    -- Outputs from the request buffer
    signal rd_req_valid_in   : std_logic;
    signal rd_req_addr_in    : std_logic_vector(G_ADDR_WIDTH - 1 downto 0);
    signal wr_req_valid_in   : std_logic;
    signal wr_req_addr_in    : std_logic_vector(G_ADDR_WIDTH - 1 downto 0);
    signal wr_req_data_in    : std_logic_vector(G_DATA_WIDTH - 1 downto 0);
    signal wr_req_byte_en_in : std_logic_vector(((G_DATA_WIDTH + 7) / 8) - 1 downto 0);

    -- Declare primary/secondary request signals
    type req_t is record
        wr_en   : std_logic;
        valid   : std_logic;
        ready   : std_logic;
        addr    : std_logic_vector(G_ADDR_WIDTH - 1 downto 0);
        data    : std_logic_vector(G_DATA_WIDTH - 1 downto 0);
        byte_en : std_logic_vector((((G_DATA_WIDTH + 7) / 8)) - 1 downto 0);
    end record;
    signal pri_req : req_t;
    signal sec_req : req_t;

    -- Declare internal response signals
    signal resp_valid_out   : std_logic;
    signal resp_rd_out      : std_logic;
    signal resp_rd_data_out : std_logic_vector(G_DATA_WIDTH - 1 downto 0);
    signal resp_err_out     : std_logic;

    -- Misc. internal signals
    signal req_sel       : std_logic;
    signal req_empty_reg : std_logic;

begin

    -----------------------
    -- Request buffering --
    -----------------------

    -- (Optional) Instantiate a FIFO for incoming requests
    gen_req_fifo : if ((G_REQ_FIFO_SIZE > 0) and (C_FIFO_WIDTH > 0)) generate

        x_req_fifo : entity work.sync_fifo
            generic map(
                G_WIDTH   => C_FIFO_WIDTH,
                G_DEPTH   => G_REQ_FIFO_SIZE,
                G_REG_OUT => 0
            )
            port map
            (
                clk          => clk,
                rst          => rst,
                wr_valid     => req_fifo.wr_valid,
                wr_ready     => req_fifo.wr_ready,
                wr_data      => req_fifo.wr_data,
                rd_valid     => req_fifo.rd_valid,
                rd_ready     => req_fifo.rd_ready,
                rd_data      => req_fifo.rd_data,
                level        => open,
                full         => req_fifo.full,
                almost_full  => open,
                empty        => req_fifo.empty,
                almost_empty => open
            );

        -- Connect inputs (request-side)
        req_fifo.wr_valid <= (wr_req_valid or rd_req_valid);
        req_fifo.wr_data  <= (rd_req_valid & rd_req_addr & wr_req_valid & wr_req_addr & wr_req_data & wr_req_byte_en);

        -- Unpack FIFO output
        rd_req_valid_in   <= req_fifo.rd_data(C_FIFO_WIDTH - 1);
        rd_req_addr_in    <= req_fifo.rd_data(C_FIFO_WIDTH - 2 downto C_FIFO_WIDTH - G_ADDR_WIDTH - 1);
        wr_req_valid_in   <= req_fifo.rd_data(C_FIFO_WIDTH - G_ADDR_WIDTH - 2);
        wr_req_addr_in    <= req_fifo.rd_data(C_FIFO_WIDTH - G_ADDR_WIDTH - 3 downto C_FIFO_WIDTH - (2 * G_ADDR_WIDTH) - 2);
        wr_req_data_in    <= req_fifo.rd_data(C_FIFO_WIDTH - (2 * G_ADDR_WIDTH) - 3 downto C_FIFO_WIDTH - (2 * G_ADDR_WIDTH) - G_DATA_WIDTH - 2);
        wr_req_byte_en_in <= req_fifo.rd_data(C_FIFO_WIDTH - (2 * G_ADDR_WIDTH) - G_DATA_WIDTH - 3 downto C_FIFO_WIDTH - (2 * G_ADDR_WIDTH) - G_DATA_WIDTH - ((G_DATA_WIDTH + 7) / 8) - 2);
        assert ((C_FIFO_WIDTH - (2 * G_ADDR_WIDTH) - G_DATA_WIDTH - ((G_DATA_WIDTH + 7) / 8) - 2) = 0) report "FIFO output is incorrectly sliced." severity error;

    end generate gen_req_fifo;

    -- (Optional) Do not generate a request buffer
    gen_no_req_fifo : if (not (G_REQ_FIFO_SIZE > 0) and (C_FIFO_WIDTH > 0)) generate
        assert (false) report "Not implemented." severity failure;
    end generate gen_no_req_fifo;

    ----------------------------------------------------------------
    -- Separate read/write streams into primary/secondary streams --
    ----------------------------------------------------------------

    gen_pri_is_write : if (not G_PRIORITISE_READS) generate
        pri_req.wr_en   <= '1';
        pri_req.valid   <= wr_req_valid_in;
        pri_req.addr    <= wr_req_addr_in;
        pri_req.data    <= wr_req_data_in;
        pri_req.byte_en <= wr_req_byte_en_in;
        sec_req.wr_en   <= '0';
        sec_req.valid   <= rd_req_valid_in;
        sec_req.addr    <= rd_req_addr_in;
    end generate gen_pri_is_write;

    gen_pri_is_read : if (G_PRIORITISE_READS) generate
        pri_req.wr_en   <= '0';
        pri_req.valid   <= rd_req_valid_in;
        pri_req.addr    <= rd_req_addr_in;
        sec_req.wr_en   <= '1';
        sec_req.valid   <= wr_req_valid_in;
        sec_req.addr    <= wr_req_addr_in;
        sec_req.data    <= wr_req_data_in;
        sec_req.byte_en <= wr_req_byte_en_in;
    end generate gen_pri_is_read;

    -- Place secondary requests in a buffer until they can be executed
    sec_buf_proc : process (clk) is
    begin
        if (rising_edge(clk)) then
            if (req_fifo.rd_valid = '1' and req_fifo.rd_ready = '1') then -- FIFO read handshake
                sec_buf.wr_en   <= sec_req.wr_en;
                sec_buf.valid   <= sec_req.valid;
                sec_buf.addr    <= sec_req.addr;
                sec_buf.data    <= sec_req.data;
                sec_buf.byte_en <= sec_req.byte_en;
            end if;
            if (rst = '1') then
                sec_buf.valid <= '0';
            end if;
        end if;
    end process;

    --------------------------------
    -- Finite State Machine (FSM) --
    --------------------------------

    -- Collect the next operation(s) from the request FIFO
    req_fifo.rd_ready <=
    '1' when (req_empty_reg = '1') else    -- Skip the first transaction after the FIFO is empty, when it appears
    '0' when (sec_buf.valid = '1') else    -- Not ready when there is a secondary request waiting
    '0' when (next_state = ACK) else       -- Not ready while the Wishbone master is waiting for an ACK
    '0' when (next_state = RTY) else       -- Not ready while the bus is waiting to retry
    '0' when (next_state = FSM_ERROR) else -- The core can completely lock up in this case
    '1';

    -- Process to select the next state
    next_state_proc : process (state, req_fifo, pri_req, sec_req, sec_buf, wb_mem_ack, wb_mem_err, wb_mem_rty, wr_req_valid, rd_req_valid) is
    begin
        case (state) is

            when IDLE =>

                -- Begin a bus transaction if there is a valid request from the FIFO
                if (req_fifo.rd_valid = '1' and (pri_req.valid = '1' or sec_req.valid = '1')) then
                    next_state <= STB;

                    -- Performance optimisation (for the first transaction, you can skip the FIFO)
                elsif (req_fifo.empty = '1' and (wr_req_valid = '1' or rd_req_valid = '1')) then
                    next_state <= STB;
                    assert (req_fifo.rd_valid = '0') report "FIFO is reporting it is empty, but hasn't de-asserted its rd_valid signal." severity error;

                    -- Similarly, begin a bus transaction if there is a valid request waiting in the secondary buffer
                    -- Technically, this should not happen from the IDLE state
                elsif (sec_buf.valid = '1') then
                    next_state <= STB;
                    assert (false) report "Secondary buffer was not properly emptied before returning to the IDLE state." severity error;
                end if;

            when STB =>
                next_state <= ACK;

            when ACK =>
                if (wb_mem_ack = '1' or wb_mem_err = '1') then
                    if (req_fifo.rd_valid = '1' and (pri_req.valid = '1' or sec_req.valid = '1')) then
                        next_state <= STB;
                    else
                        next_state <= IDLE;
                    end if;
                elsif (wb_mem_rty = '1') then
                    next_state <= RTY;
                end if;

            when RTY =>

            when others => next_state <= FSM_ERROR;
        end case;
    end process;

    -- Synchronous control process
    ctrl_proc : process (clk) is
    begin
        if (rising_edge(clk)) then

            -- Advance the state
            state <= next_state;

            -- Hold STB high until there is a response on the Wishbone bus
            if (next_state = STB) then
                wb_mem_cyc <= '1';
                wb_mem_stb <= '1';

                -- In the normal case, data is received from the FIFO/secondary buffer
                if (req_fifo.rd_valid = '1' or sec_buf.valid = '1') then

                    -- Act on the primary request, if it is present, and if the secondary buffer is empty
                    if (sec_buf.valid = '0' and pri_req.valid = '1') then
                        wb_mem_wr_en   <= pri_req.wr_en;
                        wb_mem_addr    <= pri_req.addr;
                        wb_mem_byte_en <= pri_req.byte_en;
                        wb_mem_wr_data <= pri_req.data;

                        -- Secondary requests otherwise take priority
                    else
                        wb_mem_wr_en   <= sec_req.wr_en;
                        wb_mem_addr    <= sec_req.addr;
                        wb_mem_byte_en <= sec_req.byte_en;
                        wb_mem_wr_data <= sec_req.data;
                    end if;

                    -- Performance optimisation (FIFO can be skipped for the first transaction)
                elsif (req_fifo.empty = '1') then
                    if (not G_PRIORITISE_READS) then
                        if (wr_req_valid = '1') then
                            wb_mem_wr_en   <= '1';
                            wb_mem_addr    <= wr_req_addr;
                            wb_mem_byte_en <= wr_req_byte_en;
                            wb_mem_wr_data <= wr_req_data;
                        elsif (rd_req_valid = '1') then
                            wb_mem_wr_en <= '0';
                            wb_mem_addr  <= rd_req_addr;
                        end if;
                    else
                        if (rd_req_valid = '1') then
                            wb_mem_wr_en <= '0';
                            wb_mem_addr  <= rd_req_addr;
                        elsif (wr_req_valid = '1') then
                            wb_mem_wr_en   <= '1';
                            wb_mem_addr    <= wr_req_addr;
                            wb_mem_byte_en <= wr_req_byte_en;
                            wb_mem_wr_data <= wr_req_data;
                        end if;
                    end if;
                else
                    assert (false) report "STB state entered erroneously; no requests can be submitted for a bus transaction." severity error;
                end if;
            end if;

            -- Register the request FIFO empty flag, to facilitate the performance optimisation
            req_empty_reg <= req_fifo.empty;

            -- De-assert STB
            if (next_state = IDLE or next_state = FSM_ERROR) then
                wb_mem_cyc <= '0';
                wb_mem_stb <= '0';
            end if;

            -- Generate a response
            if (state = ACK) then
                if (wb_mem_ack = '1') then
                    resp_valid_out   <= '1';
                    resp_rd_out      <= not wb_mem_wr_en;
                    resp_rd_data_out <= wb_mem_rd_data;
                    resp_err_out     <= '0';
                elsif (wb_mem_err = '1') then
                    resp_valid_out   <= '1';
                    resp_rd_out      <= not wb_mem_wr_en;
                    resp_rd_data_out <= wb_mem_rd_data;
                    resp_err_out     <= '1';
                end if;
            end if;

        end if;
    end process;

end architecture;
