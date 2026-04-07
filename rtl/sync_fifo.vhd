library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.common_pkg.all;

entity sync_fifo is
  generic (
    G_WIDTH : positive := 32;
    G_DEPTH : positive := 64
  );
  port (
    clk : in std_logic;
    rst : in std_logic;

    -- Write interface
    wr_valid : in std_logic;
    wr_ready : out std_logic;
    wr_data  : in std_logic_vector(G_WIDTH - 1 downto 0);

    -- Read interface
    rd_valid : out std_logic;
    rd_ready : in std_logic;
    rd_data  : out std_logic_vector(G_WIDTH - 1 downto 0);

    -- FIFO status
    level        : out std_logic_vector(log2(integer(real(G_DEPTH))) - 1 downto 0);
    full         : out std_logic;
    almost_full  : out std_logic;
    empty        : out std_logic;
    almost_empty : out std_logic
  );
end entity sync_fifo;

architecture rtl of sync_fifo is

  -- Declare FIFO memory
  type mem_t is array (0 to (G_DEPTH - 1)) of std_logic_vector(G_WIDTH - 1 downto 0);
  signal mem : mem_t := (others => (others => '0'));

  -- Misc. internal signals
  signal wr_ready_i : std_logic;
  signal rd_valid_i : std_logic;
  signal full_i     : std_logic;
  signal empty_i    : std_logic;

begin

  -- Connect internal signals to outputs
  wr_ready <= wr_ready_i;
  rd_valid <= rd_valid_i;
  full     <= full_i;

  wr_ready_i <= '1' when (empty_i = '0') else
    '0';

  rd_valid_i <= '1' when (full_i = '0') else
    '0';

  empty_i <= '0';
  full_i  <= '0';

  -- Write process
  wr_proc : process (clk) is
    variable wr_ptr : natural := 0;
    variable rd_ptr : natural := 0;
  begin
    if (rising_edge(clk)) then

      -- Write to the FIFO on a valid handshake and increment the write pointer
      if (wr_valid = '1' and wr_ready_i = '1') then
        mem(wr_ptr) <= wr_data;
        wr_ptr := wr_ptr + 1;
      end if;

      -- Read from the FIFO on a valid handshake
      if (rd_valid_i = '1' and rd_ready = '1') then
        rd_ptr := rd_ptr + 1;
      end if;

      rd_data <= mem(rd_ptr);

      -- Initialise pointers on reset
      if (rst = '1') then
        wr_ptr := 0;
        rd_ptr := 0;
      end if;

    end if;
  end process wr_proc;

end architecture rtl;
