library vunit_lib;
context vunit_lib.vunit_context;

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.common_pkg.all;

entity tb_cache is
    generic (
        runner_cfg : string;

        -- DUT generics
        G_CACHE_SETS         : natural := 16;
        G_CACHE_WAYS         : natural := 4;
        G_CACHE_LINE_WIDTH   : natural := 4;
        G_ASYNC_READ         : boolean := false;
        G_REPLACEMENT_POLICY : string  := "round-robin"
    );
end;

architecture tb of tb_cache is

    -- Constants
    constant C_CLK_PERIOD  : time    := 10 ns;
    constant C_OFFSET_BITS : natural := log2ceil(4 * G_CACHE_LINE_WIDTH); -- 2-bit LSBs should be ignored (byte-aligned)
    constant C_INDEX_BITS  : natural := log2ceil(G_CACHE_SETS);
    constant C_TAG_BITS    : natural := 32 - C_INDEX_BITS - C_OFFSET_BITS;

    -- Ports
    signal clk           : std_logic                     := '0';
    signal rst           : std_logic                     := '0';
    signal cache_rd_en   : std_logic                     := '0';
    signal cache_rd_addr : std_logic_vector(31 downto 0) := (others => '0');
    signal cache_rd_data : std_logic_vector(31 downto 0);
    signal cache_rd_mask : std_logic_vector(G_CACHE_LINE_WIDTH - 1 downto 0);
    signal cache_rd_hit  : std_logic;
    signal cache_wr_en   : std_logic                     := '0';
    signal cache_wr_addr : std_logic_vector(31 downto 0) := (others => '0');
    signal cache_wr_data : std_logic_vector(31 downto 0) := (others => '0');
    signal cache_wr_last : std_logic                     := '0';

begin

    -- Clock and reset generation
    clk <= not clk after (C_CLK_PERIOD / 2);
    rst <= '1', '0' after (5 * C_CLK_PERIOD);

    ---------------------
    -- Instantiate DUT --
    ---------------------

    x_cache : entity work.cache
        generic map(
            G_CACHE_SETS         => G_CACHE_SETS,
            G_CACHE_WAYS         => G_CACHE_WAYS,
            G_CACHE_LINE_WIDTH   => G_CACHE_LINE_WIDTH,
            G_ASYNC_READ         => G_ASYNC_READ,
            G_REPLACEMENT_POLICY => G_REPLACEMENT_POLICY
        )
        port map
        (
            clk           => clk,
            rst           => rst,
            cache_rd_en   => cache_rd_en,
            cache_rd_addr => cache_rd_addr,
            cache_rd_data => cache_rd_data,
            cache_rd_mask => cache_rd_mask,
            cache_rd_hit  => cache_rd_hit,
            cache_wr_en   => cache_wr_en,
            cache_wr_addr => cache_wr_addr,
            cache_wr_data => cache_wr_data,
            cache_wr_last => cache_wr_last
        );

    -----------------
    -- VUnit entry --
    -----------------

    main : process is

        -- Procedure to write to the cache
        procedure cache_write (addr : std_logic_vector(31 downto 0); data : std_logic_vector(31 downto 0); last : std_logic) is
        begin
            info("WRITING " & to_hstring(data) & "@ ADDRESS " & to_hstring(addr));
            cache_wr_en   <= '1';
            cache_wr_addr <= addr;
            cache_wr_data <= data;
            cache_wr_last <= last;
            wait until rising_edge(clk);
            cache_wr_en <= '0';
        end procedure;

        variable v_addr     : std_logic_vector(31 downto 0) := (others => '0');
        variable v_tag_base : natural                       := 0;
        variable v_last     : std_logic                     := '0';
    begin
        test_runner_setup(runner, runner_cfg);
        while test_suite loop
            if run("test_0") then
                info("Beginning cache simulation...");
                wait until (rst = '0');
                wait for (10 * C_CLK_PERIOD);
                wait until rising_edge(clk);

                -- Update every set by populating the cache line of a single way, then loop again to overwrite everything with "new" values
                for m in 1 to 2 loop
                    for s in 0 to (G_CACHE_SETS - 1) loop
                        for w in 0 to (G_CACHE_WAYS - 1) loop
                            for x in 0 to (G_CACHE_LINE_WIDTH - 1) loop

                                -- Compute the write address
                                v_addr                                                                                        := (others => '0');                                           -- Re-initialise
                                v_addr(C_OFFSET_BITS - 1 downto 0)                                                            := std_logic_vector(to_unsigned(4 * x, C_OFFSET_BITS));       -- Offset bits
                                v_addr((C_INDEX_BITS + C_OFFSET_BITS) - 1 downto C_OFFSET_BITS)                               := std_logic_vector(to_unsigned(s, C_INDEX_BITS));            -- Set bits
                                v_addr((C_TAG_BITS + C_INDEX_BITS + C_OFFSET_BITS) - 1 downto (C_INDEX_BITS + C_OFFSET_BITS)) := std_logic_vector(to_unsigned(w + v_tag_base, C_TAG_BITS)); -- Give every way a different tag

                                -- Assert the flag if this is the last write in the cache line
                                v_last := '0';
                                if (x = G_CACHE_LINE_WIDTH - 1) then
                                    v_last := '1';
                                end if;

                                -- Perform the write
                                cache_write(v_addr, std_logic_vector(to_unsigned(w, 32)), v_last);

                            end loop;
                        end loop;
                    end loop;
                    wait until rising_edge(clk);

                    -- -- Re-initialise the address and change the tag base to something new (imagine a new region of memory is being written)
                    -- v_tag_base                                                                                    := v_tag_base + 1;
                    -- v_addr                                                                                        := (others => '0');
                    -- v_addr((C_TAG_BITS + C_INDEX_BITS + C_OFFSET_BITS) - 1 downto (C_INDEX_BITS + C_OFFSET_BITS)) := std_logic_vector(to_unsigned(0 + v_tag_base, C_TAG_BITS)); -- Give every way a different tag
                    -- cache_write(v_addr, std_logic_vector(to_unsigned(48, 32)), v_last);
                    -- cache_write(v_addr, std_logic_vector(to_unsigned(72, 32)), v_last);
                end loop;

                wait for 100 * C_CLK_PERIOD;
                test_runner_cleanup(runner);
            end if;
        end loop;
    end process main;

    -- clk <= not clk after C_CLK_PERIOD/2;

end architecture;