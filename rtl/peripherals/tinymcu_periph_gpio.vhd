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
--   GPIO_BASE..GPIO_END (0x0400_0000..0x0400_00FF
--
--   Word offset  Name       R/W  Meaning
--   0            CONFIG     RW   General-purpose config register, no
--                                 bits defined yet; plain read/write
--                                 storage, reserved for future use.
--   1            DDR        RW   Data direction, per pin: 1 = output,
--                                 0 = input.
--   2            PULL_SEL   RW   Pull resistor select, per pin (only
--                                 meaningful combined with PULL_EN):
--                                 1 = pull-up, 0 = pull-down.
--   3            PULL_EN    RW   Pull resistor enable, per pin:
--                                 1 = the pull configured by PULL_SEL is
--                                 active, 0 = floating.
--   4            OUT        RW   Output data, per pin: drives the pin
--                                 when DDR = 1; has no effect on a pin
--                                 configured as input.
--   5            IN         RO   Input data, per pin: the pin's actual
--                                 resolved logic level (normalized to
--                                 '1'/'0' via to_x01, see below),
--                                 regardless of DDR (also readable while
--                                 DDR = 1, to read back what's being
--                                 driven). Writes are ignored.
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
    port (
        -- Global control
        clk_i : in std_ulogic;
        rst_i : in std_ulogic;

        -- Pad-facing side
        gpio_port_a : inout std_logic_vector(31 downto 0);

        -- Peripheral Decoder-facing side
        gpio_req_i : in  bus_req_t;
        gpio_rsp_o : out bus_rsp_t
    );
end entity tinymcu_periph_gpio;

architecture tinymcu_periph_gpio_rtl of tinymcu_periph_gpio is

    constant GPIO_REG_CONFIG    : integer := 0;
    constant GPIO_REG_DDR       : integer := 1;
    constant GPIO_REG_PULL_SEL  : integer := 2;
    constant GPIO_REG_PULL_EN   : integer := 3;
    constant GPIO_REG_OUT       : integer := 4;
    constant GPIO_REG_IN        : integer := 5;

    signal reg_config   : word_t;
    signal reg_ddr      : word_t    := (others => '1');
    signal reg_pull_sel : word_t    := (others => '0');
    signal reg_pull_en  : word_t    := (others => '0');
    signal reg_out      : word_t    := (others => '0');

    signal word_offset  : integer range 0 to 63;

    signal rdata        : word_t;

begin

    -- 256 B window, 64 possible word offsets
    word_offset <= to_integer(unsigned(gpio_req_i.addr(7 downto 2)));

    ----------------------------------------------------------------------
    -- Register writes
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
                    when GPIO_REG_CONFIG    => reg_config   <= byte_merge(reg_config, gpio_req_i.data, gpio_req_i.ben);
                    when GPIO_REG_DDR       => reg_ddr      <= byte_merge(reg_ddr, gpio_req_i.data, gpio_req_i.ben);
                    when GPIO_REG_PULL_SEL  => reg_pull_sel <= byte_merge(reg_pull_sel, gpio_req_i.data, gpio_req_i.ben);
                    when GPIO_REG_PULL_EN   => reg_pull_en  <= byte_merge(reg_pull_en, gpio_req_i.data, gpio_req_i.ben);
                    when GPIO_REG_OUT       => reg_out      <= byte_merge(reg_out, gpio_req_i.data, gpio_req_i.ben);
                    when others             => null;
                end case;
            end if;
        end if;
    end process;

    ----------------------------------------------------------------------
    -- Register reads
    ----------------------------------------------------------------------
    process (word_offset, reg_config, reg_ddr, reg_pull_sel, reg_pull_en, reg_out, gpio_port_a)
    begin
        case word_offset is
            when GPIO_REG_CONFIG    => rdata <= reg_config;
            when GPIO_REG_DDR       => rdata <= reg_ddr;
            when GPIO_REG_PULL_SEL  => rdata <= reg_pull_sel;
            when GPIO_REG_PULL_EN   => rdata <= reg_pull_en;
            when GPIO_REG_OUT       => rdata <= reg_out;
            -- to_x01 normalizes the weak 'H'/'L' pull values (see the
            -- header) to real '1'/'0' logic levels: a pin only weakly
            -- pulled high should still read back as a plain '1', exactly
            -- like a real input buffer would present it, not leak the
            -- simulation-only weak-value distinction into software.
            when GPIO_REG_IN        => rdata <= std_ulogic_vector(to_x01(gpio_port_a));
            when others             => rdata <= (others => '0');
        end case;
    end process;

    gpio_rsp_o.data <= rdata;
    gpio_rsp_o.ack  <= gpio_req_i.stb;
    gpio_rsp_o.err  <= '0';

    ----------------------------------------------------------------------
    -- Pad driver: strong drive in output mode, weak 'H'/'L' pull in
    -- input mode with the pull enabled, 'Z' otherwise.
    ----------------------------------------------------------------------
    gen_pins : for i in 0 to 31 generate
        gpio_port_a(i) <= reg_out(i) when reg_ddr(i) = '1' else
                           'H' when (reg_pull_en(i) = '1' and reg_pull_sel(i) = '1') else
                           'L' when (reg_pull_en(i) = '1' and reg_pull_sel(i) = '0') else
                           'Z';
    end generate;

end architecture tinymcu_periph_gpio_rtl;
