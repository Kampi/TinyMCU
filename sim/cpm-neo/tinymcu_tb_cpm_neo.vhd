--------------------------------------------------------------------------------
-- SPDX-License-Identifier: GPL-3.0-or-later
--
-- Company:
-- Engineer: Daniel Kampert
--
-- Create Date: 28.08.2026
-- Design Name: TinyMCU
-- Module Name: tb_cpm_neo - sim
-- Project Name: TinyMCU
-- Description:
--   Investigative (not self-checking) testbench: boots the *real*
--   sw/cpm-neo/ image currently baked into tinymcu_imem_bootrom.vhd's
--   PROGRAM constant and tinymcu_sram_generic.vhd's DISK constant (via
--   "make cpm-neo"), with the same generics real hardware currently.
--
-- Dependencies:
--   tinymcu.tinymcu_pkg, tinymcu.tinymcu_cpu
--
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

library tinymcu;
use tinymcu.tinymcu_pkg.all;

entity tb_cpm_neo is
end entity tb_cpm_neo;

architecture sim of tb_cpm_neo is

    -- Matches sw/cpm-neo/platform/tinymcu/mmio.h's TINYMCU_CLK_KHZ (16000).
    -- The already-baked-in bootloader/kernel's BAUDRATE divisor assumes
    -- this clock, so UART bit timing (and therefore how many cycles this
    -- run needs) only makes sense relative to it.
    constant CLK_PERIOD : time := 62.5 ns;

    signal clk : std_ulogic := '0';
    signal rst : std_ulogic := '1';

    signal dbg_regs : reg_array_t;
    signal uart_tx  : std_ulogic;

begin

    clk <= not clk after CLK_PERIOD / 2;

    dut : entity tinymcu.tinymcu_cpu
        generic map (
            IMEM_ADDR_WIDTH    => 13,
            RAM_ADDR_WIDTH     => 14,
            RAMDISK_ENABLE     => true,
            RAMDISK_ADDR_WIDTH => 15,
            TRACE_ENABLE       => true
        )
        port map (
            clk_i        => clk,
            rst_i        => rst,
            ext_irq_i    => '0',
            gpio_port    => open,
            uart_tx_o    => uart_tx,
            uart_rx_i    => '1',
            uart_rts_o   => open,
            uart_cts_i   => '1',
            debug_regs_o => dbg_regs
        );

    stim : process
    begin
        rst <= '1';
        wait for CLK_PERIOD * 10;
        rst <= '0';

        -- Never asserted again -- see header comment.
        wait for CLK_PERIOD * 5_000_000;

        report "SIM DONE (5_000_000 cycles elapsed, no further rst assert)";
        std.env.stop;
        wait;
    end process;

end architecture sim;
