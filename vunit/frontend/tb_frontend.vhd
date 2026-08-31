library vunit_lib;
context vunit_lib.vunit_context;

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;
use std.textio.all;
use ieee.std_logic_textio.all;

use work.common_pkg.all;

entity tb_frontend is
    generic (
        runner_cfg          : string;
        G_IMEM_DEPTH        : positive := 1024;
        G_MEM_INIT_PATH     : string;
        G_TRANSACTIONS_PATH : string;
        G_RESULTS_PATH      : string;

        -- Decode properties
        G_DECODE_SEED_A             : integer                := 1234;
        G_DECODE_SEED_B             : integer                := 5678;
        G_DECODE_ADDR_STALL_PROB    : natural range 0 to 100 := 15;
        G_DECODE_ADDR_STALL_PENALTY : natural                := 10
    );
end entity;

architecture tb of tb_frontend is

    -- Define an arbitrary clock period
    constant C_CLK_PERIOD : time := 10 ns;

    -- Signal to denote the end of the test
    signal tb_end : std_logic := '0';

    -- DUT signals
    signal clk              : std_logic := '0';
    signal rst              : std_logic := '1';
    signal instr_addr       : std_logic_vector(31 downto 0);
    signal instr_addr_valid : std_logic;
    signal instr_addr_ready : std_logic;
    signal instr_data       : std_logic_vector(31 downto 0);
    signal instr_data_valid : std_logic;
    signal instr_data_ready : std_logic;
    signal wb_imem_addr     : std_logic_vector(31 downto 0);
    signal wb_imem_data     : std_logic_vector(31 downto 0);
    signal wb_imem_stb      : std_logic;
    signal wb_imem_ack      : std_logic;
    signal wb_imem_cyc      : std_logic;

begin

    ------------------------------
    -- Fetch request generation --
    ------------------------------

    fetch_req_proc : process is
        file f                : text open read_mode is G_TRANSACTIONS_PATH;
        variable line         : line;
        variable addr         : natural;
        variable expected     : std_logic_vector(31 downto 0);
        variable actual       : character; -- No value yet
        variable latency      : character; -- No value yet
        variable comma        : character;
        variable nullc        : character;
        variable stall_seed_a : integer := G_DECODE_SEED_A;
        variable stall_seed_b : integer := G_DECODE_SEED_B;
        variable stall_r      : real;
        variable penalty      : natural range 0 to (G_DECODE_ADDR_STALL_PENALTY - 1);
    begin

        -- A short pause before the simulation begins
        instr_addr_valid <= '0';
        instr_addr       <= (others => '0');
        wait for C_CLK_PERIOD * 5;

        READLINE(f, line); -- Skip header

        while not endfile(f) loop

            -- Read the next CSV row
            READLINE(f, line);
            READ(line, addr);
            READ(line, comma);
            READ(line, expected);
            READ(line, comma);
            READ(line, actual);
            READ(line, comma);
            READ(line, latency);

            -- Randomly cause a stall
            uniform(stall_seed_a, stall_seed_b, stall_r);                    -- Generate a random number
            if (stall_r < (real(G_DECODE_ADDR_STALL_PROB)) / real(100)) then -- Decide if there is a stall
                instr_addr_valid <= '0';                                         -- Invalidate request
                for cyc in 0 to (G_DECODE_ADDR_STALL_PENALTY - 1) loop           -- Stall for N cycles
                    wait until rising_edge(clk);
                end loop;
            end if;

            -- Request the instruction
            instr_addr_valid <= '1';
            instr_addr       <= std_logic_vector(to_unsigned(addr, instr_addr'length));

            wait until rising_edge(clk);

            -- Wait until there is a handshake before continuing
            while (instr_addr_ready = '0') loop
                wait until rising_edge(clk);
            end loop;
        end loop;

        -- End the simulation
        instr_addr_valid <= '0';
        while not (instr_addr_valid = '0' and instr_addr_ready = '1' and instr_data_valid = '0') loop
            wait until rising_edge(clk);
        end loop;
        tb_end <= '1';
        wait;
    end process;

    -- Model the Decode stage as always ready
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
            wb_imem_stb  => wb_imem_stb,
            wb_imem_ack  => wb_imem_ack,
            wb_imem_cyc  => wb_imem_cyc
        );

    ---------
    -- DUT --
    ---------

    x_frontend : entity work.frontend
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
            wb_imem_stb      => wb_imem_stb,
            wb_imem_ack      => wb_imem_ack,
            wb_imem_cyc      => wb_imem_cyc
        );

    --------------------
    -- Output results --
    --------------------

    results_proc : process is
        file f     : text open write_mode is G_RESULTS_PATH;
        variable l : line;
        variable i : integer := 0;
    begin
        write(l, string'("instr_data"));
        writeline(f, l);

        while (true) loop
            if (instr_data_ready = '1' and instr_data_valid = '1') then
                write(l, instr_data);
                writeline(f, l);
            end if;
            wait until rising_edge(clk);
        end loop;
        wait;
    end process;

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
        wait until rising_edge(tb_end);
        test_runner_cleanup(runner);
    end process main;

end architecture;