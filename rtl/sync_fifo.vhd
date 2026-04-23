library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.common_pkg.all;

entity sync_fifo is
  generic (
    G_WIDTH   : positive := 32;
    G_DEPTH   : positive := 64;
    G_REG_OUT : natural  := 0 -- The number of register stages on the read output
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

  -- Read and write pointers
  signal rd_ptr : unsigned(log2(G_DEPTH) - 1 downto 0) := (others => '0');
  signal wr_ptr : unsigned(log2(G_DEPTH) - 1 downto 0) := (others => '0');

  -- Declare read output pipeline
  type pipe_t is array (natural range <>) of std_logic_vector(G_WIDTH - 1 downto 0);
  signal pipe : pipe_t (0 to G_REG_OUT) := (others => (others => '0'));

  -- Misc. internal signals
  signal wr_ready_i : std_logic;
  signal rd_valid_i : std_logic;
  signal full_i     : std_logic;
  signal empty_i    : std_logic;

  signal wr_handshake : std_logic;

begin

  -- Connect internal signals to outputs
  wr_ready <= wr_ready_i;
  rd_valid <= rd_valid_i;
  full     <= full_i;

  wr_handshake <= wr_ready_i and wr_valid;

  -- Instantiate RAM
  generic_ram_inst : entity work.generic_ram
    generic map(
      G_WIDTH    => G_WIDTH,
      G_DEPTH    => G_DEPTH,
      G_RAM_TYPE => "sdp"
    )
    port map
    (
      a_clk     => clk,
      a_port_en => '1',
      a_addr    => std_logic_vector(wr_ptr),
      a_rd_data => open,
      a_rd_en   => '1',
      a_wr_data => wr_data,
      a_wr_en   => wr_handshake,
      a_wr_byte_en => (others => '1'),

      b_clk     => clk,
      b_port_en => '1',
      b_addr    => std_logic_vector(rd_ptr),
      b_rd_data => rd_data,
      b_rd_en   => '1',
      b_wr_data => (others => '0'),
      b_wr_en   => '0',
      b_wr_byte_en => (others => '0')
    );

  -- Read output logic
  --------------------------------------------------------
  --------------------------------------------------------

  -- Combinationally read from the memory
  pipe(0) <= mem(to_integer(unsigned(rd_ptr)));

  -- Connect each output pipeline stage
  gen_reg_out : for i in 1 to (G_REG_OUT) generate
    sync_reg_out_proc : process (clk) is
    begin
      if (rising_edge(clk)) then
        pipe(i) <= pipe(i - 1);

        -- Initialise on reset
        if (rst = '1') then
          pipe(i) <= (others => '0');
        end if;
      end if;
    end process sync_reg_out_proc;
  end generate gen_reg_out;

  -- Drive the output from the final pipeline stage
  rd_data <= pipe(G_REG_OUT);

  -- Combinational status assignments
  -- TODO: Make these registered outputs by including their logic in the synchronous process
  --------------------------------------------------------
  --------------------------------------------------------

  -- The FIFO is ready as long as it is not full
  wr_ready_i <= '1' when (full_i = '0') else
    '0';

  -- The FIFO is outputting valid read data unless it is empty
  rd_valid_i <= '1' when (empty_i = '0') else
    '0';

  -- The FIFO is empty when the level is 0
  empty_i <= '1' when (to_integer(unsigned(level)) = 0) else
    '0';

  -- The FIFO is full when the level is at its maximum capacity
  full_i <= '1' when (to_integer(unsigned(level)) = G_DEPTH - 1) else
    '0';

  -- Synchronous logic
  --------------------------------------------------------
  --------------------------------------------------------

  sync_fifo_proc : process (clk) is
    variable v_read  : boolean := false;
    variable v_write : boolean := false;
  begin
    if (rising_edge(clk)) then
      v_read  := false;
      v_write := false;

      -- Reading occurs on a valid handshake at the read interface
      if (rd_valid_i = '1' and rd_ready = '1') then
        v_read := true;
      end if;

      -- Writing occurs on a valid handshake at the write interface
      if (wr_valid = '1' and wr_ready_i = '1') then
        v_write := true;
      end if;

      -- Write
      if (v_write) then
        mem(to_integer(wr_ptr)) <= wr_data;
        wr_ptr                  <= wr_ptr + 1;
      end if;

      -- Read
      if (v_read) then
        rd_ptr <= rd_ptr + 1;
      end if;

      -- Update the level
      level <= std_logic_vector(unsigned(level) + to_integer(v_write) - to_integer(v_read));

      -- Initialise signals on reset
      if (rst = '1') then
        wr_ptr <= (others => '0');
        rd_ptr <= (others => '0');
        level  <= (others => '0');
      end if;

    end if;
  end process sync_fifo_proc;

end architecture rtl;
