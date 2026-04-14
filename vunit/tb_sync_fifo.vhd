library vunit_lib;
context vunit_lib.vunit_context;

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.common_pkg.all;

entity tb_sync_fifo is
  generic (runner_cfg : string);
end entity tb_sync_fifo;

architecture tb of tb_sync_fifo is

  constant C_CLK_PERIOD : time := 10 ns;

  constant G_WIDTH : positive := 32;
  constant G_DEPTH : positive := 64;

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

  wr_proc : process (clk) is
    variable num : natural := 0;
  begin
    if (rising_edge(clk)) then
      wr_valid <= '1';
      wr_data  <= std_logic_vector(to_unsigned(num, G_WIDTH));
      rd_ready <= '1';
      num := num + 1;
    end if;
  end process wr_proc;

  -- VUnit entry
  main : process is
  begin
    test_runner_setup(runner, runner_cfg);
    report "Hello world!";

    wait for 100 * C_CLK_PERIOD;
    test_runner_cleanup(runner);
  end process main;
end architecture tb;