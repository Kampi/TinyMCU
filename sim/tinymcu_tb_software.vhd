--------------------------------------------------------------------------------
-- SPDX-License-Identifier: GPL-3.0-or-later
--
-- Company:
-- Engineer: Daniel Kampert
--
-- Create Date: 15.08.2026
-- Design Name: TinyMCU
-- Module Name: tb_cpu - sim
-- Project Name: TinyMCU
-- Description:
--   Runs whatever program sw/*/Makefile's "rom" target last wrote into
--   tinymcu_imem_bootrom.vhd via scripts/hex2rom.py, with tinymcu_cpu's
--   TRACE_ENABLE turned on: every cycle prints
--   "PC=0x... INSTR=0x..."
--   Cross-reference against the corresponding sw/*/build/main.lst 
--   (objdump disassembly) to read the trace as mnemonics instead of raw hex.
--
-- Dependencies:
--   tinymcu.tinymcu_pkg, tinymcu.tinymcu_cpu
--
-- Additional Comments:
--   This file is compiled into the default "work" library (it is
--   verification scaffolding, not an MCU-specific component) and
--   references the design under test from the "tinymcu" library.
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

library tinymcu;
use tinymcu.tinymcu_pkg.all;

entity tb_cpu is
end entity tb_cpu;

architecture sim of tb_cpu is

    constant CLK_PERIOD : time := 10 ns;

    signal clk : std_ulogic := '0';
    signal rst : std_ulogic := '1';

    signal dbg_regs : reg_array_t;

begin

    -- Clock generation
    clk <= not clk after CLK_PERIOD / 2;

    dut : entity tinymcu.tinymcu_cpu
        generic map (
            IMEM_ADDR_WIDTH => 10,
            RAM_ADDR_WIDTH => 8,
            TRACE_ENABLE    => true
        )
        port map (
            clk_i        => clk,
            rst_i        => rst,
            ext_irq_i    => '0',
            gpio_port_a  => open,
            debug_regs_o => dbg_regs
        );

    stim : process
    begin
        rst <= '1';
        wait for CLK_PERIOD * 3;
        rst <= '0';

        wait for CLK_PERIOD * 100;

        std.env.stop;
        wait;
    end process;

end architecture sim;
