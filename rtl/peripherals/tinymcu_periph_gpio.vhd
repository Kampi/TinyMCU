--------------------------------------------------------------------------------
-- SPDX-License-Identifier: GPL-3.0-or-later
--
-- Company:
-- Engineer: Daniel Kampert
--
-- Create Date: 14.06.2026
-- Design Name: TinyMCU
-- Module Name: tinymcu_periph_gpio - tinymcu_periph_gpio_rtl
-- Project Name: TinyMCU
-- Description:
--  GPIO_BASE..GPIO_END (0x0400_0000..0x0400_00FF)
--
--  Word offset     Name            R/W     Meaning
--  0               CONFIG          RW      Bit 0 and 15:1 defined below; otherwise general-purpose, reserved for future use.
--                                              Bit                     Description
--                                              0                       Global interrupt enable
--                                              15:1                    Global debounce threshold, in clock cycles (0 = disabled)
--  1               DDR             RW      Data direction, per pin:
--                                          1 = output, 0 = input
--  2               PULL_SEL        RW      Pull resistor select, per pin (only meaningful combined with PULL_EN):
--                                          1 = pull-up, 0 = pull-down.
--  3               PULL_EN         RW      Pull resistor enable, per pin:
--                                          1 = the pull configured by PULL_SEL is active, 0 = floating.
--  4               OUT             RW      Output data, per pin: drives the pin when DDR = 1; has no effect on a pin configured as input.
--  5               IN              R       Input data, per pin: the pin's actual resolved logic level (normalized to '1'/'0' via to_x01, see below),
--                                          regardless of DDR (also readable while DDR = 1, to read back what's being driven). Writes are ignored.
--  6               INT_CONFIG      RW      Enable a pin interrupt for the specific GPIO. 1 = enabled, 0 = disabled
--  7               INT_STATUS      RW      Interrupt status for each GPIO. Write to '0' to clear it.
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

entity tinymcu_periph_gpio is
    generic (
        PORT_WIDTH : integer := 32;

        -- Width of the debounce threshold field in CONFIG
        DEBOUNCE_WIDTH : integer := 15
    );
    port (
        -- Global control
        clk_i       : in std_ulogic;
        rst_i       : in std_ulogic;

        -- Peripheral Decoder-facing side
        gpio_req_i : in  bus_req_t;
        gpio_rsp_o : out bus_rsp_t;

        -- Interrupt output
        irq_o       : out std_ulogic;

        -- Pad-facing side
        gpio_port   : inout std_logic_vector((PORT_WIDTH - 1) downto 0)
    );
end entity tinymcu_periph_gpio;

architecture tinymcu_periph_gpio_rtl of tinymcu_periph_gpio is

    constant GPIO_REG_CONFIG        : integer := 0;
    constant GPIO_REG_DDR           : integer := 1;
    constant GPIO_REG_PULL_SEL      : integer := 2;
    constant GPIO_REG_PULL_EN       : integer := 3;
    constant GPIO_REG_OUT           : integer := 4;
    constant GPIO_REG_IN            : integer := 5;
    constant GPIO_REG_INT_CONFIG    : integer := 6;
    constant GPIO_REG_INT_STATUS    : integer := 7;

    constant GPIO_BIT_GLOB_INT      : integer := 0;

    constant GPIO_DEBOUNCE_LSB      : integer := 1;
    constant GPIO_DEBOUNCE_MSB      : integer := GPIO_DEBOUNCE_LSB + DEBOUNCE_WIDTH - 1;

    type debounce_cnt_t is array (0 to (PORT_WIDTH - 1)) of unsigned((GPIO_DEBOUNCE_MSB - GPIO_DEBOUNCE_LSB) downto 0);

    signal reg_config       : word_t;
    signal reg_ddr          : word_t    := (others => '1');
    signal reg_pull_sel     : word_t    := (others => '0');
    signal reg_pull_en      : word_t    := (others => '0');
    signal reg_out          : word_t    := (others => '0');
    signal reg_int_config   : word_t    := (others => '0');
    signal reg_int_status   : word_t    := (others => '0');
    signal rdata            : word_t;

    signal debounce_thresh  : unsigned((GPIO_DEBOUNCE_MSB - GPIO_DEBOUNCE_LSB) downto 0);
    signal debounce_cnt     : debounce_cnt_t := (others => (others => '0'));
    signal gpio_raw_x01     : std_ulogic_vector((PORT_WIDTH - 1) downto 0);
    signal gpio_debounced   : std_ulogic_vector((PORT_WIDTH - 1) downto 0) := (others => '0');
    signal gpio_filtered    : std_ulogic_vector((PORT_WIDTH - 1) downto 0);
    signal gpio_port_prev   : std_ulogic_vector((PORT_WIDTH - 1) downto 0)  := (others => '0');

    signal word_offset      : integer range 0 to 63;

begin

    assert GPIO_DEBOUNCE_MSB <= 31
        report "tinymcu_periph_gpio: DEBOUNCE_WIDTH=" & integer'image(DEBOUNCE_WIDTH) &
               " puts the debounce field's MSB at bit " & integer'image(GPIO_DEBOUNCE_MSB) &
               ", which doesn't fit inside CONFIG's 32 bits (bit 0 is reserved for the global interrupt enable)"
        severity failure;

    -- 256 B window, 64 possible word offsets
    word_offset <= to_integer(unsigned(gpio_req_i.addr(7 downto 2)));

    ----------------------------------------------------------------------
    -- Register writes except interrupt flags
    ----------------------------------------------------------------------
    process (clk_i)
    begin
        if rising_edge(clk_i) then
            if rst_i = '1' then
                reg_config   <= (others => '0');
                reg_ddr      <= (others => '0');
                reg_pull_sel <= (others => '0');
                reg_pull_en  <= (others => '0');
                reg_out      <= (others => '0');
            elsif gpio_req_i.stb = '1' and gpio_req_i.we = '1' then
                case word_offset is
                    when GPIO_REG_CONFIG        => reg_config       <= byte_merge(reg_config, gpio_req_i.data, gpio_req_i.ben);
                    when GPIO_REG_DDR           => reg_ddr          <= byte_merge(reg_ddr, gpio_req_i.data, gpio_req_i.ben);
                    when GPIO_REG_PULL_SEL      => reg_pull_sel     <= byte_merge(reg_pull_sel, gpio_req_i.data, gpio_req_i.ben);
                    when GPIO_REG_PULL_EN       => reg_pull_en      <= byte_merge(reg_pull_en, gpio_req_i.data, gpio_req_i.ben);
                    when GPIO_REG_OUT           => reg_out          <= byte_merge(reg_out, gpio_req_i.data, gpio_req_i.ben);
                    when GPIO_REG_INT_CONFIG    => reg_int_config   <= byte_merge(reg_int_config, gpio_req_i.data, gpio_req_i.ben);
                    when others                 => null;
                end case;
            end if;
        end if;
    end process;

    ----------------------------------------------------------------------
    -- Register reads
    ----------------------------------------------------------------------
    process (word_offset, reg_config, reg_ddr, reg_pull_sel, reg_pull_en, reg_out, gpio_port, reg_int_config, reg_int_status)
    begin
        case word_offset is
            when GPIO_REG_CONFIG        => rdata <= reg_config;
            when GPIO_REG_DDR           => rdata <= reg_ddr;
            when GPIO_REG_PULL_SEL      => rdata <= reg_pull_sel;
            when GPIO_REG_PULL_EN       => rdata <= reg_pull_en;
            when GPIO_REG_OUT           => rdata <= reg_out;
            when GPIO_REG_IN            => rdata <= std_ulogic_vector(to_x01(gpio_port));
            when GPIO_REG_INT_CONFIG    => rdata <= reg_int_config;
            when GPIO_REG_INT_STATUS    => rdata <= reg_int_status;
            when others                 => rdata <= (others => '0');
        end case;
    end process;

    gpio_rsp_o.data <= rdata;
    gpio_rsp_o.ack  <= gpio_req_i.stb;
    gpio_rsp_o.err  <= '0';

    ----------------------------------------------------------------------
    -- Pad driver: strong drive in output mode, weak 'H'/'L' pull in
    -- input mode with the pull enabled, 'Z' otherwise.
    ----------------------------------------------------------------------
    gen_pins : for i in 0 to (PORT_WIDTH - 1) generate
        gpio_port(i) <= reg_out(i) when reg_ddr(i) = '1' else
                           'H' when (reg_pull_en(i) = '1' and reg_pull_sel(i) = '1') else
                           'L' when (reg_pull_en(i) = '1' and reg_pull_sel(i) = '0') else
                           'Z';
    end generate;

    ----------------------------------------------------------------------
    -- Debounce filter (CONFIG bits 15:1)
    ----------------------------------------------------------------------
    debounce_thresh <= unsigned(reg_config(GPIO_DEBOUNCE_MSB downto GPIO_DEBOUNCE_LSB));
    gpio_raw_x01    <= std_ulogic_vector(to_x01(gpio_port));

    process (clk_i)
    begin
        if rising_edge(clk_i) then
            if rst_i = '1' then
                for i in 0 to (PORT_WIDTH - 1) loop
                    debounce_cnt(i) <= (others => '0');
                end loop;

                gpio_debounced <= (others => '0');
            else
                for i in 0 to (PORT_WIDTH - 1) loop
                    if gpio_raw_x01(i) = gpio_debounced(i) then
                        -- Already settled on this value; nothing to count.
                        debounce_cnt(i) <= (others => '0');
                    elsif debounce_cnt(i) >= debounce_thresh then
                        -- Disagreed for debounce_thresh cycles in a row: accept it.
                        gpio_debounced(i) <= gpio_raw_x01(i);
                        debounce_cnt(i)   <= (others => '0');
                    else
                        debounce_cnt(i) <= debounce_cnt(i) + 1;
                    end if;
                end loop;
            end if;
        end if;
    end process;

    gpio_filtered <= gpio_debounced when unsigned(debounce_thresh) /= 0 else gpio_raw_x01;

    ----------------------------------------------------------------------
    -- Interrupt detection for the GPIO port
    ----------------------------------------------------------------------
    process (clk_i)
    begin
        if rising_edge(clk_i) then
            if rst_i = '1' then
                gpio_port_prev <= (others => '0');
            else
                gpio_port_prev <= gpio_filtered;
            end if;
        end if;
    end process;

    -- IRQ output when any pin has changed
    irq_o <= '1' when unsigned(reg_int_status) /= 0 else '0';

    ----------------------------------------------------------------------
    -- Interrupt flags generation
    ----------------------------------------------------------------------
    process (clk_i)
    begin
        if rising_edge(clk_i) then
            if rst_i = '1' then
                reg_int_status  <= (others => '0');
            else
                -- Software clear (write bit to '0')
                if gpio_req_i.stb = '1' and gpio_req_i.we = '1' and word_offset = GPIO_REG_INT_STATUS then
                    reg_int_status <= byte_merge(reg_int_status, gpio_req_i.data, gpio_req_i.ben);
                -- Set the interrupt flags
                else
                    for i in 0 to (PORT_WIDTH - 1) loop
                        if (gpio_filtered(i) xor gpio_port_prev(i)) = '1' and reg_int_config(i) = '1' and reg_config(GPIO_BIT_GLOB_INT) = '1' then
                            reg_int_status(i) <= '1';
                        end if;
                    end loop;
                end if;
            end if;
        end if;
    end process;

end architecture tinymcu_periph_gpio_rtl;
