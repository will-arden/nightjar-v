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
        G_REQ_FIFO_DEPTH    : natural  := 8;
        G_RESP_FIFO_DEPTH   : natural  := 8;
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

    -- FIFO data consists of (from MSB down to LSB):
    --      Read:
    --          - Valid
    --          - Address
    --      Write:
    --          - Valid
    --          - Address
    --          - Data
    --          - Byte-enable
    constant C_WR_BE_LOWER : natural := 0;                                                                  -- Write Byte-Enable Lower Bound
    constant C_WR_BE_UPPER : natural := C_WR_BE_LOWER + ((G_DATA_WIDTH + 7) / 8) - 1;                       -- Write Byte-Enable Upper Bound
    constant C_WR_D_LOWER  : natural := C_WR_BE_UPPER + 1;                                                  -- Write Data Lower Bound
    constant C_WR_D_UPPER  : natural := C_WR_D_LOWER + G_DATA_WIDTH - 1;                                    -- Write Data Upper Bound
    constant C_WR_A_LOWER  : natural := C_WR_D_UPPER + 1;                                                   -- Write Address Lower Bound
    constant C_WR_A_UPPER  : natural := C_WR_A_LOWER + G_ADDR_WIDTH - 1;                                    -- Write Address Upper Bound
    constant C_WR_V_BIT    : natural := C_WR_A_UPPER + 1;                                                   -- Write Valid Bit
    constant C_RD_A_LOWER  : natural := C_WR_V_BIT + 1;                                                     -- Read Address Lower Bound
    constant C_RD_A_UPPER  : natural := C_RD_A_LOWER + G_ADDR_WIDTH - 1;                                    -- Read Address Upper Bound
    constant C_RD_V_BIT    : natural := C_RD_A_UPPER + 1;                                                   -- Read Valid Bit
    constant C_FIFO_WIDTH  : natural := (2 * (1 + G_ADDR_WIDTH)) + G_DATA_WIDTH + ((G_DATA_WIDTH + 7) / 8); -- Total FIFO width

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

    -- Primary/secondary request signals
    signal pri_req_valid   : std_logic;
    signal pri_req_addr    : std_logic_vector(G_ADDR_WIDTH - 1 downto 0);
    signal pri_req_wr_en   : std_logic;
    signal pri_req_byte_en : std_logic_vector((((G_DATA_WIDTH + 7) / 8)) - 1 downto 0);
    signal pri_req_data    : std_logic_vector(G_DATA_WIDTH - 1 downto 0);
    signal sec_req_valid   : std_logic;
    signal sec_req_addr    : std_logic_vector(G_ADDR_WIDTH - 1 downto 0);
    signal sec_req_wr_en   : std_logic;
    signal sec_req_byte_en : std_logic_vector((((G_DATA_WIDTH + 7) / 8)) - 1 downto 0);
    signal sec_req_data    : std_logic_vector(G_DATA_WIDTH - 1 downto 0);

    -- Misc. control signals
    signal req_pair_valid : std_logic;
    signal req_pair_ready : std_logic;

    signal addr_in_prog       : std_logic_vector(G_ADDR_WIDTH - 1 downto 0);
    signal wr_data_in_prog    : std_logic_vector(G_DATA_WIDTH - 1 downto 0);
    signal wr_en_in_prog      : std_logic;
    signal wr_byte_en_in_prog : std_logic_vector(((G_DATA_WIDTH + 7) / 8) downto 0);

    signal pri_req_done : std_logic;
    signal sec_req_done : std_logic;

    signal rty_timer : unsigned(log2ceil(G_RETRY_TIMEOUT_CYC) - 1 downto 0);

begin

    ----------------------------------
    -- (Optional) Request buffering --
    ----------------------------------

    -- Request buffering can help to reduce stalling by increasing parallelism. For an in-order CPU, such a FIFO can only be useful for STORE requests, since
    -- the CPU pipeline will simply stall when it is waiting to receive the result of a LOAD, meaning a FIFO cannot relieve the bottleneck.
    
    -- Whenever either a read/write request is input, it is passed through the FIFO; requests are handled in pairs so that they are processed chronologically.
    -- The FIFO wr_ready signal is connected to both input streams, such that they are accepted together and remain in sync.

    -- Instantiate a FIFO for incoming requests
    gen_req_fifo : if ((G_REQ_FIFO_DEPTH > 0) and (C_FIFO_WIDTH > 0)) generate

        x_req_fifo : entity work.sync_fifo
            generic map(
                G_WIDTH   => C_FIFO_WIDTH,
                G_DEPTH   => G_REQ_FIFO_DEPTH,
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
        req_fifo.wr_valid <= (wr_req_valid or rd_req_valid);                                                           -- Ensure chronology
        req_fifo.wr_data  <= (rd_req_valid & rd_req_addr & wr_req_valid & wr_req_addr & wr_req_data & wr_req_byte_en); -- Pack data input

        -- Accept new data into the FIFO in pairs, by connecting a common ready signal
        rd_req_ready <= req_fifo.wr_ready;
        wr_req_ready <= req_fifo.wr_ready;

        -- Unpack FIFO output
        rd_req_valid_in   <= req_fifo.rd_data(C_RD_V_BIT);
        rd_req_addr_in    <= req_fifo.rd_data(C_RD_A_UPPER downto C_RD_A_LOWER);
        wr_req_valid_in   <= req_fifo.rd_data(C_WR_V_BIT);
        wr_req_addr_in    <= req_fifo.rd_data(C_WR_A_UPPER downto C_WR_A_LOWER);
        wr_req_data_in    <= req_fifo.rd_data(C_WR_D_UPPER downto C_WR_D_LOWER);
        wr_req_byte_en_in <= req_fifo.rd_data(C_WR_BE_UPPER downto C_WR_BE_LOWER);

        -- Connect valid/ready signals (handled in pairs)
        req_pair_valid    <= req_fifo.rd_valid;
        req_fifo.rd_ready <= req_pair_ready;

    end generate gen_req_fifo;

    -- Pass the inputs directly if no FIFO is required
    gen_no_req_fifo : if (not (G_REQ_FIFO_DEPTH > 0) and (C_FIFO_WIDTH > 0)) generate

        -- Connect data signals
        rd_req_valid_in   <= rd_req_valid;
        rd_req_addr_in    <= rd_req_addr;
        wr_req_valid_in   <= wr_req_valid;
        wr_req_addr_in    <= wr_req_addr;
        wr_req_data_in    <= wr_req_data;
        wr_req_byte_en_in <= wr_req_byte_en;

        -- Connect valid/ready signals (handled in pairs)
        req_pair_valid <= (rd_req_valid_in or wr_req_valid_in);
        rd_req_ready   <= req_pair_ready;
        wr_req_ready   <= req_pair_ready;

    end generate gen_no_req_fifo;

    -------------------------------------------------------------------
    -- Rename inputs as "primary" and "secondary", based on priority --
    -------------------------------------------------------------------

    -- These signals could either be coming directly from the two input streams, or via the request FIFO.
    -- In either case, they may be treated the same.

    gen_prioritise_writes : if (not G_PRIORITISE_READS) generate

        -- Primary = Write
        pri_req_valid   <= wr_req_valid_in;
        pri_req_addr    <= wr_req_addr_in;
        pri_req_wr_en   <= '1';
        pri_req_byte_en <= wr_req_byte_en_in;
        pri_req_data    <= wr_req_data_in;

        -- Secondary = Read
        sec_req_valid <= rd_req_valid;
        sec_req_addr  <= rd_req_addr;
        sec_req_wr_en <= '0';

    end generate;

    gen_prioritise_reads : if (G_PRIORITISE_READS) generate

        -- Primary = Read
        pri_req_valid <= rd_req_valid_in;
        pri_req_addr  <= rd_req_addr_in;
        pri_req_wr_en <= '0';

        -- Secondary = Write
        sec_req_valid   <= wr_req_valid_in;
        sec_req_addr    <= wr_req_addr_in;
        sec_req_wr_en   <= '1';
        sec_req_byte_en <= wr_req_byte_en_in;
        sec_req_data    <= wr_req_data_in;

    end generate;

    ---------------------------
    -- Wishbone Protocol FSM --
    ---------------------------

    -- Combinational process to assert req_pair_ready
    req_pair_ready_proc : process (all) is
    begin
        req_pair_ready <= '0'; -- Default assignment

        -- Only accept new data when the Wishbone output registers are updated
        if (next_state = STB and state /= RTY) then

            -- Scenario A: there is only one valid request in the current pair
            if ((pri_req_valid xor sec_req_valid) = '1') then
                req_pair_ready <= '1';
            end if;

            -- Scenario B: the primary request has already been placed on the bus, meaning that the secondary request is now being placed on the bus
            if (pri_req_valid = '1' and sec_req_valid = '1' and pri_req_done = '1') then
                req_pair_ready <= '1';
            end if;

        end if;

        -- Logic is not ready during reset
        if (rst = '1') then
            req_pair_ready <= '0';
        end if;
    end process;

    -- Combinational process to derive the next state
    next_state_proc : process (all) is
    begin
        next_state <= state; -- By default, remain in the same state

        case (state) is

            when IDLE =>
                if (pri_req_valid = '1' or sec_req_valid = '1') then
                    next_state <= STB;
                end if;

            when STB =>
                next_state <= ACK;

            when ACK =>

                -- Only act when ACK_I or ERR_I are received
                if (wb_mem_ack = '1' or wb_mem_err = '1') then

                    -- If there is an outstanding request, immediately action it
                    if (pri_req_valid = '1' and pri_req_done = '0') or (sec_req_valid = '1' and sec_req_done = '0') then
                        next_state <= STB;
                    else
                        next_state <= IDLE;
                    end if;
                end if;

            when RTY =>
                if (rty_timer = 0) then
                    next_state <= STB;
                end if;

                -- Unreachable state
            when others =>
                next_state <= FSM_ERROR;
        end case;
    end process;

    -- Synchronous control process
    ctrl_proc : process (clk) is
    begin
        if (rising_edge(clk)) then

            -- Default assignments
            state <= next_state;

            -- Initiate a new bus transaction
            if (next_state = STB) then

                wb_mem_stb <= '1';
                wb_mem_cyc <= '1';

                -- Do not change the data signals if coming from the RTY state
                if (state /= RTY) then

                    -- Place the primary request on the bus
                    if (pri_req_valid = '1' and pri_req_done = '0') then
                        pri_req_done   <= '1';
                        wb_mem_addr    <= pri_req_addr;
                        wb_mem_wr_en   <= pri_req_wr_en;
                        wb_mem_byte_en <= pri_req_byte_en;
                        wb_mem_wr_data <= pri_req_data;

                        -- Place the secondary request on the bus
                    elsif (sec_req_valid = '1' and sec_req_done = '0') then
                        sec_req_done   <= '1';
                        wb_mem_addr    <= sec_req_addr;
                        wb_mem_wr_en   <= sec_req_wr_en;
                        wb_mem_byte_en <= sec_req_byte_en;
                        wb_mem_wr_data <= sec_req_data;
                    end if;
                end if;

            end if;

            -- Re-initialise the "done" signals as the next pair is input
            if (req_pair_valid = '1' and req_pair_ready = '1') then
                pri_req_done <= '0';
                sec_req_done <= '0';
            end if;

            -- De-assert STB_O and CYC_O upon transition to IDLE or RTY
            if (next_state = IDLE or next_state = RTY) then
                wb_mem_stb <= '0';
                wb_mem_cyc <= '0';
            end if;

            -- Initialise state on reset
            if (rst = '1') then
                state        <= IDLE;
                wb_mem_stb   <= '0';
                wb_mem_cyc   <= '0';
                pri_req_done <= '0';
                sec_req_done <= '0';
            end if;
        end if;
    end process;

end architecture;
