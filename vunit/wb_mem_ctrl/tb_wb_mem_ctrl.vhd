
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library vunit_lib;
context vunit_lib.vunit_context;

entity tb_wb_mem_ctrl is
    generic (
        runner_cfg   : string;
        G_ADDR_WIDTH : positive := 32;
        G_DATA_WIDTH : positive := 32
    );
end;

architecture tb of tb_wb_mem_ctrl is

    -- Clock period
    constant C_CLK_PERIOD : time := 10 ns;

    -- Ports
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

begin

    -- Generate clock and reset
    clk <= not clk after (C_CLK_PERIOD / 2);
    rst <= '0', '1' after (10 * C_CLK_PERIOD);

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

    -----------------
    -- VUnit entry --
    -----------------

    main : process is
    begin
        test_runner_setup(runner, runner_cfg);
        while test_suite loop
            if run("test_0") then
                info("Beginning wb_mem_ctrl test...");

                -- Test goes here

                wait for (100 * C_CLK_PERIOD);
                test_runner_cleanup(runner);
            end if;
        end loop;
    end process;

end architecture;
