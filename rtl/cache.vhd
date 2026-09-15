library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.common_pkg.all;

entity cache is
    generic (
        G_CACHE_SETS         : natural := 16;      -- Number of cache sets (the depth of the cache)
        G_CACHE_WAYS         : natural := 4;       -- Number of cache ways
        G_CACHE_LINE_WIDTH   : natural := 4;       -- Width of each cache line in 32-bit increments (must be a power of 2)
        G_ASYNC_READ         : boolean := false;   -- When false, reads are performed asynchronously
        G_REPLACEMENT_POLICY : string  := "simple" -- "simple", TODO: "round-robin", "pseudo-random", "replace-oldest"
    );
    port (
        clk : in std_logic;
        rst : in std_logic;

        -- Cache read interface
        cache_rd_en   : in std_logic;
        cache_rd_addr : in std_logic_vector(31 downto 0);
        cache_rd_data : out std_logic_vector(31 downto 0);
        cache_rd_hit  : out std_logic;

        -- Cache write interface
        cache_wr_en   : in std_logic;
        cache_wr_addr : in std_logic_vector(31 downto 0);
        cache_wr_data : in std_logic_vector(31 downto 0)
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
    signal next_way       : natural range 0 to (G_CACHE_WAYS - 1)       := 0;
    signal way_sel        : natural range 0 to (G_CACHE_WAYS - 1)       := 0;
    signal update_counter : natural range 0 to (G_CACHE_LINE_WIDTH - 1) := 0;
begin

    -- Slice the tag, index and offset for the rd/wr addresses
    rd_offset <= cache_rd_addr(C_OFFSET_BITS - 1 downto 2);
    rd_index  <= cache_rd_addr((C_INDEX_BITS + C_OFFSET_BITS) - 1 downto C_OFFSET_BITS);
    rd_tag    <= cache_rd_addr((C_TAG_BITS + C_INDEX_BITS + C_OFFSET_BITS) - 1 downto (C_INDEX_BITS + C_OFFSET_BITS));
    wr_offset <= cache_wr_addr(C_OFFSET_BITS - 1 downto 2);
    wr_index  <= cache_wr_addr((C_INDEX_BITS + C_OFFSET_BITS) - 1 downto C_OFFSET_BITS);
    wr_tag    <= cache_wr_addr((C_TAG_BITS + C_INDEX_BITS + C_OFFSET_BITS) - 1 downto (C_INDEX_BITS + C_OFFSET_BITS));

    ---------------------------------------------------------------------
    -- Implement a cache replacement policy; which way is overwritten? --
    ---------------------------------------------------------------------

    -- "simple" (a little bit random)
    GEN_SIMPLE_NEXT_WAY : if (G_REPLACEMENT_POLICY = "simple") generate
        next_way_proc : process (clk) is
        begin
            if (rising_edge(clk)) then
                if (next_way = G_CACHE_WAYS - 1) then
                    next_way <= 0;
                else
                    next_way <= next_way + 1;
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

                -- Only act when a cache write is in progress
                if (cache_wr_en = '1') then

                    -- Select the next way when the cache line is filled
                    if (update_counter = (G_CACHE_LINE_WIDTH - 1) and cache_wr_en = '1') then
                        v_ptr := (set_ptr_array(to_uint(wr_index)) + 1) mod G_CACHE_WAYS;
                        set_ptr_array(to_uint(wr_index)) <= v_ptr;
                        next_way <= v_ptr;
                    end if;
                end if;
            end if;
        end process;
    end generate;

    -- TODO:
    -- "pseudo-random"
    -- "replace-oldest"

    -----------------------------------------------------
    -- Write synchronously to the cache during updates --
    -----------------------------------------------------

    cache_wr_proc : process (clk) is
    begin
        if (rising_edge(clk)) then

            -- Count the progress of the cache line update
            if (cache_wr_en = '1') then
                if (update_counter = (G_CACHE_LINE_WIDTH - 1)) then
                    update_counter <= 0;
                else
                    update_counter <= update_counter + 1;
                end if;
            end if;

            -- When the counter expires, the cache line update is complete
            if (update_counter = (G_CACHE_LINE_WIDTH - 1) and cache_wr_en = '1') then
                way_sel                                 <= next_way; -- Choose a new way for the next update
                cache(to_uint(wr_index))(way_sel).valid <= '1';      -- Validate the way
            end if;

            -- Write to the cache
            if (cache_wr_en = '1') then
                cache(to_uint(wr_index))(way_sel).tag                      <= wr_tag;        -- Update the tag
                cache(to_uint(wr_index))(way_sel).line(to_uint(wr_offset)) <= cache_wr_data; -- Update one slice of the line
            end if;

            -- Reset
            if (rst = '1') then
                way_sel <= 0;
                for set in 0 to (G_CACHE_SETS - 1) loop
                    for way in 0 to (G_CACHE_WAYS - 1) loop
                        cache(set)(way).valid <= '0';
                    end loop;
                end loop;
            end if;
        end if;
    end process;

    -------------------------------
    -- Asynchronous cache reads --
    -------------------------------

    GEN_ASYNC_CACHE_READ : if (G_ASYNC_READ) generate
        cache_rd_proc : process (cache, rd_index, cache_rd_en, cache_rd_data, rd_tag, rd_offset) is
            variable found : boolean;
            variable ln    : line_t;
        begin
            if (cache_rd_en = '1') then
                found := false;

                -- Check each way of the indexed set
                for w in 0 to (G_CACHE_WAYS - 1) loop
                    if (cache(to_uint(rd_index))(w).valid = '1') then  -- Only check valid entries
                        if (cache(to_uint(rd_index))(w).tag = rd_tag) then -- Match the way's tag
                            found := true;
                            ln    := cache(to_uint(rd_index))(w).line;
                        end if;
                    end if;
                end loop;

                -- Slice the requested instruction from the line
                cache_rd_data <= ln(to_uint(rd_offset));

                -- Assert the "hit" flag
                if (found) then
                    cache_rd_hit <= '1';
                else
                    cache_rd_hit <= '0';
                end if;
            end if;
        end process;
    end generate;

    -----------------------------
    -- Synchronous cache reads --
    -----------------------------

    GEN_SYNC_CACHE_READ : if (not G_ASYNC_READ) generate
        cache_rd_proc : process (clk) is
            variable found : boolean;
            variable ln    : line_t;
        begin
            if (rising_edge(clk)) then
                if (cache_rd_en = '1') then
                    found := false;

                    -- Check each way of the indexed set
                    for w in 0 to (G_CACHE_WAYS - 1) loop
                        if (cache(to_uint(rd_index))(w).valid = '1') then  -- Only check valid entries
                            if (cache(to_uint(rd_index))(w).tag = rd_tag) then -- Match the way's tag
                                found := true;
                                ln    := cache(to_uint(rd_index))(w).line;
                            end if;
                        end if;
                    end loop;

                    -- Slice the requested instruction from the line
                    cache_rd_data <= ln(to_uint(rd_offset));

                    -- Assert the "hit" flag
                    if (found) then
                        cache_rd_hit <= '1';
                    else
                        cache_rd_hit <= '0';
                    end if;
                end if;

                -- Reset
                if (rst = '1') then
                    cache_rd_hit <= '0';
                end if;
            end if;
        end process;
    end generate;

end architecture;
