library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;
use std.textio.all;

library work;
use work.common_pkg.all;

entity imem is
    generic (
        G_IMEM_DEPTH           : positive               := 256;
        G_MEM_INIT_PATH        : string                 := "";
        G_BASE_RESPONSE_CYC    : natural                := 2;  -- Normal latency in clock cycles
        G_PENALTY_RESPONSE_CYC : natural                := 20; -- Number of clock cycles' latency added during a penalty
        G_PENALTY_PROB         : natural range 0 to 100 := 10; -- % chance for a penalty to occur
        G_RANDOM_SEED_A        : integer                := 4826;
        G_RANDOM_SEED_B        : integer                := 9814
    );
    port (

        clk : in std_logic;

        -- Wishbone interface
        wb_imem_addr : in std_logic_vector(31 downto 0);
        wb_imem_data : out std_logic_vector(31 downto 0);
        wb_imem_stb  : in std_logic;  -- STB_O
        wb_imem_ack  : out std_logic; -- ACK_I
        wb_imem_cyc  : in std_logic   -- CYC_O

    );
end entity;

architecture sim of imem is

    -- Declare memory
    type ram_t is array (0 to G_IMEM_DEPTH - 1) of std_logic_vector(31 downto 0);
    signal ram : ram_t;

    -- Procedure to return the initialised memory
    procedure F_GET_INIT_MEMORY(ram_out : out ram_t) is
        file f                              : text open read_mode is G_MEM_INIT_PATH;
        variable line                       : line;
        variable addr                       : integer := 0;
        variable comma                      : character;
        variable data                       : std_logic_vector(31 downto 0);
        variable idx                        : natural := 0;
    begin
        READLINE(f, line); -- Skip header

        while not endfile(f) loop
            READLINE(f, line);
            READ(line, addr);
            READ(line, comma);
            READ(line, data);

            ram_out(idx) := data;
            idx          := idx + 1;
        end loop;
    end procedure;

    -- Simple state machine to model behaviour
    type state_t is (IDLE, WORKING, ACK, ERROR);
    signal state      : state_t := IDLE;
    signal next_state : state_t;

    -- Declare a timer to model the response time
    signal timer : natural range 0 to (G_BASE_RESPONSE_CYC + G_PENALTY_RESPONSE_CYC - 1) := 0;

    -- Address register
    signal addr : std_logic_vector(31 downto 0) := (others => '0');

begin

    -- Process to initialise the memory
    init_proc : process is
        variable v_ram : ram_t;
    begin
        F_GET_INIT_MEMORY(ram_out => v_ram);
        ram <= v_ram;
        wait;
    end process;

    -- Combinational process to determine the next state
    next_state_proc : process (state, wb_imem_stb, timer) is
    begin
        next_state <= state;
        case state is

            when IDLE =>
                if (wb_imem_stb = '1') then
                    next_state <= WORKING;
                end if;

            when WORKING =>
                if (timer = 1) then
                    next_state <= ACK;
                end if;

            when ACK =>
                if (wb_imem_stb = '1') then
                    next_state <= WORKING;
                else
                    next_state <= IDLE;
                end if;

            when others => next_state <= ERROR;
        end case;
    end process;

    -- Process to drive the outputs based on the current state
    output_proc : process (state) is
    begin

        -- Drive ACK and DATA
        if (state = ACK) then
            wb_imem_ack <= '1';

            -- Each line of the CSV is a single index of the RAM signal
            -- Since instructions are byte-aligned, you must divide the address by 4 to get its index in the RAM signal
            wb_imem_data <= ram(to_integer(unsigned(addr(31 downto 2))));
        else
            wb_imem_ack  <= '0';
            wb_imem_data <= (others => 'U');
        end if;
    end process;

    -- Misc. sequential process
    misc_seq_proc : process (clk) is
        variable seed_a : integer := G_RANDOM_SEED_A;
        variable seed_b : integer := G_RANDOM_SEED_B;

        -- Function to return the number of cycles required for each fetch request
        impure function F_GET_RESPONSE_TIME return natural is
            variable r : real;
        begin
            uniform(seed_a, seed_b, r); -- Generate a random decimal

            if (r < (real(G_PENALTY_PROB) / real(100))) then -- Penalty
                return G_BASE_RESPONSE_CYC + G_PENALTY_RESPONSE_CYC;
            else -- No penalty
                return G_BASE_RESPONSE_CYC;
            end if;
        end function;
    begin
        if (rising_edge(clk)) then

            -- Advance the state
            state <= next_state;

            -- Register the requested address
            if (state /= WORKING and next_state = WORKING) then
                addr <= wb_imem_addr;
            end if;

            -- Set the timer when an instruction fetch is requested
            if (state /= WORKING and next_state = WORKING) then
                timer <= F_GET_RESPONSE_TIME - 1;
            end if;

            -- Decrement the timer if it is active
            if (timer > 0) then
                timer <= timer - 1;
            end if;
        end if;
    end process;

end architecture;
