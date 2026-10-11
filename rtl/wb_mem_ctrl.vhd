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

        -- Response interface
        rd_resp_valid : out std_logic;
        rd_resp_ready : in std_logic;
        rd_resp_data  : out std_logic_vector(G_DATA_WIDTH - 1 downto 0);
        rd_resp_err   : out std_logic;
        wr_resp_err   : out std_logic;

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

    -- FSM states
    type state_t is (IDLE, STB, ACK, RTY, FSM_ERROR);
    signal state      : state_t;
    signal next_state : state_t;

    -- Declare a backup buffer to hold a secondary request if a write and read are simultaneously requested
    type backup_buf_t is record
        consume : std_logic;
        valid   : std_logic;
        wr_en   : std_logic;
        addr    : std_logic_vector(G_ADDR_WIDTH - 1 downto 0);
        data    : std_logic_vector(G_DATA_WIDTH - 1 downto 0);
        byte_en : std_logic_vector((((G_DATA_WIDTH + 7) / 8)) - 1 downto 0);
    end record;
    signal backup_buf : backup_buf_t;

    -- Function to select the next request to act upon
    type op_t is (NONE, RD, WR);
    function F_GET_NEXT_REQ return op_t is
    begin
        if (G_PRIORITISE_READS) then
            if (rd_req_valid = '1') then
                return RD;
            elsif (wr_req_valid = '1') then
                return WR;
            end if;
        else
            if (wr_req_valid = '1') then
                return WR;
            elsif (rd_req_valid = '1') then
                return RD;
            end if;
        end if;
        return NONE;
    end function;

    signal rty_timer : unsigned(log2ceil(G_RETRY_TIMEOUT_CYC) - 1 downto 0);

begin

    --------------------
    -- Input handling --
    --------------------

    backup_buf_proc : process (clk) is
    begin
        if (rising_edge(clk)) then

            -- Clear the contents of the buffer when the consume signal is asserted
            if (backup_buf.consume = '1') then
                backup_buf.valid <= '0';
            end if;

            -- If there are two requests at once, copy the non-priority request into the backup buffer
            if (wr_req_valid = '1' and rd_req_valid = '1') then
                backup_buf.valid <= '1';
                if (F_GET_NEXT_REQ = WR) then
                    backup_buf.wr_en <= '0';
                    backup_buf.addr  <= rd_req_addr;
                elsif (F_GET_NEXT_REQ = RD) then
                    backup_buf.wr_en   <= '1';
                    backup_buf.addr    <= wr_req_addr;
                    backup_buf.data    <= wr_req_data;
                    backup_buf.byte_en <= wr_req_byte_en;
                end if;
                assert (F_GET_NEXT_REQ /= NONE) report "Failed to copy into the backup buffer; F_GET_NEXT_REQ returned NONE." severity error;
            end if;

            -- Initialise on reset
            if (rst = '1') then
                backup_buf.valid <= '0';
            end if;
        end if;
    end process;

    -- Assert the ready signals when:
    --      > there is nothing waiting in the backup buffer, and
    --      > there is not a transaction currently in-progress on the Wishbone bus
    wr_req_ready <=
        '1' when ((backup_buf.valid = '0' or backup_buf.consume = '1') and state /= STB and not (state = ACK and not (wb_mem_ack = '1' or wb_mem_err = '1'))) else
        '0';
    rd_req_ready <=
        '1' when ((backup_buf.valid = '0' or backup_buf.consume = '1') and state /= STB and not (state = ACK and not (wb_mem_ack = '1' or wb_mem_err = '1'))) else
        '0';

    -- Asynchronous process to determine the next state
    next_state_proc : process (state, wr_req_valid, wr_req_ready, rd_req_valid, rd_req_ready, wb_mem_ack, wb_mem_err, wb_mem_rty, rty_timer) is
    begin
        next_state <= state;
        case (state) is

                -- When there is a request handshake, initiate a Wishbone memory transaction
            when IDLE =>
                if ((wr_req_valid = '1' and wr_req_ready = '1') or (rd_req_valid = '1' and rd_req_ready = '1')) then
                    next_state <= STB;
                end if;

                -- STB is asserted in this cycle
            when STB =>
                next_state <= ACK;

                -- Wait for an ACK/RTY/ERR reponse before returning to IDLE, or going straight into the next transfer if necessary
            when ACK =>
                if (wb_mem_ack = '1' or wb_mem_err = '1') then
                    if ((wr_req_valid = '1' and wr_req_ready = '1') or (rd_req_valid = '1' and rd_req_ready = '1')) then
                        next_state <= STB;
                    else
                        next_state <= IDLE;
                    end if;
                elsif (wb_mem_rty = '1') then
                    next_state <= RTY;
                end if;

                -- Stay in this state until the retry timer expires
            when RTY =>
                if (rty_timer = 0) then
                    next_state <= STB;
                end if;

            when others => next_state <= FSM_ERROR;
        end case;
    end process;

    ctrl_proc : process (clk) is
    begin
        if (rising_edge(clk)) then

            -- Update the state
            state <= next_state;

            -- Clear signals upon returning to IDLE
            if (next_state <= IDLE) then
                wb_mem_cyc     <= '0';
                wb_mem_stb     <= '0';
            end if;

            -- Update the Wishbone outputs upon entering the STB state
            if (next_state = STB) then
                wb_mem_cyc <= '1';
                wb_mem_stb <= '1';

                if (state /= RTY) then -- If this is a retry, do not update the other Wishbone outputs

                    -- Prioritise requests held in the backup buffer
                    if (backup_buf.valid = '1') then
                        wb_mem_wr_en   <= backup_buf.wr_en;
                        wb_mem_addr    <= backup_buf.addr;
                        wb_mem_wr_data <= backup_buf.data;
                        wb_mem_byte_en <= backup_buf.byte_en;

                        -- Otherwise, the STB state must've been triggered by a new request
                    else
                        wb_mem_addr    <= wr_req_addr;
                        wb_mem_wr_data <= wr_req_data;
                        wb_mem_byte_en <= wr_req_byte_en;

                        if (F_GET_NEXT_REQ = WR) then
                            wb_mem_wr_en <= '1';
                        else
                            wb_mem_wr_en <= '0';
                        end if;

                        assert (F_GET_NEXT_REQ /= NONE) report "STB state enterred erroneously (F_GET_NEXT_REQ = NONE)." severity error;
                        assert ((wr_req_valid = '1' and wr_req_ready = '1') or (rd_req_valid = '1' and rd_req_ready = '1')) report "STB state enterred erroneously (no new/in-progress requests)." severity error;
                    end if;
                end if;
            end if;

            -- Initialise on reset
            if (rst = '1') then
                state      <= IDLE;
                wb_mem_cyc <= '0';
                wb_mem_stb <= '0';
            end if;
        end if;
    end process;

end architecture;