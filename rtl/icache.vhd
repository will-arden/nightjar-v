library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.common_pkg.all;

entity icache is
    generic (
        G_ICACHE_SETS       : natural := 16; -- Number of cache sets (the depth of the cache)
        G_ICACHE_WAYS       : natural := 4;  -- Number of cache ways
        G_ICACHE_LINE_WIDTH : natural := 4   -- Width of each cache line in 32-bit increments (must be a power of 2)
    );
    port (
        clk : in std_logic;
        rst : in std_logic;

        -- Cache read interface
        ic_rd_addr : in std_logic_vector(31 downto 0);
        ic_rd_data : out std_logic_vector(31 downto 0);
        ic_rd_hit  : out std_logic;

        -- Cache update interface
        ic_write   : in std_logic;
        ic_wr_addr : in std_logic_vector(31 downto 0);
        ic_wr_data : in std_logic_vector(31 downto 0)
    );
end entity;

architecture rtl of icache is

    constant C_ICACHE_DEPTH : natural := G_ICACHE_SETS * G_ICACHE_WAYS;

    -- Compute the number of offset, index and tag bits in the address
    constant C_OFFSET_BITS : natural := log2ceil(4 * G_ICACHE_LINE_WIDTH); -- 2-bit LSBs should be ignored (byte-aligned)
    constant C_INDEX_BITS  : natural := log2ceil(G_ICACHE_SETS);
    constant C_TAG_BITS    : natural := 32 - C_INDEX_BITS - C_OFFSET_BITS;

    -- A line of cache is an array of multiple instructions
    type line_t is array (0 to (G_ICACHE_LINE_WIDTH - 1)) of std_logic_vector(31 downto 0);

    -- Lines are grouped to form ways; a way is a single cache entry, selected using a "tag"
    type way_t is record
        valid : std_logic;
        tag   : std_logic_vector(C_TAG_BITS - 1 downto 0);
        line  : line_t;
    end record;

    -- Ways are grouped into sets, which are selected by an "index"
    type set_t is array (0 to (G_ICACHE_WAYS - 1)) of way_t;

    -- I-Cache is composed of sets, which are composed of ways, which are composed of instruction data
    type icache_t is array (0 to (G_ICACHE_SETS - 1)) of set_t;
    signal icache : icache_t;

    -- Slices of rd/wr addresses
    signal rd_offset : std_logic_vector(C_OFFSET_BITS - 3 downto 0);
    signal rd_index  : std_logic_vector(C_INDEX_BITS - 1 downto 0);
    signal rd_tag    : std_logic_vector(C_TAG_BITS - 1 downto 0);
    signal wr_offset : std_logic_vector(C_OFFSET_BITS - 3 downto 0);
    signal wr_index  : std_logic_vector(C_INDEX_BITS - 1 downto 0);
    signal wr_tag    : std_logic_vector(C_TAG_BITS - 1 downto 0);

    -- Misc. signals
    signal rand_reg       : natural range 0 to (G_ICACHE_WAYS - 1)       := 0;
    signal way_sel        : natural range 0 to (G_ICACHE_WAYS - 1)       := 0;
    signal update_counter : natural range 0 to (G_ICACHE_LINE_WIDTH - 1) := 0;
begin

    -- Slice the tag, index and offset for the rd/wr addresses
    rd_offset <= ic_rd_addr(C_OFFSET_BITS - 1 downto 2);
    rd_index  <= ic_rd_addr((C_INDEX_BITS + C_OFFSET_BITS) - 1 downto C_OFFSET_BITS);
    rd_tag    <= ic_rd_addr((C_TAG_BITS + C_INDEX_BITS + C_OFFSET_BITS) - 1 downto (C_INDEX_BITS + C_OFFSET_BITS));
    wr_offset <= ic_wr_addr(C_OFFSET_BITS - 1 downto 2);
    wr_index  <= ic_wr_addr((C_INDEX_BITS + C_OFFSET_BITS) - 1 downto C_OFFSET_BITS);
    wr_tag    <= ic_wr_addr((C_TAG_BITS + C_INDEX_BITS + C_OFFSET_BITS) - 1 downto (C_INDEX_BITS + C_OFFSET_BITS));

    -- Process to control synchronous writes to the cache during updates
    cache_wr_proc : process (clk) is
    begin
        if (rising_edge(clk)) then

            -- Count the progress of the cache line update
            if (ic_write = '1') then
                if (update_counter = (G_ICACHE_LINE_WIDTH - 1)) then
                    update_counter <= 0;
                else
                    update_counter <= update_counter + 1;
                end if;
            end if;

            -- Generate a random number
            if (rand_reg = G_ICACHE_WAYS - 1) then
                rand_reg <= 0;
            else
                rand_reg <= rand_reg + 1;
            end if;

            -- When the counter expires, the cache line update is complete
            if (update_counter = (G_ICACHE_LINE_WIDTH - 1) and ic_write = '1') then
                way_sel                                  <= rand_reg; -- Choose a new way for the next update
                icache(to_uint(wr_index))(way_sel).valid <= '1';      -- Validate the way
            end if;

            -- Write to the cache
            if (ic_write = '1') then
                icache(to_uint(wr_index))(way_sel).tag                      <= wr_tag;     -- Update the tag
                icache(to_uint(wr_index))(way_sel).line(to_uint(wr_offset)) <= ic_wr_data; -- Update one slice of the line
            end if;

            -- Reset
            if (rst = '1') then
                way_sel <= 0;
                for set in 0 to (G_ICACHE_SETS - 1) loop
                    for way in 0 to (G_ICACHE_WAYS - 1) loop
                        icache(set)(way).valid <= '0';
                    end loop;
                end loop;
            end if;
        end if;
    end process;

    -- Process to control the asynchronous reads from cache
    cache_rd_proc : process (ic_rd_addr) is
        variable found : boolean;
        variable ln    : line_t;
    begin
        found := false;

        -- Check each way of the indexed set
        for w in 0 to (G_ICACHE_WAYS - 1) loop
            if (icache(to_uint(rd_index))(w).valid = '1') then  -- Only check valid entries
                if (icache(to_uint(rd_index))(w).tag = rd_tag) then -- Match the way's tag
                    found := true;
                    ln    := icache(to_uint(rd_index))(w).line;
                end if;
            end if;
        end loop;

        -- Slice the requested instruction from the line
        ic_rd_data <= ln(to_uint(rd_offset));

        -- Assert the "hit" flag
        if (found) then
            ic_rd_hit <= '1';
        else
            ic_rd_hit <= '0';
        end if;

    end process;

end architecture;
