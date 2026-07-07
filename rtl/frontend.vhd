library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.common_pkg.all;

entity frontend is
    generic (
        G_IMEM_DEPTH : positive := 1024
    );
    port (
        clk : in std_logic;
        rst : in std_logic;

        -- CPU Interface
        instr_addr       : in std_logic_vector(log2ceil(G_IMEM_DEPTH) - 1 downto 0);
        instr_addr_valid : in std_logic;
        instr_addr_ready : out std_logic;
        instr_data       : out std_logic_vector(31 downto 0);
        instr_data_valid : out std_logic;
        instr_data_ready : in std_logic;

        -- Instruction Memory Interface (Wishbone)
        wb_imem_addr : out std_logic_vector(log2ceil(G_IMEM_DEPTH) - 1 downto 0);
        wb_imem_data : in std_logic_vector(31 downto 0);
        wb_imem_req  : out std_logic; -- STB_O
        wb_imem_ack  : in std_logic;  -- ACK_I
        wb_imem_cyc  : out std_logic  -- CYC_O
    );
end entity;

architecture rtl of frontend is

    type state_t is (IDLE, CACHE_LOOKUP, IMEM_LOOKUP, DECODE_STALL, ERROR);
    signal state      : state_t := IDLE;
    signal next_state : state_t := IDLE;

    signal cache_miss : std_logic := '1'; -- TODO: For now, cache is not implemented

    signal instr_addr_reg : std_logic_vector(instr_addr'range);

    signal instr_data_valid_i : std_logic;

begin

    -- Connect outputs to internal signals
    instr_data_valid <= instr_data_valid_i;

    -- One bus transfer is only one instruction request
    wb_imem_cyc <= wb_imem_req;

    -- Synchronous control process
    ctrl_proc : process (clk) is
    begin
        if (rising_edge(clk)) then

            -- Register the address when it is to be used in the next fetch request
            if (instr_addr_valid = '1') then
                instr_addr_reg <= instr_addr;
            end if;

        end if;
    end process;

    -- Combinational control process
    comb_proc : process (state, next_state) is
    begin

        -- The frontend is only ready to accept an address in the IDLE or CACHE_LOOKUP states
        if (next_state = IDLE or next_state = CACHE_LOOKUP) then
            instr_addr_ready <= '1';
        else
            instr_addr_ready <= '0';
        end if;

        -- Drive Wishbone signals
        if (state = IMEM_LOOKUP) then
            wb_imem_req <= '1';
        end if;

    end process;

    -- Combinational process to determine the next state
    next_state_proc : process (state, rst, instr_addr_valid, instr_data_valid_i, instr_data_ready, cache_miss, wb_imem_ack) is
    begin
        next_state <= state;
        case (state) is

            when IDLE =>
                if (instr_addr_valid = '1') then
                    next_state <= CACHE_LOOKUP;
                end if;

            when CACHE_LOOKUP =>

                -- If there is a cache hit, proceed depending on the Decode handshake
                if (instr_data_ready = '1' and instr_addr_valid = '0') then
                    next_state <= IDLE;
                elsif (instr_data_ready = '0') then
                    next_state <= DECODE_STALL;
                end if;

                -- NOTE:
                -- If the Decode stage is ready and there is another valid address input, the state machine remains
                -- here while it processes the next fetch request.

                -- If there is a cache miss, then defer to memory
                if (cache_miss = '1') then
                    next_state <= IMEM_LOOKUP;
                end if;

            when IMEM_LOOKUP =>

                -- NOTE:
                -- STB and CYC signals are held high during this state.

                -- Only leave once the acknowledgement is received from memory
                if (wb_imem_ack = '1') then

                    -- If the Decode stage is ready, proceed to either IDLE or straight to CACHE_LOOKUP
                    if (instr_data_ready = '1' and instr_addr_valid = '1') then
                        next_state <= CACHE_LOOKUP;
                    elsif (instr_data_ready = '1' and instr_addr_valid = '0') then
                        next_state <= IDLE;

                        -- Otherwise, enter the stall state
                    else
                        next_state <= DECODE_STALL;
                    end if;
                end if;

            when DECODE_STALL =>

                -- Only leave this state when the Decode stage becomes ready
                if (instr_data_ready = '1') then

                    -- If there is another fetch request, enter CACHE_LOOKUP immediately
                    if (instr_addr_valid = '1') then
                        next_state <= CACHE_LOOKUP;
                    else
                        next_state <= IDLE;
                    end if;

                end if;

            when others => next_state <= ERROR;
        end case;

        -- On reset, return to IDLE state
        if (rst = '1') then
            next_state <= IDLE;
        end if;
    end process;

    -- Process to advance the state
    adv_state_proc : process (clk) is
    begin
        if (rising_edge(clk)) then
            state <= next_state;
        end if;
    end process;

end architecture;