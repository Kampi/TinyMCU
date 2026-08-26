--------------------------------------------------------------------------------
-- SPDX-License-Identifier: GPL-3.0-or-later
--
-- Company:
-- Engineer: Daniel Kampert
--
-- Create Date: 26.08.2026
-- Design Name: TinyMCU
-- Module Name: tb_div - sim
-- Project Name: TinyMCU
-- Description:
--   Standalone functional test for tinymcu_cpu_div.vhd (the M-
--   extension divide unit). Covers all four RV32M divide variants
--   (DIV/DIVU/REM/REMU, selected via funct3_i), plus division-by-zero
--   and the signed-overflow ((-2^31)/(-1)) special cases.
--
-- Dependencies:
--   tinymcu.tinymcu_pkg, tinymcu.tinymcu_cpu_div
--
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

library tinymcu;
use tinymcu.tinymcu_pkg.all;

entity tb_div is end entity tb_div;

architecture sim of tb_div is

    constant CLK_PERIOD : time := 10 ns;

    signal clk       : std_ulogic := '0';
    signal rst       : std_ulogic := '1';
    signal op_a      : word_t := (others => '0');
    signal op_b      : word_t := (others => '0');
    signal quotient  : word_t;
    signal remainder : word_t;
    signal start     : std_ulogic := '0';
    signal busy      : std_ulogic;
    signal valid     : std_ulogic;
    signal funct3    : std_ulogic_vector(2 downto 0) := "000";

begin

    clk <= not clk after CLK_PERIOD / 2;

    dut : entity tinymcu.tinymcu_cpu_div
        port map (
            clk_i       => clk,
            rst_i       => rst,
            op_a_i      => op_a,
            op_b_i      => op_b,
            quotient_o  => quotient,
            remainder_o => remainder,
            start_i     => start,
            busy_o      => busy,
            valid_o     => valid,
            funct3_i    => funct3
        );

    stim : process
        variable errors : integer := 0;

        -- a, b and the expected outputs are raw bit patterns (not "integer", which can't represent values like 0xFFFFFFFF as a
        -- 32-bit signed VHDL integer) so this covers both the unsigned and signed cases uniformly.
        procedure do_div(a, b, exp_q, exp_r : word_t; mode : std_ulogic_vector(2 downto 0); name : string) is
            variable cycles_waited : integer := 0;
        begin
            report "---- " & name & " ----";

            wait until rising_edge(clk);
            op_a   <= a;
            op_b   <= b;
            funct3 <= mode;
            start  <= '1';
            wait until rising_edge(clk);
            start <= '0';
            wait for 1 ns;

            while busy = '1' and cycles_waited < 100 loop
                wait until rising_edge(clk);
                wait for 1 ns;
                cycles_waited := cycles_waited + 1;
            end loop;

            check(name & ": finished within 40 cycles (32-bit shift-subtract + Check)", cycles_waited <= 40, errors);
            check(name & ": valid pulses when busy drops", valid = '1', errors);
            check(name & " quotient", quotient, exp_q, errors);
            check(name & " remainder", remainder, exp_r, errors);
        end procedure;

    begin
        wait for CLK_PERIOD * 3;
        rst <= '0';
        wait for CLK_PERIOD * 2;

        -- DIV (signed): all four sign combinations, truncated toward zero.
        do_div(x"0000000A", x"00000003", x"00000003", x"00000001", "100", "DIV 10/3");
        do_div(x"FFFFFFF6", x"00000003", x"FFFFFFFD", x"FFFFFFFF", "100", "DIV -10/3");
        do_div(x"0000000A", x"FFFFFFFD", x"FFFFFFFD", x"00000001", "100", "DIV 10/-3");
        do_div(x"FFFFFFF6", x"FFFFFFFD", x"00000003", x"FFFFFFFF", "100", "DIV -10/-3");

        -- DIVU (unsigned).
        do_div(x"0000000A", x"00000003", x"00000003", x"00000001", "101", "DIVU 10/3");
        do_div(x"FFFFFFFF", x"00000002", x"7FFFFFFF", x"00000001", "101", "DIVU 0xFFFFFFFF/2");

        -- REM/REMU: remainder follows the dividend's sign.
        do_div(x"FFFFFFF6", x"00000003", x"FFFFFFFD", x"FFFFFFFF", "110", "REM -10%3");
        do_div(x"0000000A", x"00000003", x"00000003", x"00000001", "111", "REMU 10%3");

        -- Division by zero: quotient = all ones, remainder = dividend
        -- unchanged. Applies to all four variants, not just DIV/DIVU.
        do_div(x"0000000A", x"00000000", x"FFFFFFFF", x"0000000A", "100", "DIV 10/0");
        do_div(x"0000000A", x"00000000", x"FFFFFFFF", x"0000000A", "101", "DIVU 10/0");
        do_div(x"FFFFFFF6", x"00000000", x"FFFFFFFF", x"FFFFFFF6", "110", "REM -10%0");

        -- Signed overflow ((-2^31)/(-1)): quotient = dividend unchanged,
        -- remainder = 0. Only applies to DIV/REM (signed), not DIVU/REMU.
        do_div(x"80000000", x"FFFFFFFF", x"80000000", x"00000000", "100", "DIV INT_MIN/-1");
        -- Same bit pattern via DIVU: NOT a special case, ordinary unsigned division.
        do_div(x"80000000", x"FFFFFFFF", x"00000000", x"80000000", "101", "DIVU 0x80000000/0xFFFFFFFF");

        report "Total errors: " & integer'image(errors);
        if errors = 0 then
            report "ALL CHECKS PASSED";
        end if;

        std.env.stop;
        wait;
    end process;

end architecture sim;
