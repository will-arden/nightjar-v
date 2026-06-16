library vunit_lib;
context vunit_lib.vunit_context;

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;
use std.textio.all;

use work.common_pkg.all;

entity tb_sync_fifo is
  generic (runner_cfg : string);
end entity tb_sync_fifo;

architecture tb of tb_sync_fifo is

  constant C_CLK_PERIOD           : time   := 10 ns;
  constant C_SIM_TICKS : natural := 500;
  constant C_INPUT_CSV_PATH       : string := "test_artefacts/sync_fifo_inputs.csv";
  constant C_OUTPUT_CSV_PATH      : string := "test_artefacts/sync_fifo_outputs.csv";
  constant C_WR_STALL_PROBABILITY : real   := 0.3;
  constant C_RD_STALL_PROB        : real   := 0.3;

  constant G_WIDTH : positive := 32;
  constant G_DEPTH : positive := 512;

  -- Test signals
  signal clk          : std_logic := '0';
  signal rst          : std_logic := '1';
  signal wr_valid     : std_logic;
  signal wr_ready     : std_logic;
  signal wr_data      : std_logic_vector(G_WIDTH - 1 downto 0);
  signal rd_valid     : std_logic;
  signal rd_ready     : std_logic;
  signal rd_data      : std_logic_vector(G_WIDTH - 1 downto 0);
  signal level        : std_logic_vector(log2(G_DEPTH) - 1 downto 0);
  signal full         : std_logic;
  signal almost_full  : std_logic;
  signal empty        : std_logic;
  signal almost_empty : std_logic;

begin

  -- Instantiate DUT
  sync_fifo_inst : entity work.sync_fifo
    generic map(
      G_WIDTH => G_WIDTH,
      G_DEPTH => G_DEPTH
    )
    port map
    (
      clk          => clk,
      rst          => rst,
      wr_valid     => wr_valid,
      wr_ready     => wr_ready,
      wr_data      => wr_data,
      rd_valid     => rd_valid,
      rd_ready     => rd_ready,
      rd_data      => rd_data,
      level        => level,
      full         => full,
      almost_full  => almost_full,
      empty        => empty,
      almost_empty => almost_empty
    );

  -- Generate clock and reset
  clk <= not clk after C_CLK_PERIOD;
  rst <= '1', '0' after 10 * C_CLK_PERIOD;

  -- Process to write to the FIFO using the input CSV file
  wr_proc : process is
    file f       : text open READ_MODE is C_INPUT_CSV_PATH;
    variable l   : line;
    variable hex : unsigned(G_WIDTH - 1 downto 0) := (others => '0');

    -- Variables for random stall events
    variable seed1 : positive := 12345;
    variable seed2 : positive := 30914;
    variable r     : real;
  begin
    wr_valid <= '0';
    wait until falling_edge(rst);

    while not endfile(f) loop

      READLINE(f, l);
      READ(l, hex);

      -- Stimulate the DUT
      wr_data <= std_logic_vector(hex);

      while true loop

        -- Random stall event (controlled by C_WR_STALL_PROBABILITY)
        UNIFORM(seed1, seed2, r);
        if (r < C_WR_STALL_PROBABILITY) then
          wr_valid <= '0';
        else
          wr_valid <= '1';
        end if;

        wait until rising_edge(clk);

        -- Only proceed once a valid handshake at the write interface occurs
        if (wr_valid = '1' and wr_ready = '1') then
          exit;
        end if;
      end loop;
    end loop;
  end process wr_proc;

  -- Process to read into a CSV file
  rd_proc : process is
    file f     : text open WRITE_MODE is C_OUTPUT_CSV_PATH;
    variable l : line;

    -- Variables for random stall events
    variable seed1 : positive := 37291;
    variable seed2 : positive := 567301;
    variable r     : real;
  begin
    rd_ready <= '0';
    wait until falling_edge(rst);

    while true loop

      -- Random stall event (controlled by C_RD_STALL_PROBABILITY)
      UNIFORM(seed1, seed2, r);
      if (r < C_RD_STALL_PROB) then
        rd_ready <= '0';
      else
        rd_ready <= '1';
      end if;

      wait until rising_edge(clk);

      -- On a valid read handshake, write to the CSV
      if (rd_ready = '1' and rd_valid = '1') then
        WRITE(l, rd_data);
        WRITELINE(f, l);
      end if;
    end loop;
  end process rd_proc;

  -- VUnit entry
  main : process is
  begin
    test_runner_setup(runner, runner_cfg);
    report "Hello world!";

    wait for C_SIM_TICKS * C_CLK_PERIOD;
    test_runner_cleanup(runner);
  end process main;
end architecture tb;