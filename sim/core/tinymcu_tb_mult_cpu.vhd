--------------------------------------------------------------------------------
-- SPDX-License-Identifier: GPL-3.0-or-later
--
-- Company:
-- Engineer: Daniel Kampert
--
-- Create Date: 26.08.2026
-- Design Name: TinyMCU
-- Module Name: tb_mult_cpu - sim
-- Project Name: TinyMCU
-- Description:
--   Runs the multiplier through the full CPU pipeline (tinymcu_cpu),
--   not just the standalone unit (see tinymcu_tb_mult.vhd for that).
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

entity tb_mult_cpu is
end entity tb_mult_cpu;

architecture sim of tb_mult_cpu is

    constant CLK_PERIOD : time := 10 ns;

    signal clk : std_ulogic := '0';
    signal rst : std_ulogic := '1';

    signal dbg_regs : reg_array_t;

begin

    clk <= not clk after CLK_PERIOD / 2;

    dut : entity tinymcu.tinymcu_cpu
        generic map (
            IMEM_ADDR_WIDTH => 10,
            RAM_ADDR_WIDTH  => 8
        )
        port map (
            clk_i        => clk,
            rst_i        => rst,
            ext_irq_i    => '0',
            gpio_port_a  => open,
            debug_regs_o => dbg_regs
        );

    stim : process
        variable errors : integer := 0;
    begin
        rst <= '1';
        wait for CLK_PERIOD * 3;
        rst <= '0';

        -- 6 instructions, two of them 32-cycle multiplies -> generous margin.
        wait for CLK_PERIOD * 100;

        check("x1 (6)",      dbg_regs(1), x"00000006", errors);
        check("x2 (7)",      dbg_regs(2), x"00000007", errors);
        check("x3 (6*7=42)", dbg_regs(3), x"0000002A", errors);
        check("x4 (111)",    dbg_regs(4), x"0000006F", errors);
        check("x5 (7*7=49)", dbg_regs(5), x"00000031", errors);

        report "Total errors: " & integer'image(errors);
        if errors = 0 then
            report "ALL CHECKS PASSED";
        end if;

        std.env.stop;
        wait;
    end process;

end architecture sim;
