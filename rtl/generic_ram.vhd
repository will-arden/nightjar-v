library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.common_pkg.all;

entity generic_ram is
  generic (
    G_WIDTH      : positive := 32;
    G_DEPTH      : positive := 32;
    G_BYTE_WIDTH : positive := 8;
    G_RAM_TYPE   : string   := "sdp"; -- "basic", "sdp", "tdp"
    G_DUAL_CLK   : boolean  := false;
    G_RAM_STYLE  : string   := "auto"; -- Specifies the synthesis RAM-style attribute
    G_SIM_CHECKS : boolean  := true -- Include logic for simulation-time checks
  );
  port (

    -- Port A
    a_clk        : in std_logic;
    a_port_en    : in std_logic;
    a_addr       : in std_logic_vector(log2(G_WIDTH) - 1 downto 0);
    a_rd_data    : out std_logic_vector(G_WIDTH - 1 downto 0);
    a_rd_en      : in std_logic;
    a_wr_data    : in std_logic_vector(G_WIDTH - 1 downto 0);
    a_wr_en      : in std_logic;
    a_wr_byte_en : in std_logic_vector((G_WIDTH / G_BYTE_WIDTH) - 1 downto 0);

    -- Port B (not used when "G_RAM_TYPE = basic")
    b_clk        : in std_logic;
    b_port_en    : in std_logic;
    b_addr       : in std_logic_vector(log2(G_WIDTH) - 1 downto 0);
    b_rd_data    : out std_logic_vector(G_WIDTH - 1 downto 0);
    b_rd_en      : in std_logic;
    b_wr_data    : in std_logic_vector(G_WIDTH - 1 downto 0);
    b_wr_en      : in std_logic;
    b_wr_byte_en : in std_logic_vector((G_WIDTH / G_BYTE_WIDTH) - 1 downto 0)
  );
end entity;

architecture rtl of generic_ram is

  constant C_NUM_BYTES : positive := ((G_WIDTH + 7) / G_BYTE_WIDTH);

  -- Type definitions
  subtype byte_t is std_logic_vector(G_BYTE_WIDTH - 1 downto 0);
  type word_t is array (0 to C_NUM_BYTES) of byte_t;
  type ram_t is array (0 to G_DEPTH) of word_t;

  -- Function to convert a word_t to a std_logic_vector
  function word_to_slv (word : word_t) return std_logic_vector is
    variable slv               : std_logic_vector((G_BYTE_WIDTH * C_NUM_BYTES) - 1 downto 0);
  begin
    for byte in 0 to (C_NUM_BYTES - 1) loop
      slv(((byte + 1) * G_BYTE_WIDTH) downto (byte * G_BYTE_WIDTH)) := word(byte);
    end loop;
    return slv;
  end function word_to_slv;

  -- Function to convert a std_logic_vector to a word_t
  function slv_to_word (slv : std_logic_vector) return word_t is
    variable padded           : std_logic_vector((G_BYTE_WIDTH * C_NUM_BYTES) - 1 downto 0);
    variable word             : word_t;
  begin
    padded := pad(slv, padded'length);
    for byte in 0 to (C_NUM_BYTES - 1) loop
      word(byte) := padded(((byte + 1) * G_BYTE_WIDTH) downto (byte * G_BYTE_WIDTH));
    end loop;
    return word;
  end function slv_to_word;

  -- Declare the RAM as an array of words, which is an array of bytes
  signal ram : ram_t := (others => (others => (others => '0')));

  signal b_clk_sw : std_logic;

  signal a_ram_out : std_logic_vector((G_BYTE_WIDTH * C_NUM_BYTES) - 1 downto 0) := (others => '0');
  signal b_ram_out : std_logic_vector((G_BYTE_WIDTH * C_NUM_BYTES) - 1 downto 0) := (others => '0');

begin

  -- Select Port B clock depending on G_DUAL_CLK
  gen_dual_clk : if (G_DUAL_CLK) generate
    b_clk_sw <= b_clk;
  end generate gen_dual_clk;
  gen_no_dual_clk : if (not G_DUAL_CLK) generate
    b_clk_sw <= a_clk;
  end generate gen_no_dual_clk;

  -- Drive the RAM outputs
  a_rd_data <= a_ram_out(a_rd_data'length - 1 downto 0);
  b_rd_data <= b_ram_out(b_rd_data'length - 1 downto 0);

  gen_sdp_ram : if (G_RAM_TYPE = "sdp") generate

    -- (Port A) Write interface
    port_a_proc : process (a_clk) is
    begin
      if (rising_edge(a_clk)) then
        if (a_port_en = '1') then
          if (a_wr_en = '1') then
            for byte in 0 to (C_NUM_BYTES - 1) loop
              if (a_wr_byte_en(byte) = '1') then
                ram(to_integer(unsigned(a_addr))) <= slv_to_word(a_wr_data);
              end if;
            end loop;
          end if;
        end if;
      end if;
    end process port_a_proc;

    -- (Port B) Read interface
    port_b_proc : process (b_clk_sw) is
    begin
      if (rising_edge(b_clk_sw)) then
        if (b_port_en = '1') then
          if (b_rd_en = '1') then
            b_ram_out <= word_to_slv(ram(to_integer(unsigned(b_addr))));
          end if;
        end if;
      end if;
    end process port_b_proc;

  end generate gen_sdp_ram;

  -- TODO: simulation checks process which checks for misuse of RAM for the given generics

  -- TODO: basic warnings and checks for generic values

end architecture rtl;
