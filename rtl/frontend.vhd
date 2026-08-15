library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.common_pkg.all;

entity frontend is
    generic (
        -- Cache parameters
        G_ICACHE_SETS       : natural := 16; -- Number of cache sets (the depth of the cache)
        G_ICACHE_WAYS       : natural := 4;  -- Number of cache ways
        G_ICACHE_LINE_WIDTH : natural := 4   -- Width of each cache line in 32-bit increments (must be a power of 2)
    );
    port (
        clk : in std_logic;
        rst : in std_logic;

        -- CPU Interface
        instr_addr       : in std_logic_vector(31 downto 0);
        instr_addr_valid : in std_logic;
        instr_addr_ready : out std_logic;
        instr_data       : out std_logic_vector(31 downto 0);
        instr_data_valid : out std_logic;
        instr_data_ready : in std_logic;

        -- Instruction Memory Interface (Wishbone)
        wb_imem_addr : out std_logic_vector(31 downto 0);
        wb_imem_data : in std_logic_vector(31 downto 0);
        wb_imem_req  : out std_logic; -- STB_O
        wb_imem_ack  : in std_logic;  -- ACK_I
        wb_imem_cyc  : out std_logic  -- CYC_O
    );
end entity;

architecture rtl of frontend is

    -- FSM States
    type state_t is (IDLE, CACHE_LOOKUP, IMEM_STB, IMEM_ACK, ERROR);
    signal state      : state_t := IDLE;
    signal next_state : state_t := IDLE;

    -- Number of offset bits in the cache address (when these bits are zero, it is the base address)
    constant C_OFFSET_BITS : natural := log2ceil(4 * G_ICACHE_LINE_WIDTH);

    -- Cache control signals
    signal cache_hit              : std_logic;
    signal cache_update_complete  : std_logic := '1';
    signal cache_missed_addr      : std_logic_vector(31 downto 0);
    signal cache_missed_base_addr : std_logic_vector(31 downto 0);
    signal cache_line_counter     : natural := 0;
    signal cache_wr_addr_ptr      : std_logic_vector(31 downto 0);

    -- Cache interface signals
    signal cache_wr_addr : std_logic_vector(31 downto 0);
    signal cache_wr_data : std_logic_vector(31 downto 0);
    signal cache_rd_data : std_logic_vector(31 downto 0);

    -- Misc. signals
    signal instr_addr_reg    : std_logic_vector(instr_addr'range);
    signal missing_data_sent : std_logic;

begin

    --------------------------
    -- Finite State Machine --
    --------------------------

    -- Process to advance the state
    adv_state_proc : process (clk) is
    begin
        if (rising_edge(clk)) then
            state <= next_state;
        end if;
    end process;

    -- Process to decide the next state
    next_state_proc : process (rst, state, instr_addr_valid, cache_hit, wb_imem_ack, cache_update_complete) is
    begin
        next_state <= state;
        case (state) is

            when IDLE =>

                -- Advance the state when a fetch is requested
                if (instr_addr_valid = '1') then
                    next_state <= CACHE_LOOKUP;
                end if;

            when CACHE_LOOKUP =>

                -- Return to IDLE if there are no more fetch requests
                if (instr_addr_valid = '0') then
                    next_state <= IDLE;
                end if;

                -- However, if there is a cache miss, memory must be searched
                if (cache_hit = '0') then
                    next_state <= IMEM_STB;
                end if;

            when IMEM_STB =>
                next_state <= IMEM_ACK;

            when IMEM_ACK =>
                if (wb_imem_ack = '1') then -- Wait for ACK signal
                    -- Repeat until the cache line is full, then proceed
                    if (cache_update_complete = '0') then
                        next_state <= IMEM_STB;
                    elsif (instr_addr_valid = '1') then
                        next_state <= CACHE_LOOKUP;
                    elsif (instr_addr_valid = '0') then
                        next_state <= IDLE;
                    end if;
                end if;

            when others =>
                next_state <= ERROR;
        end case;

        if (rst = '1') then
            next_state <= IDLE;
        end if;
    end process;

    -------------
    -- I-Cache --
    -------------

    x_icache : entity work.icache
        generic map(
            G_ICACHE_SETS       => G_ICACHE_SETS,
            G_ICACHE_WAYS       => G_ICACHE_WAYS,
            G_ICACHE_LINE_WIDTH => G_ICACHE_LINE_WIDTH
        )
        port map
        (
            clk        => clk,
            rst        => rst,
            ic_rd_addr => instr_addr,
            ic_rd_data => cache_rd_data,
            ic_rd_hit  => cache_hit,
            ic_write   => wb_imem_ack,
            ic_wr_addr => cache_wr_addr,
            ic_wr_data => wb_imem_data
        );

    wb_imem_addr <= cache_wr_addr;

    -- Synchronous process to control the cache updates from instruction memory
    cache_update_proc : process (clk) is
        variable v_cache_missed_addr      : std_logic_vector(instr_addr'range);
        variable v_cache_missed_base_addr : std_logic_vector(instr_addr'range);
        variable v_cache_line_counter     : integer := 0;

        variable next_addr        : std_logic_vector(cache_wr_addr'range);
        variable incr_addr        : std_logic_vector(wb_imem_addr'range);
        variable null_offset_bits : std_logic_vector(C_OFFSET_BITS - 1 downto 0) := (others => '0');
    begin
        if (rising_edge(clk)) then

            -- Detect a new cache miss
            if (state = CACHE_LOOKUP and cache_hit = '0') then

                -- Load the missing/base addresses to prepare for updating the cache line
                v_cache_missed_addr      := instr_addr_reg;
                v_cache_missed_base_addr := instr_addr_reg(instr_addr'high downto C_OFFSET_BITS) & null_offset_bits; -- Round down to find the base

                -- Prepare to update the cache line
                cache_wr_addr     <= instr_addr_reg; -- Fetch the missed address first
                cache_wr_addr_ptr <= instr_addr_reg(instr_addr'high downto C_OFFSET_BITS) & null_offset_bits;

                -- During a cache line update, request each address, starting with the missed address
            elsif (cache_update_complete = '0') then

                -- Only act after a handshake with instruction memory
                if (wb_imem_ack = '1') then

                    -- Increment/reset the counter
                    if (v_cache_line_counter < G_ICACHE_LINE_WIDTH - 1) then
                        v_cache_line_counter := v_cache_line_counter + 1;
                    else
                        v_cache_line_counter := 0;
                    end if;

                    -- Update the address
                    next_addr := std_logic_vector(to_unsigned(to_uint(v_cache_missed_base_addr) + (v_cache_line_counter * 4), next_addr'length)); -- next_addr = base_addr + counter
                    if (next_addr = v_cache_missed_addr) then
                        next_addr := cache_missed_base_addr;
                    end if;
                    cache_wr_addr <= next_addr;

                end if;
            else
                v_cache_line_counter := 0;
            end if;

            -- Connect registers to variables
            cache_missed_addr      <= v_cache_missed_addr;
            cache_missed_base_addr <= v_cache_missed_base_addr;
            cache_line_counter     <= v_cache_line_counter;
        end if;
    end process;

    -- The cache update is only marked as complete when ACK is asserted for the final time
    cache_update_complete <= '1' when (cache_line_counter = G_ICACHE_LINE_WIDTH - 1 and wb_imem_ack = '1') else
        '0';

    -- Process to control the data given to the Decode stage
    data_ret_proc : process (clk) is
    begin
        if (rising_edge(clk)) then
            instr_data_valid <= '0';

            -- If there is a cache hit, provide the data directly from the cache
            if (state = CACHE_LOOKUP and cache_hit = '1') then
                instr_data       <= cache_rd_data;
                instr_data_valid <= '1';
            end if;

            -- Following a cache miss, provide the missing data as soon as possible
            if (state = IMEM_ACK and wb_imem_ack = '1' and cache_line_counter = 0 and missing_data_sent = '0') then
                instr_data        <= wb_imem_data;
                instr_data_valid  <= '1';
                missing_data_sent <= '1';
            end if;

            -- De-assert valid when there is a handshake
            if (instr_data_ready = '1' and instr_data_valid = '1' and cache_hit = '0') then
                instr_data_valid <= '0';
            end if;

            -- Reset flag for subsequent handshakes with the Decode stage
            if (state /= IMEM_STB and state /= IMEM_ACK) then
                missing_data_sent <= '0';
            end if;

        end if;
    end process;

    -----------
    -- Misc. --
    -----------

    -- Synchronous control process
    ctrl_proc : process (clk) is
    begin
        if (rising_edge(clk)) then

            -- Default values should be loaded during the IDLE state
            if (next_state = IDLE) then
                wb_imem_cyc <= '0';
            end if;

            -- Claim the Wishbone bus when 

            -- Register the address when it is to be used in the next fetch request
            if (instr_addr_valid = '1') then
                instr_addr_reg <= instr_addr;
            end if;

            -- In the IMEM_STB state, the STB_O and CYC_O signals must be asserted
            if (next_state = IMEM_STB) then
                wb_imem_cyc <= '1';
            end if;

            -- The CYC_O signal can be de-asserted when the cache line is updated
            if (cache_update_complete = '1') then
                wb_imem_cyc <= '0';
            end if;

        end if;
    end process;

    instr_addr_ready <= '1' when ((next_state = IDLE or next_state = CACHE_LOOKUP) and rst = '0') else
        '0';

    -- Combinational control process
    comb_proc : process (state, next_state) is
    begin

        -- The STB_O should be asserted in the IMEM_STB/ACK states
        if (state = IMEM_STB or state = IMEM_ACK) then
            wb_imem_req <= '1';
        end if;

        -- However, when an ACK has been received, the STB_O signal can be de-asserted
        if (state = IMEM_ACK and next_state /= IMEM_ACK) then
            wb_imem_req <= '0';
        end if;
    end process;

end architecture;