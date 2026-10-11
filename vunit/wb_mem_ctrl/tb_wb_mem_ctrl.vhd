
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library vunit_lib;
context vunit_lib.vunit_context;

entity tb_wb_mem_ctrl is
    generic (
        runner_cfg   : string;
        G_ADDR_WIDTH : positive := 32;
        G_DATA_WIDTH : positive := 32;
        G_MEM_DEPTH  : positive := 1024;

        -- Memory generics
        G_BASE_LATENCY      : positive               := 3;
        G_PENALTY_LATENCY   : positive               := 50;
        G_PENALTY_PROB_X100 : natural range 0 to 100 := 20;
        G_ERR_PROB_X100     : natural range 0 to 100 := 10;
        G_RTY_PROB_X100     : natural range 0 to 100 := 10;
        G_RANDOM_SEED_A     : natural                := 1234;
        G_RANDOM_SEED_B     : natural                := 5678
    );
end;

architecture tb of tb_wb_mem_ctrl is

    -- Clock period
    constant C_CLK_PERIOD : time := 10 ns;

    -- DUT ports
    signal clk            : std_logic := '0';
    signal rst            : std_logic;
    signal rd_req_valid   : std_logic;
    signal rd_req_ready   : std_logic;
    signal rd_req_addr    : std_logic_vector(G_ADDR_WIDTH - 1 downto 0);
    signal wr_req_valid   : std_logic;
    signal wr_req_ready   : std_logic;
    signal wr_req_addr    : std_logic_vector(G_ADDR_WIDTH - 1 downto 0);
    signal wr_req_byte_en : std_logic_vector((((G_DATA_WIDTH + 7) / 8)) - 1 downto 0);
    signal wr_req_data    : std_logic_vector(G_DATA_WIDTH - 1 downto 0);
    signal rd_resp_valid  : std_logic;
    signal rd_resp_ready  : std_logic;
    signal rd_resp_data   : std_logic_vector(G_DATA_WIDTH - 1 downto 0);
    signal rd_resp_err    : std_logic;
    signal wb_mem_stb     : std_logic;
    signal wb_mem_ack     : std_logic;
    signal wb_mem_cyc     : std_logic;
    signal wb_mem_err     : std_logic;
    signal wb_mem_rty     : std_logic;
    signal wb_mem_wr_en   : std_logic;
    signal wb_mem_byte_en : std_logic_vector((((G_DATA_WIDTH + 7) / 8)) - 1 downto 0);
    signal wb_mem_addr    : std_logic_vector(G_ADDR_WIDTH - 1 downto 0);
    signal wb_mem_rd_data : std_logic_vector(G_DATA_WIDTH - 1 downto 0);
    signal wb_mem_wr_data : std_logic_vector(G_DATA_WIDTH - 1 downto 0);

    -- Memory ports
    -- signal wb_cyc_i : std_logic;
    -- signal wb_stb_i : std_logic;
    -- signal wb_we_i  : std_logic;
    -- signal wb_adr_i : std_logic_vector(G_ADDR_WIDTH - 1 downto 0);
    -- signal wb_sel_i : std_logic_vector(((G_DATA_WIDTH + 7) / 8) - 1 downto 0);
    -- signal wb_dat_i : std_logic_vector(G_DATA_WIDTH - 1 downto 0);
    -- signal wb_ack_o : std_logic;
    -- signal wb_err_o : std_logic;
    -- signal wb_rty_o : std_logic;
    -- signal wb_dat_o : std_logic_vector(G_DATA_WIDTH - 1 downto 0);

    -- Reference memory
    type mem_t is array (0 to G_MEM_DEPTH - 1) of std_logic_vector(G_DATA_WIDTH - 1 downto 0);
    signal ref_mem : mem_t := (others => (others => '0'));

begin

    -- Generate clock and reset
    clk <= not clk after (C_CLK_PERIOD / 2);
    rst <= '1', '0' after (10 * C_CLK_PERIOD);

    ---------------------
    -- Instantiate DUT --
    ---------------------

    x_wb_mem_ctrl : entity work.wb_mem_ctrl
        generic map(
            G_ADDR_WIDTH => G_ADDR_WIDTH,
            G_DATA_WIDTH => G_DATA_WIDTH
        )
        port map
        (
            clk            => clk,
            rst            => rst,
            rd_req_valid   => rd_req_valid,
            rd_req_ready   => rd_req_ready,
            rd_req_addr    => rd_req_addr,
            wr_req_valid   => wr_req_valid,
            wr_req_ready   => wr_req_ready,
            wr_req_addr    => wr_req_addr,
            wr_req_byte_en => wr_req_byte_en,
            wr_req_data    => wr_req_data,
            rd_resp_valid  => rd_resp_valid,
            rd_resp_ready  => rd_resp_ready,
            rd_resp_data   => rd_resp_data,
            rd_resp_err    => rd_resp_err,
            wb_mem_stb     => wb_mem_stb,
            wb_mem_ack     => wb_mem_ack,
            wb_mem_cyc     => wb_mem_cyc,
            wb_mem_err     => wb_mem_err,
            wb_mem_rty     => wb_mem_rty,
            wb_mem_wr_en   => wb_mem_wr_en,
            wb_mem_byte_en => wb_mem_byte_en,
            wb_mem_addr    => wb_mem_addr,
            wb_mem_rd_data => wb_mem_rd_data,
            wb_mem_wr_data => wb_mem_wr_data
        );

    ----------------------------------
    -- Instantiate memory component --
    ----------------------------------

    x_wb_mem : entity work.wb_mem
        generic map(
            G_MEM_DEPTH         => G_MEM_DEPTH,
            G_ADDR_WIDTH        => G_ADDR_WIDTH,
            G_DATA_WIDTH        => G_DATA_WIDTH,
            G_BASE_LATENCY      => G_BASE_LATENCY,
            G_PENALTY_LATENCY   => G_PENALTY_LATENCY,
            G_PENALTY_PROB_X100 => G_PENALTY_PROB_X100,
            G_ERR_PROB_X100     => G_ERR_PROB_X100,
            G_RTY_PROB_X100     => G_RTY_PROB_X100,
            G_RANDOM_SEED_A     => G_RANDOM_SEED_A,
            G_RANDOM_SEED_B     => G_RANDOM_SEED_B
        )
        port map
        (
            clk      => clk,
            rst      => rst,
            wb_cyc_i => wb_mem_cyc,
            wb_stb_i => wb_mem_stb,
            wb_we_i  => wb_mem_wr_en,
            wb_adr_i => wb_mem_addr,
            wb_sel_i => wb_mem_byte_en,
            wb_dat_i => wb_mem_wr_data,
            wb_ack_o => wb_mem_ack,
            wb_err_o => wb_mem_err,
            wb_rty_o => wb_mem_rty,
            wb_dat_o => wb_mem_rd_data
        );

    -----------------
    -- VUnit entry --
    -----------------

    main : process is

        -- Procedure to request a write
        procedure wr_req (addr : in std_logic_vector; data : in std_logic_vector; byte_en : in std_logic_vector; timeout : in positive) is
            variable v_timer : natural := 0;
        begin
            report "New write request (address = 0x" & to_hstring(addr) & ", data = 0x" & to_hstring(data) & ")";
            ref_mem(to_integer(unsigned(addr(addr'high downto 2)))) <= data; -- Update the reference memory

            -- Issue the request
            wr_req_valid   <= '1';
            wr_req_addr    <= addr;
            wr_req_data    <= data;
            wr_req_byte_en <= byte_en;
            wait until rising_edge(clk);
            while (wr_req_ready = '0') loop
                v_timer := v_timer + 1;
                assert (v_timer < timeout) report "Write request failed; timeout reached." severity failure;
                wait until rising_edge(clk);
            end loop;
            wr_req_valid <= '0';
        end procedure;

    begin
        test_runner_setup(runner, runner_cfg);
        while test_suite loop
            if run("test_0") then
                info("Beginning wb_mem_ctrl test...");

                -- Default signal assigments
                rd_req_valid   <= '0';
                rd_req_addr    <= (others => '0');
                wr_req_valid   <= '0';
                wr_req_addr    <= (others => '0');
                wr_req_byte_en <= (others => '1');
                wr_req_data    <= (others => '0');
                rd_resp_ready  <= '0';
                wait until rst = '0';
                wait for (5 * C_CLK_PERIOD);
                wait until rising_edge(clk);

                -- Request several writes
                for i in 0 to 3 loop
                    wr_req(
                    addr    => std_logic_vector(to_unsigned((i * 4), G_ADDR_WIDTH)),
                    data    => std_logic_vector(to_unsigned((i * 4) + 1, G_DATA_WIDTH)),
                    byte_en => (wr_req_byte_en'range => '0'),
                    timeout => 500
                    );
                end loop;

                wait for (100 * C_CLK_PERIOD);
                test_runner_cleanup(runner);
            end if;
        end loop;
    end process;

end architecture;
