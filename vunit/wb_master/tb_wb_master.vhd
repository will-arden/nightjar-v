
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

library vunit_lib;
context vunit_lib.vunit_context;

use work.nj_global_pkg.all;

entity tb_wb_master is
    generic (
        runner_cfg   : string;
        G_ADDR_WIDTH : positive := 32;
        G_DATA_WIDTH : positive := 32;
        G_MEM_DEPTH  : positive := 256;

        G_RANDOM_SEED_A : natural := 1234;
        G_RANDOM_SEED_B : natural := 5678;

        -- Memory generics
        G_BASE_LATENCY      : positive               := 3;
        G_PENALTY_LATENCY   : positive               := 50;
        G_PENALTY_PROB_X100 : natural range 0 to 100 := 20;
        G_ERR_PROB_X100     : natural range 0 to 100 := 5;
        G_RTY_PROB_X100     : natural range 0 to 100 := 5;

        G_RESP_READY_PROB_X100 : positive := 75
    );
end;

architecture tb of tb_wb_master is

    constant C_CLK_PERIOD        : time                         := 10 ns;
    constant C_DEBUG_INSTANCE_ID : std_logic_vector(7 downto 0) := x"00";

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
    signal resp_valid     : std_logic;
    signal resp_ready     : std_logic;
    signal resp_rd        : std_logic;
    signal resp_rd_data   : std_logic_vector(G_DATA_WIDTH - 1 downto 0);
    signal resp_err       : std_logic;
    signal wr_resp_err    : std_logic;
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
    signal dbg_valid      : std_logic;
    signal dbg_component  : std_logic_vector(7 downto 0);
    signal dbg_instance   : std_logic_vector(7 downto 0);
    signal dbg_msg        : std_logic_vector(7 downto 0);

    -- Reference memory
    type mem_t is array (0 to G_MEM_DEPTH - 1) of std_logic_vector(G_DATA_WIDTH - 1 downto 0);
    signal ref_mem : mem_t := (others => (others => '0'));

    -- Misc. testbench signals
    signal number_wb_errors     : natural := 0;
    signal num_responses        : natural := 0;
    signal num_rd_responses     : natural := 0;
    signal num_wr_responses     : natural := 0;
    signal num_err_responses    : natural := 0;
    signal num_rd_err_responses : natural := 0;
    signal num_wr_err_responses : natural := 0;
    signal num_mismatches       : natural := 0;

    type rd_addr_array_t is array (0 to (G_MEM_DEPTH)) of std_logic_vector(31 downto 0);
    signal rd_addr_array        : rd_addr_array_t;
    signal rd_addr_array_wr_ptr : natural := 0;
    signal rd_addr_array_rd_ptr : natural := 0;

begin

    -- Generate clock and reset
    clk <= not clk after (C_CLK_PERIOD / 2);
    rst <= '1', '0' after (10 * C_CLK_PERIOD);

    ---------------------
    -- Instantiate DUT --
    ---------------------

    x_wb_master : entity work.wb_master
        generic map(
            G_ADDR_WIDTH        => G_ADDR_WIDTH,
            G_DATA_WIDTH        => G_DATA_WIDTH,
            G_REQ_FIFO_DEPTH    => 0,
            G_RESP_FIFO_DEPTH   => 0,
            G_DEBUG_INSTANCE_ID => C_DEBUG_INSTANCE_ID
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
            resp_valid     => resp_valid,
            resp_ready     => resp_ready,
            resp_rd        => resp_rd,
            resp_rd_data   => resp_rd_data,
            resp_err       => resp_err,
            wb_mem_stb     => wb_mem_stb,
            wb_mem_ack     => wb_mem_ack,
            wb_mem_cyc     => wb_mem_cyc,
            wb_mem_err     => wb_mem_err,
            wb_mem_rty     => wb_mem_rty,
            wb_mem_wr_en   => wb_mem_wr_en,
            wb_mem_byte_en => wb_mem_byte_en,
            wb_mem_addr    => wb_mem_addr,
            wb_mem_rd_data => wb_mem_rd_data,
            wb_mem_wr_data => wb_mem_wr_data,
            dbg_valid      => dbg_valid,
            dbg_component  => dbg_component,
            dbg_instance   => dbg_instance,
            dbg_msg        => dbg_msg
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

        -- Procedure to request a read
        procedure rd_req (addr : in std_logic_vector; timeout : in positive) is
            variable v_timer : natural := 0;
        begin
            report "New read request (address = 0x" & to_hstring(addr) & ")";
            rd_addr_array(rd_addr_array_wr_ptr) <= addr;                     -- Update read address array
            rd_addr_array_wr_ptr                <= rd_addr_array_wr_ptr + 1; -- Update pointer

            -- Issue the request
            rd_req_valid <= '1';
            rd_req_addr  <= addr;
            wait until rising_edge(clk);
            while (rd_req_ready = '0') loop
                v_timer := v_timer + 1;
                assert (v_timer < timeout) report "Read request failed; timeout reached." severity failure;
                wait until rising_edge(clk);
            end loop;
            rd_req_valid <= '0';
        end procedure;

    begin
        test_runner_setup(runner, runner_cfg);
        while test_suite loop
            if run("write_and_read") then
                info("Beginning write_and_read");

                -- Default signal assigments
                rd_req_valid   <= '0';
                rd_req_addr    <= (others => '0');
                wr_req_valid   <= '0';
                wr_req_addr    <= (others => '0');
                wr_req_byte_en <= (others => '1');
                wr_req_data    <= (others => '0');
                wait until rst = '0';
                wait for (5 * C_CLK_PERIOD);
                wait until rising_edge(clk);

                -- Request a write to every memory location
                for i in 0 to (G_MEM_DEPTH - 1) loop
                    wr_req(
                    addr    => std_logic_vector(to_unsigned((i * 4), G_ADDR_WIDTH)),
                    data    => std_logic_vector(to_unsigned((i * 4) + 1, G_DATA_WIDTH)),
                    byte_en => (wr_req_byte_en'range => '1'),
                    timeout => 500
                    );
                end loop;

                -- Wait for the writes to be completed
                wait for (1000 * C_CLK_PERIOD);

                -- Request the same number of reads
                for i in 0 to (G_MEM_DEPTH - 1) loop
                    rd_req(
                    addr    => std_logic_vector(to_unsigned((i * 4), G_ADDR_WIDTH)),
                    timeout => 500
                    );
                end loop;

                -- Wait for the reads to be completed
                wait for (1000 * C_CLK_PERIOD);

                -- Analyse wb_master responses
                report "";
                report "Total Number of responses: " & integer'image(num_responses);
                report "Number of read responses: " & integer'image(num_rd_responses);
                report "Number of write responses: " & integer'image(num_wr_responses);
                report "Total number of error responses: " & integer'image(num_err_responses);
                report "Number of read error responses: " & integer'image(num_rd_err_responses);
                report "Number of write error responses: " & integer'image(num_wr_err_responses);
                report "Number of bus errors: " & integer'image(number_wb_errors);
                report "Number of write/read data mismatches: " & integer'image(num_mismatches);
                assert (num_responses = (G_MEM_DEPTH * 2)) report "Unexpected number of responses (expected: " & integer'image(2 * G_MEM_DEPTH) & ", received: " & integer'image(num_responses) & ")" severity error;
                assert (num_err_responses = number_wb_errors) report "Number of error responses did not match the number of errors on the bus (bus errors: " & integer'image(number_wb_errors) & ", error responses: " & integer'image(num_err_responses) & ")" severity error;
                assert (num_mismatches = num_wr_err_responses) report "The number of read data mismatches did not match the number of failed write transactions." severity error;

                test_runner_cleanup(runner);
            end if;
        end loop;
    end process;

    -----------------------
    -- Monitor responses --
    -----------------------

    tb_resp_proc : process (clk) is
        variable seed_a : integer := G_RANDOM_SEED_A;
        variable seed_b : integer := G_RANDOM_SEED_B;
        variable r      : real;
        variable addr   : natural := 0;
    begin
        if (rising_edge(clk)) then

            -- Randomly assert resp_ready
            uniform(seed_a, seed_b, r);
            if (integer(real(100) * r) < G_RESP_READY_PROB_X100) then
                resp_ready <= '1';
            else
                resp_ready <= '0';
            end if;

            -- Count rd/wr responses and errors
            if (resp_ready = '1' and resp_valid = '1') then
                num_responses <= num_responses + 1;

                if (resp_rd = '1') then
                    num_rd_responses <= num_rd_responses + 1;
                else
                    num_wr_responses <= num_wr_responses + 1;
                end if;

                if (resp_err = '1') then
                    num_err_responses <= num_err_responses + 1;

                    if (resp_rd = '1') then
                        num_rd_err_responses <= num_rd_err_responses + 1;
                    else
                        num_wr_err_responses <= num_wr_err_responses + 1;
                    end if;
                end if;
            end if;

            -- Test that read responses match the memory contents
            if (resp_ready = '1' and resp_valid = '1' and resp_rd = '1') then

                addr := to_integer(unsigned(rd_addr_array(rd_addr_array_rd_ptr)(31 downto 2))); -- Recall the correct read address
                rd_addr_array_rd_ptr <= rd_addr_array_rd_ptr + 1;                               -- Increment the pointer

                -- Check the read data is as expected (if there was a Wishbone error, then the data does not need to match)
                if (resp_err = '0') then
                    report "Comparing expected read data (" & to_hstring(ref_mem(addr)) & ") with actual read data (" & to_hstring(resp_rd_data) & "), at address: " & integer'image(addr);
                    assert (resp_rd_data = ref_mem(addr)) report "Read response data (" & to_hstring(resp_rd_data) & ") did not match expected (" & to_hstring(ref_mem(addr)) & ") at RAM index: " & integer'image(addr) severity warning;
                    if (not (resp_rd_data = ref_mem(addr))) then
                        num_mismatches <= num_mismatches + 1;
                    end if;
                end if;
            end if;

            -- Reset counts
            if (rst = '1') then
                num_responses        <= 0;
                num_rd_responses     <= 0;
                num_wr_responses     <= 0;
                num_err_responses    <= 0;
                num_rd_err_responses <= 0;
                num_wr_err_responses <= 0;
                num_mismatches       <= 0;
            end if;
        end if;
    end process;

    -----------------------------
    -- Monitor debug interface --
    -----------------------------

    tb_dbg_proc : process (clk) is
    begin
        if (rising_edge(clk)) then

            if (dbg_valid = '1') then

                -- Alive
                assert (dbg_msg /= x"00")
                report "[DEBUG-" & to_hstring(C_DEBUG_COMPONENT_WB_MASTER) & "-" & to_hstring(C_DEBUG_INSTANCE_ID) & "] Alive"
                    severity note;

                -- Wishbone bus error
                if (dbg_msg = x"01") then
                    number_wb_errors <= number_wb_errors + 1; -- Increment count
                end if;
                assert (dbg_msg /= x"01")
                report "[DEBUG-" & to_hstring(C_DEBUG_COMPONENT_WB_MASTER) & "-" & to_hstring(C_DEBUG_INSTANCE_ID) & "] Wishbone bus error"
                    severity warning;

                -- Wishbone bus retry
                assert (dbg_msg /= x"02")
                report "[DEBUG-" & to_hstring(C_DEBUG_COMPONENT_WB_MASTER) & "-" & to_hstring(C_DEBUG_INSTANCE_ID) & "] Wishbone bus retry"
                    severity note;

            end if;

            if (rst = '1') then
                number_wb_errors <= 0;
            end if;
        end if;
    end process;

end architecture;
