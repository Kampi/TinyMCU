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
--  Self-checking testbench for the TinyMCU IRQ and trap logic.
--
-- Dependencies:
--   tinymcu.tinymcu_pkg, tinymcu.tinymcu_cpu
--
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
            IMEM_ADDR_WIDTH => 13,
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

        wait for CLK_PERIOD * 20;
        report "asserting ext_irq_i now";
        ext_irq <= '1';
        wait for CLK_PERIOD * 1;
        ext_irq <= '0';
        report "deasserted ext_irq_i";

        -- Handler (2 instructions) + mret + resume
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
