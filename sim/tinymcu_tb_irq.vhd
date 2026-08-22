--------------------------------------------------------------------------------
-- SPDX-License-Identifier: GPL-3.0-or-later
--
-- Company:
-- Engineer: Daniel Kampert
--
-- Create Date: 18.08.2026
-- Design Name: TinyMCU
-- Module Name: tb_irq - sim
-- Project Name: TinyMCU
-- Description:
--   Manual trap/return round-trip check for ext_irq_i. Not wired into the
--   default "make run" (see rtl/Makefile's SIM_SRCS): it needs the ROM to
--   hold a program that sets up mtvec/mstatus.MIE/mie.MEIE and provides a
--   handler, not the asm.py demo program that "make run" regenerates.
--   Switch to it by hand, the same way as tinymcu_tb_software.vhd:
--
--     SIM_SRCS := $(SIM_DIR)/tinymcu_tb_irq.vhd
--
--   Expected ROM layout (word index -> byte address):
--      0: addi x1, x0, 0x40       ; x1 = handler address
--      1: csrrw x0, mtvec, x1     ; mtvec = 0x40
--      2: addi x2, x0, 8          ; x2 = 1<<3 (MIE)
--      3: csrrw x0, mstatus, x2   ; mstatus.MIE = 1
--      4: lui x3, 1               ; x3 = 0x1000
--      5: addi x3, x3, -2048      ; x3 = 0x800 (MEIE)
--      6: csrrw x0, mie, x3       ; mie.MEIE = 1
--      7: loop: addi x7, x7, 1    ; counting loop body
--      8: jal x0, -4              ; back to loop
--      9..15: nop (padding up to the handler address)
--     16: handler: addi x6, x0, 222  ; marker: handler ran
--     17: mret
--
--   Asserts ext_irq_i for one cycle while the loop body is in EX, then
--   checks that the handler ran (x6 = 222) and that the loop resumed
--   after mret instead of restarting or hanging (x7 > 0).
--
-- Dependencies:
--   tinymcu.tinymcu_pkg, tinymcu.tinymcu_cpu
--
-- Additional Comments:
--   Compiled into the default "work" library, like the other sim/*.vhd
--   testbenches; references the design under test from the "tinymcu"
--   library.
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library tinymcu;
use tinymcu.tinymcu_pkg.all;

entity tb_irq is
end entity tb_irq;

architecture sim of tb_irq is

    constant CLK_PERIOD : time := 10 ns;

    signal clk     : std_ulogic := '0';
    signal rst     : std_ulogic := '1';
    signal ext_irq : std_ulogic := '0';
    signal gpio    : std_logic_vector(31 downto 0);
    signal dbg     : reg_array_t;

begin

    clk <= not clk after CLK_PERIOD / 2;

    dut : entity tinymcu.tinymcu_cpu
        generic map (
            IMEM_ADDR_WIDTH => 10,
            RAM_ADDR_WIDTH  => 8,
            TRACE_ENABLE    => true
        )
        port map (
            clk_i        => clk,
            rst_i        => rst,
            ext_irq_i    => ext_irq,
            gpio_port_a  => gpio,
            debug_regs_o => dbg
        );

    stim : process
    begin
        rst <= '1';
        wait for CLK_PERIOD * 3;
        rst <= '0';

        -- Let the 7 setup instructions (mtvec/mstatus/mie writes) run,
        -- then a few counting-loop iterations, then pulse the external
        -- IRQ for exactly one cycle. mip's MEIP bit is a live overlay of
        -- ext_irq_i (level-triggered), so it must drop again before mret
        -- restores mstatus.MIE, or the core would re-trap instantly.
        wait for CLK_PERIOD * 20;
        report "asserting ext_irq_i now";
        ext_irq <= '1';
        wait for CLK_PERIOD * 1;
        ext_irq <= '0';
        report "deasserted ext_irq_i";

        -- Handler (2 instructions) + mret + resume; generous margin.
        wait for CLK_PERIOD * 20;

        report "x6 (handler marker, expect 222) = " & integer'image(to_integer(unsigned(dbg(6))));
        report "x7 (loop counter, expect > 0)    = " & integer'image(to_integer(unsigned(dbg(7))));
        assert to_integer(unsigned(dbg(6))) = 222
            report "FAIL: handler did not run (x6 /= 222)" severity error;
        assert to_integer(unsigned(dbg(7))) > 0
            report "FAIL: loop did not resume after mret (x7 = 0)" severity error;

        std.env.stop;
        wait;
    end process;

end architecture sim;
