--------------------------------------------------------------------------------------------------
--                                      ~   nightjar-v   ~                                      --
--------------------------------------------------------------------------------------------------
-- Filename:    wb_mem.vhd
-- Author:      Will Arden
-- Date:        3rd October 2026
-- Brief:       Wishbone memory element for simulation.
-- Description: This is a simulation component which acts as an external memory interface.
-- Remarks:     
--------------------------------------------------------------------------------------------------
--------------------------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;
use std.textio.all;

entity wb_mem is
    generic (
        G_MEM_INIT_PATH     : string                 := "";
        G_MEM_DEPTH         : natural                := 0; -- In words; when 0, the full address range is used
        G_ADDR_WIDTH        : positive               := 32;
        G_DATA_WIDTH        : positive               := 32;
        G_BASE_LATENCY      : positive               := 3;
        G_PENALTY_LATENCY   : positive               := 50;
        G_PENALTY_PROB_X100 : natural range 0 to 100 := 20;
        G_ERR_PROB_X100     : natural range 0 to 100 := 10;
        G_RTY_PROB_X100     : natural range 0 to 100 := 10;
        G_RANDOM_SEED_A     : integer                := 4826;
        G_RANDOM_SEED_B     : integer                := 9814
    );
    port (
        clk : in std_logic;
        rst : in std_logic;

        wb_cyc_i : in std_logic;
        wb_stb_i : in std_logic;
        wb_we_i  : in std_logic;
        wb_adr_i : in std_logic_vector(G_ADDR_WIDTH - 1 downto 0);
        wb_sel_i : in std_logic_vector(((G_DATA_WIDTH + 7) / 8) - 1 downto 0);
        wb_dat_i : in std_logic_vector(G_DATA_WIDTH - 1 downto 0);
        wb_ack_o : out std_logic;
        wb_err_o : out std_logic;
        wb_rty_o : out std_logic;
        wb_dat_o : out std_logic_vector(G_DATA_WIDTH - 1 downto 0)
    );
end entity;

architecture behav of wb_mem is

    -- Function which returns the memory depth (words)
    function F_GET_MEM_DEPTH return natural is
    begin
        if (G_MEM_DEPTH = 0) then
            return (2 ** G_ADDR_WIDTH);
        end if;
        return G_MEM_DEPTH;
    end function;

    -- Function which returns a random latency
    function F_GET_LATENCY (r : real) return natural is
        variable v_latency        : natural range 0 to (G_BASE_LATENCY + G_PENALTY_LATENCY) := G_BASE_LATENCY;
    begin
        if ((real(100) * r) < real(G_PENALTY_PROB_X100)) then
            v_latency := v_latency + G_PENALTY_LATENCY;
        end if;
        return v_latency;
    end function;

    -- Function which returns true if there is a random error
    function F_IS_ERROR (r : real) return boolean is
    begin
        if ((real(100) * r) < real(G_ERR_PROB_X100)) then
            return true;
        end if;
        return false;
    end function;

    -- Function which returns true if there is a random retry
    function F_IS_RTY (r : real) return boolean is
        variable v_percent   : real;
    begin
        v_percent := real(100) * r;
        if (v_percent >= real(G_ERR_PROB_X100) and v_percent < real(G_ERR_PROB_X100 + G_RTY_PROB_X100)) then
            return true;
        end if;
        return false;
    end function;

    -- Declare memory
    type ram_t is array (0 to F_GET_MEM_DEPTH - 1) of std_logic_vector(31 downto 0);
    signal ram : ram_t;

    -- Procedure to return the initialised memory
    procedure F_GET_INIT_MEMORY(ram_out : out ram_t) is
        file f                              : text;
        variable line                       : line;
        variable addr                       : integer := 0;
        variable comma                      : character;
        variable data                       : std_logic_vector(31 downto 0);
        variable idx                        : natural := 0;
    begin

        -- If no path is provided, skip this procedure
        if (G_MEM_INIT_PATH = "") then
            return;
        end if;

        file_open(f, G_MEM_INIT_PATH, read_mode); -- Open the file
        READLINE(f, line);                        -- Skip header

        while not endfile(f) loop
            READLINE(f, line);
            READ(line, addr);
            READ(line, comma);
            READ(line, data);

            ram_out(idx) := data;
            idx          := idx + 1;
        end loop;
    end procedure;

    -- State machine to model behaviour
    type state_t is (IDLE, WR_IN_PROG, RD_IN_PROG, ACK, FSM_ERROR);
    signal state      : state_t := IDLE;
    signal next_state : state_t;

    -- Declare signals to model responses
    signal timer  : natural range 0 to (G_BASE_LATENCY + G_PENALTY_LATENCY - 1) := 0;
    signal rand_a : real;
    signal rand_b : real;

begin

    -- Process to initialise the memory
    init_proc : process is
        variable v_ram : ram_t;
    begin
        F_GET_INIT_MEMORY(ram_out => v_ram);
        ram <= v_ram;
        wait;
    end process;

    -- Randomness engine
    random_proc : process (clk) is
        variable seed_a : natural := G_RANDOM_SEED_A;
        variable seed_b : natural := G_RANDOM_SEED_B;
        variable r      : real;
    begin
        if (rising_edge(clk)) then
            uniform(seed_a, seed_b, r);
            rand_a <= r;
            uniform(seed_a, seed_b, r);
            rand_b <= r;
        end if;
    end process;

    -- Combinational process to determine the next state
    next_state_proc : process (state, wb_cyc_i, wb_stb_i, wb_we_i, timer) is
    begin
        case (state) is

            when IDLE =>
                if (wb_cyc_i = '1' and wb_stb_i = '1') then
                    if (wb_we_i = '1') then
                        next_state <= WR_IN_PROG;
                    else
                        next_state <= RD_IN_PROG;
                    end if;
                end if;

            when WR_IN_PROG =>
                if (timer = 0) then
                    next_state <= ACK;
                end if;

            when RD_IN_PROG =>
                if (timer = 0) then
                    next_state <= ACK;
                end if;

            when ACK =>
                if (wb_cyc_i = '1' and wb_stb_i = '1') then
                    if (wb_we_i = '1') then
                        next_state <= WR_IN_PROG;
                    else
                        next_state <= RD_IN_PROG;
                    end if;
                else
                    next_state <= IDLE;
                end if;

            when FSM_ERROR =>
                next_state <= IDLE;

            when others =>
                next_state <= FSM_ERROR;
        end case;
    end process;

    -- Process to advance the state
    adv_state_proc : process (clk) is
    begin
        if (rising_edge(clk)) then
            state <= next_state;
            if (rst = '1') then
                state <= IDLE;
            end if;
        end if;
    end process;

    -- Process to control the timer
    timer_proc : process (clk) is
    begin
        if (rising_edge(clk)) then

            -- Set the timer when transitioning to a read/write operation
            if ((next_state = RD_IN_PROG or next_state = WR_IN_PROG) and state /= next_state) then
                timer <= F_GET_LATENCY(rand_a) - 1;

                -- While in these states, the timer should decrement until it reaches zero
            else
                if ((state = RD_IN_PROG or state = WR_IN_PROG) and timer > 0) then
                    timer <= timer - 1;
                end if;
            end if;
            if (rst = '1') then
                timer <= F_GET_LATENCY(rand_a) - 1;
            end if;
        end if;
    end process;

    -- Process to control reading and writing from/to the memory
    mem_proc : process (clk) is
        variable v_err  : boolean;
        variable v_rty  : boolean;
        variable v_ack  : boolean;
        variable v_addr : natural range 0 to (F_GET_MEM_DEPTH - 1);
    begin
        if (rising_edge(clk)) then
            wb_ack_o <= '0';
            wb_err_o <= '0';
            wb_rty_o <= '0';

            -- Act on the last clock cycle of the _IN_PROG state
            if ((state = RD_IN_PROG or state = WR_IN_PROG) and timer = 1) then
                v_err := F_IS_ERROR(rand_b);
                v_rty := F_IS_RTY(rand_b);
                v_ack := (not F_IS_ERROR(rand_b)) and (not F_IS_RTY(rand_b));
                assert ((v_err xor v_rty xor v_ack) and not (v_err and v_rty and v_ack)) report "ERR, RTY and ACK must be mutually-exclusive." severity failure;

                -- ACK (success)
                if (v_ack) then
                    wb_ack_o <= '1';
                    v_addr := to_integer(unsigned(wb_adr_i(wb_adr_i'high downto 2))); -- LSBs are ignored to ensure byte-aligned accesses

                    if (wb_we_i = '1') then
                        ram(v_addr) <= wb_dat_i; -- Write
                    else
                        wb_dat_o <= ram(v_addr); -- Read
                    end if;
                end if;

                -- ERR (failure)
                if (v_err) then
                    wb_err_o <= '1';
                end if;

                -- RTY (failure - retry)
                if (v_rty) then
                    wb_rty_o <= '1';
                end if;
            end if;
        end if;
    end process;

end architecture;