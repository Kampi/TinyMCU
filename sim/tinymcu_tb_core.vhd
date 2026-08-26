--------------------------------------------------------------------------------
-- SPDX-License-Identifier: GPL-3.0-or-later
--
-- Company:
-- Engineer: Daniel Kampert
--
-- Create Date: 15.08.2026
-- Design Name: TinyMCU
-- Module Name: tb_core - sim
-- Project Name: TinyMCU
-- Description:
--   Self-checking testbench for the TinyMCU core (tinymcu.tinymcu_cpu).
--   Runs the demo program stored in tinymcu_imem_bootrom.vhd and compares
--   the final register file values against the expected results via the
--   debug_regs_o port (simulation only; left unconnected in the FPGA top
--   level).
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

entity tb_core is
end entity tb_core;

architecture sim of tb_core is

    constant CLK_PERIOD : time := 10 ns;

    signal clk : std_ulogic := '0';
    signal rst : std_ulogic := '1';

    signal dbg_regs : reg_array_t;

begin

    -- Clock generation
    clk <= not clk after CLK_PERIOD / 2;

    dut : entity tinymcu.tinymcu_cpu
        generic map (
            IMEM_ADDR_WIDTH => 13,
            RAM_ADDR_WIDTH => 8
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

        -- 41 instructions + pipeline fill + 3 branch/jump bubbles (beq,
        -- jal, jalr); generous margin included.
        wait for CLK_PERIOD * 150;

        -- TINYMCU_CHECKS_BEGIN (auto-generated, do not edit by hand)
        check("x1  (5+1)", dbg_regs(1), x"00000006", errors);
        check("x2  (10)", dbg_regs(2), x"0000000A", errors);
        check("x3  (x1+x2)", dbg_regs(3), x"0000000F", errors);
        check("x4  (x2-x1)", dbg_regs(4), x"00000005", errors);
        check("x5  (lw mem[0])", dbg_regs(5), x"0000000F", errors);
        check("x6  (beq skip)", dbg_regs(6), x"00000000", errors);
        check("x7  (42)", dbg_regs(7), x"0000002A", errors);
        check("x8  (lui 0x1)", dbg_regs(8), x"00001000", errors);
        check("x9  (jal link)", dbg_regs(9), x"00000030", errors);
        check("x10 (jal skip)", dbg_regs(10), x"00000000", errors);
        check("x11 (jalr base)", dbg_regs(11), x"0000003C", errors);
        check("x12 (jalr link)", dbg_regs(12), x"00000040", errors);
        check("x13 (jalr skip)", dbg_regs(13), x"00000000", errors);
        check("x14 (jalr landing point)", dbg_regs(14), x"00000037", errors);
        check("x15 (auipc pc+0x1000)", dbg_regs(15), x"00001048", errors);
        check("x16 (0xAA)", dbg_regs(16), x"000000AA", errors);
        check("x17 (-1)", dbg_regs(17), x"FFFFFFFF", errors);
        check("x18 (lw after 2x sb)", dbg_regs(18), x"0000FFAA", errors);
        check("x19 (0x3CD)", dbg_regs(19), x"000003CD", errors);
        check("x20 (lw after sh)", dbg_regs(20), x"000003CD", errors);
        check("x21 (RAM base)", dbg_regs(21), x"02000000", errors);
        check("x22 (mvendorid)", dbg_regs(22), x"00000000", errors);
        check("x23 (csrrw old mscratch)", dbg_regs(23), x"00000000", errors);
        check("x24 (csrrw read back mscratch)", dbg_regs(24), x"00000123", errors);
        check("x25 (marchid)", dbg_regs(25), x"00000000", errors);
        check("x26 (csrrs old mscratch)", dbg_regs(26), x"00000000", errors);
        check("x27 (csrrs read back mscratch)", dbg_regs(27), x"000000F0", errors);
        check("x28 (mimpid)", dbg_regs(28), x"00000000", errors);
        check("x29 (csrrc old mscratch)", dbg_regs(29), x"000000F0", errors);
        check("x30 (csrrc read back mscratch)", dbg_regs(30), x"000000C0", errors);
        check("x31 (csrrwi old mscratch)", dbg_regs(31), x"000000C0", errors);
        -- TINYMCU_CHECKS_END

        if errors = 0 then
            report "TEST PASSED";
        else
            report "TEST FAILED with " & integer'image(errors) & " error(s)" severity error;
        end if;

        std.env.stop;
        wait;
    end process;

end architecture sim;
