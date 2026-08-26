--------------------------------------------------------------------------------
-- SPDX-License-Identifier: GPL-3.0-or-later
--
-- Company:
-- Engineer: Daniel Kampert
--
-- Create Date: 26.08.2026
-- Design Name: TinyMCU
-- Module Name: tb_mult - sim
-- Project Name: TinyMCU
-- Description:
--   Standalone functional test for tinymcu_cpu_mult.vhd (the M-
--   extension multiply unit). Covers all four RV32M multiply
--   variants (MUL/MULH/MULHSU/MULHU, selected via funct3_i).
--
-- Dependencies:
--   tinymcu.tinymcu_pkg, tinymcu.tinymcu_cpu_mult
--
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

library tinymcu;
use tinymcu.tinymcu_pkg.all;

entity tb_mult is end entity tb_mult;

architecture sim of tb_mult is

    constant CLK_PERIOD : time := 10 ns;

    signal clk    : std_ulogic := '0';
    signal rst    : std_ulogic := '1';
    signal op_a   : word_t := (others => '0');
    signal op_b   : word_t := (others => '0');
    signal result : word_t;
    signal start  : std_ulogic := '0';
    signal busy   : std_ulogic;
    signal valid  : std_ulogic;
    signal funct3 : std_ulogic_vector(2 downto 0) := "000";

begin

    clk <= not clk after CLK_PERIOD / 2;

    dut : entity tinymcu.tinymcu_cpu_mult
        port map (
            clk_i    => clk,
            rst_i    => rst,
            op_a_i   => op_a,
            op_b_i   => op_b,
            result_o => result,
            start_i  => start,
            busy_o   => busy,
            valid_o  => valid,
            funct3_i => funct3
        );

    stim : process
        variable errors : integer := 0;

        -- a, b and expected are raw bit patterns (not "integer", which can't represent values like 0xFFFFFFFF as a 32-bit signed
        -- VHDL integer) so this covers both the unsigned MUL cases and he signed MULH/MULHSU cases uniformly.
        procedure do_multiply(a, b, expected : word_t; mode : std_ulogic_vector(2 downto 0); name : string) is
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

            check(name & ": busy goes high", busy = '1', errors);

            while busy = '1' and cycles_waited < 100 loop
                wait until rising_edge(clk);
                wait for 1 ns;
                cycles_waited := cycles_waited + 1;
            end loop;

            check(name & ": finished within 40 cycles (32-bit shift-add)", cycles_waited <= 40, errors);
            check(name & ": valid pulses when busy drops", valid = '1', errors);
            check(name & " result", result, expected, errors);
        end procedure;

    begin
        wait for CLK_PERIOD * 3;
        rst <= '0';
        wait for CLK_PERIOD * 2;

        -- MUL (funct3 = 000): low word only, operand sign never matters.
        do_multiply(x"00000005", x"00000003", x"0000000F", "000", "MUL 5*3");
        do_multiply(x"00000007", x"00000006", x"0000002A", "000", "MUL 7*6 (second run, tests accumulator reset)");
        do_multiply(x"FFFFFFFF", x"00000002", x"FFFFFFFE", "000", "MUL 0xFFFFFFFF*2 (carry stress)");

        -- MULH (funct3 = 001): signed x signed, high word.
        -- (-3) * 5 = -15 -> 64-bit two's complement 0xFFFFFFFF_FFFFFFF1.
        do_multiply(x"FFFFFFFD", x"00000005", x"FFFFFFFF", "001", "MULH (-3)*5");
        -- INT_MIN * INT_MIN = 2^62 -> 0x40000000_00000000.
        do_multiply(x"80000000", x"80000000", x"40000000", "001", "MULH INT_MIN*INT_MIN");

        -- MULHSU (funct3 = 010): signed(a) x unsigned(b), high word.
        -- (-1) * 0xFFFFFFFF(unsigned) = -4294967295 -> 0xFFFFFFFF_00000001.
        do_multiply(x"FFFFFFFF", x"FFFFFFFF", x"FFFFFFFF", "010", "MULHSU (-1)*0xFFFFFFFF(u)");
        -- 3 * 0xFFFFFFFF(unsigned) = 12884901885 -> 0x00000002_FFFFFFFD.
        do_multiply(x"00000003", x"FFFFFFFF", x"00000002", "010", "MULHSU 3*0xFFFFFFFF(u)");

        -- MULHU (funct3 = 011): unsigned x unsigned, high word.
        -- 0xFFFFFFFF * 0xFFFFFFFF = 0xFFFFFFFE_00000001.
        do_multiply(x"FFFFFFFF", x"FFFFFFFF", x"FFFFFFFE", "011", "MULHU 0xFFFFFFFF*0xFFFFFFFF");
        do_multiply(x"00000005", x"00000003", x"00000000", "011", "MULHU 5*3 (high word is zero)");

        report "Total errors: " & integer'image(errors);
        if errors = 0 then
            report "ALL CHECKS PASSED";
        end if;

        std.env.stop;
        wait;
    end process;

end architecture sim;
