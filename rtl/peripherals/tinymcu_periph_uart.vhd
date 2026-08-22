--------------------------------------------------------------------------------
-- SPDX-License-Identifier: GPL-3.0-or-later
--
-- Company:
-- Engineer: Daniel Kampert
--
-- Create Date: 14.06.2026
-- Design Name: TinyMCU
-- Module Name: tinymcu_periph_uart - tinymcu_periph_uart_rtl
-- Project Name: TinyMCU
-- Description:
--   UART_BASE..UART_END (0x0400_0200..0x0400_02FF
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

entity tinymcu_periph_uart is
    port (
        -- Global control
        clk_i       : in  std_ulogic;
        rst_i       : in  std_ulogic;

        -- Peripheral Decoder-facing side
        uart_req_i : in  bus_req_t;
        uart_rsp_o : out bus_rsp_t
    );
end entity tinymcu_periph_uart;

architecture tinymcu_periph_uart_rtl of tinymcu_periph_uart is

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

    signal word_offset      : integer range 0 to 63;

begin

    -- 256 B window, 64 possible word offsets
    word_offset <= to_integer(unsigned(uart_req_i.addr(7 downto 2)));

end architecture tinymcu_periph_uart_rtl;
