library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.common_pkg.all;

entity cache is
    generic (
        G_CACHE_SETS         : natural := 16;       -- Number of cache sets (the depth of the cache)
        G_CACHE_WAYS         : natural := 4;        -- Number of cache ways
        G_CACHE_LINE_WIDTH   : natural := 4;        -- Width of each cache line in 32-bit increments (must be a power of 2)
        G_ASYNC_READ         : boolean := false;    -- When false, reads are performed asynchronously
        G_REPLACEMENT_POLICY : string  := "simple"; -- "simple", "round-robin", "lfsr", "replace-oldest"
        G_RANDOM_SEED        : natural := 48        -- Random seed for the cache replacement policy
    );
    port (
        clk : in std_logic;
        rst : in std_logic;

        -- Cache read interface
        cache_rd_en   : in std_logic;
        cache_rd_addr : in std_logic_vector(31 downto 0);
        cache_rd_data : out std_logic_vector(31 downto 0);
        cache_rd_mask : out std_logic_vector(G_CACHE_LINE_WIDTH - 1 downto 0);
        cache_rd_hit  : out std_logic;

        -- Cache write interface
        cache_wr_en   : in std_logic;
        cache_wr_addr : in std_logic_vector(31 downto 0);
        cache_wr_data : in std_logic_vector(31 downto 0);
        cache_wr_last : in std_logic
    );
end entity;

architecture rtl of cache is

    constant C_CACHE_DEPTH : natural := G_CACHE_SETS * G_CACHE_WAYS;

    -- Compute the number of offset, index and tag bits in the address
    constant C_OFFSET_BITS : natural := log2ceil(4 * G_CACHE_LINE_WIDTH); -- 2-bit LSBs should be ignored (byte-aligned)
    constant C_INDEX_BITS  : natural := log2ceil(G_CACHE_SETS);
    constant C_TAG_BITS    : natural := 32 - C_INDEX_BITS - C_OFFSET_BITS;

    -- A line of cache is an array of multiple instructions
    type line_t is array (0 to (G_CACHE_LINE_WIDTH - 1)) of std_logic_vector(31 downto 0);

    -- Lines are grouped to form ways; a way is a single cache entry, selected using a "tag"
    type way_t is record
        valid : std_logic;
        mask  : std_logic_vector(G_CACHE_LINE_WIDTH - 1 downto 0); -- Indicates which instructions in the line are valid
        tag   : std_logic_vector(C_TAG_BITS - 1 downto 0);
        line  : line_t;
    end record;

    -- Ways are grouped into sets, which are selected by an "index"
    type set_t is array (0 to (G_CACHE_WAYS - 1)) of way_t;

    -- Cache is composed of sets, which are composed of ways, which are composed of instruction data
    type cache_t is array (0 to (G_CACHE_SETS - 1)) of set_t;
    signal cache : cache_t;

    -- Slices of rd/wr addresses
    signal rd_offset : std_logic_vector(C_OFFSET_BITS - 3 downto 0);
    signal rd_index  : std_logic_vector(C_INDEX_BITS - 1 downto 0);
    signal rd_tag    : std_logic_vector(C_TAG_BITS - 1 downto 0);
    signal wr_offset : std_logic_vector(C_OFFSET_BITS - 3 downto 0);
    signal wr_index  : std_logic_vector(C_INDEX_BITS - 1 downto 0);
    signal wr_tag    : std_logic_vector(C_TAG_BITS - 1 downto 0);

    -- Misc. signals
    signal next_way         : natural range 0 to (G_CACHE_WAYS - 1);
    signal update_next_way  : std_logic;
    signal fill_in_progress : std_logic;

begin

    -- Slice the tag, index and offset for the rd/wr addresses
    rd_offset <= cache_rd_addr(C_OFFSET_BITS - 1 downto 2);
    rd_index  <= cache_rd_addr((C_INDEX_BITS + C_OFFSET_BITS) - 1 downto C_OFFSET_BITS);
    rd_tag    <= cache_rd_addr((C_TAG_BITS + C_INDEX_BITS + C_OFFSET_BITS) - 1 downto (C_INDEX_BITS + C_OFFSET_BITS));
    wr_offset <= cache_wr_addr(C_OFFSET_BITS - 1 downto 2);
    wr_index  <= cache_wr_addr((C_INDEX_BITS + C_OFFSET_BITS) - 1 downto C_OFFSET_BITS);
    wr_tag    <= cache_wr_addr((C_TAG_BITS + C_INDEX_BITS + C_OFFSET_BITS) - 1 downto (C_INDEX_BITS + C_OFFSET_BITS));

    -----------------------
    -- Cache write logic --
    -----------------------

    cache_wr_proc : process (clk) is
    begin
        if (rising_edge(clk)) then

            if (cache_wr_en = '1') then

                -- Invalidate the cache line (as not to conflate old data with new data), unless this is part of the cache line update in progress
                if (fill_in_progress = '0') then
                    cache(to_uint(wr_index))(next_way).valid <= '0';
                    cache(to_uint(wr_index))(next_way).mask  <= (others => '0');
                end if;

                -- Regardless, update the cache
                cache(to_uint(wr_index))(next_way).mask(to_uint(wr_offset)) <= '1';           -- Update mask bit
                cache(to_uint(wr_index))(next_way).tag                      <= wr_tag;        -- Update the tag (should be held for the duration of the cache line fill)
                cache(to_uint(wr_index))(next_way).line(to_uint(wr_offset)) <= cache_wr_data; -- Update one slice of the cache line data

                -- Evaluate the cache_wr_last signal
                cache(to_uint(wr_index))(next_way).valid <= cache_wr_last;     -- When the cache line fill is complete, mark it as valid                
                fill_in_progress                         <= not cache_wr_last; -- Register when a cache line fill has been marked as complete

            end if;

            -- Initialise the cache on reset
            if (rst = '1') then
                for set in 0 to (G_CACHE_SETS - 1) loop
                    for way in 0 to (G_CACHE_WAYS - 1) loop
                        cache(set)(way).valid <= '0';
                        cache(set)(way).mask  <= (others => '0');
                    end loop;
                end loop;
                fill_in_progress <= '0';
            end if;
        end if;
    end process;

    --------------------------------------------------------------------------------------
    -- Cache replacement policy; which way should be overwritten, if there is no space? --
    --------------------------------------------------------------------------------------

    -- Update the next way selection when the cache line fill is about to be completed
    update_next_way <= cache_wr_en and cache_wr_last;

    GEN_REPLACEMENT_SIMPLE : if (G_REPLACEMENT_POLICY = "simple") generate
        next_way_proc : process (clk) is
        begin
            if (rising_edge(clk)) then
                if (update_next_way = '1') then
                    next_way <= to_integer(to_unsigned(next_way, log2ceil(G_CACHE_WAYS)) + 1);
                end if;
                if (rst = '1') then
                    next_way <= 0;
                end if;
            end if;
        end process;
    end generate;

    GEN_REPLACEMENT_LFSR : if (G_REPLACEMENT_POLICY = "lfsr") generate
        signal lfsr : std_logic_vector(7 downto 0);
    begin
        next_way_proc : process (clk) is
        begin
            if (rising_edge(clk)) then
                lfsr <= lfsr(6 downto 0) & (lfsr(7) xor lfsr(5) xor lfsr(4) xor lfsr(3));

                if (update_next_way = '1') then
                    next_way <= to_integer(unsigned(lfsr(7 downto (8 - log2ceil(G_CACHE_WAYS)))));
                end if;

                if (rst = '1') then
                    lfsr     <= std_logic_vector(to_unsigned(G_RANDOM_SEED, lfsr'length));
                    next_way <= 0;
                end if;
            end if;
        end process;
    end generate;

    -- "round-robin"
    GEN_ROUND_ROBIN_NEXT_WAY : if (G_REPLACEMENT_POLICY = "round-robin") generate

        -- Use an array of pointers to track which way should be selected next for the set
        type ptr_array_t is array (0 to G_CACHE_SETS - 1) of natural range 0 to (G_CACHE_WAYS - 1);
        signal set_ptr_array : ptr_array_t := (others => 0);

    begin
        next_way_proc : process (clk) is
            variable v_ptr : natural range 0 to (G_CACHE_WAYS - 1);
        begin
            if (rising_edge(clk)) then
                if (update_next_way) then
                    v_ptr := (set_ptr_array(to_uint(wr_index)) + 1) mod G_CACHE_WAYS;
                    set_ptr_array(to_uint(wr_index)) <= v_ptr;
                    next_way                         <= v_ptr;
                end if;
                if (rst = '1') then
                    next_way <= 0;
                end if;
            end if;
        end process;
    end generate;

end architecture;
