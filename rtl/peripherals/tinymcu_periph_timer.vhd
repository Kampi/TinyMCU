--------------------------------------------------------------------------------
-- SPDX-License-Identifier: GPL-3.0-or-later
--
-- Company:
-- Engineer: Daniel Kampert
--
-- Create Date: 14.06.2026
-- Design Name: TinyMCU
-- Module Name: tinymcu_periph_timer - tinymcu_periph_timer_rtl
-- Project Name: TinyMCU
-- Description:
--  TIMER_BASE..TIMER_END (0x0400_0100..0x0400_01FF)
--
--  Word offset     Name            R/W     Meaning
--  0               CONFIG        RW        Clock select register.
--                                              Bit                     Description
--                                              3:0                     Clock prescaler
--                                                                          0000        OFF (reg_counter does not tick)
--                                                                          0001        DIV1    (clk_i)
--                                                                          0010        DIV2    (clk_i/2)
--                                                                          0011        DIV4    (clk_i/4)
--                                                                          0100        DIV8    (clk_i/8)
--                                                                          0101        DIV64   (clk_i/64)
--                                                                          0110        DIV256  (clk_i/256)
--                                                                          0111        DIV1024 (clk_i/1024)
--                                                                          1000-1111   Reserved, behaves like OFF
--                                              31:4                    Unused.
--  1               INT_CONFIG    RW        Interrupt enable register.
--                                              Bit                     Description
--                                              0                       Compare interrupt enable.
--                                              31:1                    Unused.
--  2               INT_STATUS    RW        Interrupt status register.
--                                              Bit                     Description
--                                              0                       Compare interrupt flag. Write to '0' to clear it.
--                                              31:1                    Unused.
--  3               COUNTER       RW        Free-running counter, auto-increments every prescaled tick;
--                                          also directly writable/readable by software.
--                                              Bit                     Description
--                                              1:0                    Counter value.
--  4               COMPARE       RW        Compare value; not consumed by hardware yet (no match/
--                                          reload/interrupt logic), plain read/write storage for now.
--                                              Bit                     Description
--                                              31:0                    Compare value.
--
-- Dependencies:
--   tinymcu_pkg
--
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library tinymcu;
use tinymcu.tinymcu_pkg.all;

entity tinymcu_periph_timer is
    port (
        -- Global control
        clk_i       : in  std_ulogic;
        rst_i       : in  std_ulogic;

        -- Interrupt output
        irq_o       : out std_ulogic;

        -- Peripheral Decoder-facing side
        timer_req_i : in  bus_req_t;
        timer_rsp_o : out bus_rsp_t
    );
end entity tinymcu_periph_timer;

architecture tinymcu_periph_timer_rtl of tinymcu_periph_timer is

    constant TIMER_REG_CONFIG       : integer := 0;
    constant TIMER_REG_INT_CONFIG   : integer := 1;
    constant TIMER_REG_INT_STATUS   : integer := 2;
    constant TIMER_REG_COUNTER      : integer := 3;
    constant TIMER_REG_COMPARE      : integer := 4;

    constant TIMER_BIT_COMP_INT     : integer := 0;

    signal reg_config       : word_t    := (others => '0');
    signal reg_int_config   : word_t    := (others => '0');
    signal reg_int_status   : word_t    := (others => '0');
    signal reg_counter      : word_t    := (others => '0');
    signal reg_compare      : word_t    := (others => '0');

    signal rdata            : word_t;

    signal word_offset      : integer range 0 to 63;

    signal clk_prescaled    : std_ulogic := '0';

    -- Maps the clock prescaler to which bit of the prescaler's free-running counter selects the divide
    -- period (tapping bit i and pulsing on its rising edge gives one tick every 2**(i+1)
    -- cycles, see "Clock prescaler" below).
    --   clksel - reg_config(3 downto 0), the CONFIG register's CLKSEL field (see the header
    --            table above).
    -- Returns: the free-running counter's bit index to tap; the sentinel -1 for DIV1 (tick
    -- every cycle, no bit to tap); the sentinel -2 for OFF (never tick covers CLKSEL "0000"
    -- and every reserved "1000".."1111" code, all falling into "when others" below since none
    -- of them are listed explicitly).
    function clksel_reg(clksel : std_ulogic_vector(3 downto 0)) return integer is
    begin
        case clksel is
            when "0001" => return -1;  -- DIV1
            when "0010" => return 0;   -- DIV2
            when "0011" => return 1;   -- DIV4
            when "0100" => return 2;   -- DIV8
            when "0101" => return 5;   -- DIV64
            when "0110" => return 7;   -- DIV256
            when "0111" => return 9;   -- DIV1024
            when others => return -2;  -- OFF, or reserved
        end case;
    end function;

begin

    -- 256 B window, 64 possible word offsets
    word_offset <= to_integer(unsigned(timer_req_i.addr(7 downto 2)));

    ----------------------------------------------------------------------
    -- Register writes (CONFIG, COMPARE)
    ----------------------------------------------------------------------
    process (clk_i)
    begin
        if rising_edge(clk_i) then
            if rst_i = '1' then
                reg_config  <= (others => '0');
                reg_compare <= (others => '0');
            elsif timer_req_i.stb = '1' and timer_req_i.we = '1' then
                case word_offset is
                    when TIMER_REG_CONFIG       => reg_config       <= byte_merge(reg_config, timer_req_i.data, timer_req_i.ben);
                    when TIMER_REG_COMPARE      => reg_compare      <= byte_merge(reg_compare, timer_req_i.data, timer_req_i.ben);
                    when TIMER_REG_INT_CONFIG   => reg_int_config   <= byte_merge(reg_int_config, timer_req_i.data, timer_req_i.ben);
                    when others                 => null;
                end case;
            end if;
        end if;
    end process;

    ----------------------------------------------------------------------
    -- Register writes (COUNTER)
    ----------------------------------------------------------------------
    process (clk_i)
    begin
        if rising_edge(clk_i) then
            if rst_i = '1' then
                reg_counter <= (others => '0');
            elsif timer_req_i.stb = '1' and timer_req_i.we = '1' and word_offset = TIMER_REG_COUNTER then
                reg_counter <= byte_merge(reg_counter, timer_req_i.data, timer_req_i.ben);
            elsif clk_prescaled = '1' then
                reg_counter <= std_ulogic_vector(unsigned(reg_counter) + 1);
            end if;
        end if;
    end process;

    ----------------------------------------------------------------------
    -- Register reads
    ----------------------------------------------------------------------
    process (word_offset, reg_config, reg_counter, reg_compare, reg_int_config, reg_int_status)
    begin
        case word_offset is
            when TIMER_REG_CONFIG       => rdata <= reg_config;
            when TIMER_REG_COUNTER      => rdata <= reg_counter;
            when TIMER_REG_COMPARE      => rdata <= reg_compare;
            when TIMER_REG_INT_CONFIG   => rdata <= reg_int_config;
            when TIMER_REG_INT_status   => rdata <= reg_int_status;
            when others                 => rdata <= (others => '0');
        end case;
    end process;

    ----------------------------------------------------------------------
    -- Clock prescaler
    ----------------------------------------------------------------------
    process (clk_i)
        variable free_run_cnt   : unsigned(9 downto 0) := (others => '0');
        variable tap_bit        : integer;
        variable tap            : std_ulogic_vector(1 downto 0) := (others => '0');
    begin
        if rising_edge(clk_i) then
            if rst_i = '1' then
                free_run_cnt    := (others => '0');
                tap             := (others => '0');
                clk_prescaled   <= '0';
            else
                free_run_cnt := free_run_cnt + 1;
                tap_bit := clksel_reg(reg_config(3 downto 0));

                -- No prescaler configured
                if tap_bit = -1 then
                    clk_prescaled <= '1';
                    tap(1) := '0';
                -- Clock is off
                elsif tap_bit = -2 then
                    clk_prescaled <= '0';
                    tap(1) := '0';
                -- Rising edge detection
                else
                    tap(0) := free_run_cnt(tap_bit);
                    clk_prescaled <= tap(0) and not tap(1);
                    tap(1) := tap(0);
                end if;
            end if;
        end if;
    end process;

    ----------------------------------------------------------------------
    -- Interrupt flags generation
    ----------------------------------------------------------------------
    process (clk_i)
        variable compare_match : std_ulogic_vector(1 downto 0);
    begin
        if rising_edge(clk_i) then
            if rst_i = '1' then
                reg_int_status  <= (others => '0');
                compare_match   := (others => '0');
            else
                compare_match(0) := '1' when unsigned(reg_counter) = unsigned(reg_compare) else '0';

                -- Software clear (write bit to '0')
                if timer_req_i.stb = '1' and timer_req_i.we = '1' and word_offset = TIMER_REG_INT_STATUS then
                    reg_int_status <= byte_merge(reg_int_status, timer_req_i.data, timer_req_i.ben);
                -- Rising edge detection
                elsif (compare_match(0) and not compare_match(1)) = '1' and reg_int_config(TIMER_BIT_COMP_INT) = '1' then
                    reg_int_status(TIMER_BIT_COMP_INT) <= '1';
                end if;

                compare_match(1) := compare_match(0);
            end if;
        end if;
    end process;

    timer_rsp_o.data <= rdata;
    timer_rsp_o.ack  <= timer_req_i.stb;
    timer_rsp_o.err  <= '0';

    irq_o <= reg_int_status(TIMER_BIT_COMP_INT);

end architecture tinymcu_periph_timer_rtl;
