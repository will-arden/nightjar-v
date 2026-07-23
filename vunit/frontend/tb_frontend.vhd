library vunit_lib;
context vunit_lib.vunit_context;

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;
use std.textio.all;

use work.common_pkg.all;

entity tb_frontend is
    generic (
        runner_cfg      : string;
        G_IMEM_DEPTH    : positive := 1024;
        G_MEM_INIT_PATH : string
    );
end entity;

architecture tb of tb_frontend is

    constant C_CLK_PERIOD : time    := 10 ns;
    constant C_SIM_TICKS  : natural := 500;

    -- Test signals
    signal clk              : std_logic := '0';
    signal rst              : std_logic := '1';
    signal instr_addr       : std_logic_vector(log2ceil(G_IMEM_DEPTH) - 1 downto 0);
    signal instr_addr_valid : std_logic;
    signal instr_addr_ready : std_logic;
    signal instr_data       : std_logic_vector(31 downto 0);
    signal instr_data_valid : std_logic;
    signal instr_data_ready : std_logic;
    signal wb_imem_addr     : std_logic_vector(log2ceil(G_IMEM_DEPTH) - 1 downto 0);
    signal wb_imem_data     : std_logic_vector(31 downto 0);
    signal wb_imem_req      : std_logic;
    signal wb_imem_ack      : std_logic;
    signal wb_imem_cyc      : std_logic;

begin

    ------------------------------
    -- Fetch request generation --
    ------------------------------

    fetch_req_proc : process is
        file f            : text open read_mode is G_MEM_INIT_PATH;
        variable line     : line;
        variable addr     : integer;
        variable expected : std_logic_vector(31 downto 0);
        variable comma    : character;
        variable nullc    : character;
    begin
        READLINE(f, line); -- Skip header

        while not endfile(f) loop

            -- Read the next CSV row
            READLINE(f, line);
            READ(line, addr);
            READ(line, comma);
            READ(line, expected);

            -- Request the instruction
            instr_addr_valid <= '1';
            instr_addr       <= std_logic_vector(to_unsigned(addr, instr_addr'length));

            -- Wait until there is a handshake before continuing
            wait until (instr_addr_ready = '1');

            -- TODO: Probability to stall, where valid is de-asserted after a good handshake

            wait until rising_edge(clk);
        end loop;
        wait;
    end process;

    instr_data_ready <= '1';

    ------------------------
    -- Instruction memory --
    ------------------------

    x_imem : entity work.imem
        generic map(
            G_IMEM_DEPTH           => G_IMEM_DEPTH,
            G_MEM_INIT_PATH        => G_MEM_INIT_PATH,
            G_BASE_RESPONSE_CYC    => 2,  -- Normal latency in clock cycles
            G_PENALTY_RESPONSE_CYC => 20, -- Number of clock cycles' latency added during a penalty
            G_PENALTY_PROB         => 10  -- % chance for a penalty to occur
        )
        port map
        (
            clk          => clk,
            wb_imem_addr => wb_imem_addr,
            wb_imem_data => wb_imem_data,
            wb_imem_req  => wb_imem_req,
            wb_imem_ack  => wb_imem_ack,
            wb_imem_cyc  => wb_imem_cyc
        );

    ---------
    -- DUT --
    ---------

    x_frontend : entity work.frontend
        generic map(
            G_IMEM_DEPTH => G_IMEM_DEPTH
        )
        port map
        (
            clk              => clk,
            rst              => rst,
            instr_addr       => instr_addr,
            instr_addr_valid => instr_addr_valid,
            instr_addr_ready => instr_addr_ready,
            instr_data       => instr_data,
            instr_data_valid => instr_data_valid,
            instr_data_ready => instr_data_ready,
            wb_imem_addr     => wb_imem_addr,
            wb_imem_data     => wb_imem_data,
            wb_imem_req      => wb_imem_req,
            wb_imem_ack      => wb_imem_ack,
            wb_imem_cyc      => wb_imem_cyc
        );

    ----------------------
    -- Misc. test setup --
    ----------------------

    -- Generate clock and reset
    clk <= not clk after C_CLK_PERIOD;
    rst <= '1', '0' after 10 * C_CLK_PERIOD;

    -- VUnit entry
    main : process is
    begin
        test_runner_setup(runner, runner_cfg);
        report "Frontend test beginning...";

        -- -- Init values
        -- instr_addr <= (others => '0');
        -- instr_addr_valid <= '0';
        -- instr_data_ready <= '1';
        -- wb_imem_ack <= '0';
        -- wait for 10 * C_CLK_PERIOD;

        -- -- Request a fetch
        -- instr_addr <= std_logic_vector(to_unsigned(10, instr_addr'length));
        -- instr_addr_valid <= '1';
        -- wait for C_CLK_PERIOD;
        -- instr_addr_valid <= '0';

        -- -- Wait a few cycles, then provide an acknowledgement from memory
        -- wait for 3 * C_CLK_PERIOD;
        -- wb_imem_ack <= '1';
        -- wait for C_CLK_PERIOD;
        -- wb_imem_ack <= '0';

        wait for C_SIM_TICKS * C_CLK_PERIOD;
        test_runner_cleanup(runner);
    end process main;

end architecture;