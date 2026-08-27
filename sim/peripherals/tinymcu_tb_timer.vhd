--------------------------------------------------------------------------------
-- SPDX-License-Identifier: GPL-3.0-or-later
--
-- Company:
-- Engineer: Daniel Kampert
--
-- Create Date: 24.08.2026
-- Design Name: TinyMCU
-- Module Name: tb_timer - sim
-- Project Name: TinyMCU
-- Description:
--   Standalone functional test for tinymcu_periph_timer.vhd.
--
-- Dependencies:
--   tinymcu.tinymcu_pkg, tinymcu.tinymcu_periph_timer
--
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

library tinymcu;
use tinymcu.tinymcu_pkg.all;

entity tb_timer is end entity tb_timer;

architecture sim of tb_timer is

    constant CLK_PERIOD : time := 10 ns;

    signal clk : std_ulogic := '0';
    signal rst : std_ulogic := '1';
    signal irq : std_ulogic;
    signal req : bus_req_t := BUS_REQ_IDLE;
    signal rsp : bus_rsp_t;

begin

    clk <= not clk after CLK_PERIOD / 2;

    dut : entity tinymcu.tinymcu_periph_timer
        port map (
            clk_i => clk,
            rst_i => rst,
            irq_o => irq,
            timer_req_i => req,
            timer_rsp_o => rsp
        );

    stim : process
        procedure bus_write(addr : std_ulogic_vector(31 downto 0); data : word_t) is
        begin
            wait until rising_edge(clk);
            req.addr <= addr;
            req.data <= data;
            req.ben  <= "1111";
            req.we   <= '1';
            req.stb  <= '1';
            wait until rising_edge(clk);
            req.we  <= '0';
            req.stb <= '0';
        end procedure;

        procedure bus_read(addr : std_ulogic_vector(31 downto 0); variable result : out word_t) is
        begin
            req.addr <= addr;
            req.we   <= '0';
            req.stb  <= '1';
            wait for 1 ns;
            result := rsp.data;
            req.stb <= '0';
        end procedure;

        variable rd : word_t;
        variable errors : integer := 0;
    begin
        wait for CLK_PERIOD * 3;
        rst <= '0';

        -- Prescaler: DIV4 (CLKSEL=0011), verify COUNTER advances by
        -- exactly 25 in 100 cycles (100/4=25).
        bus_write(x"00000000", x"00000003");  -- CONFIG = DIV4
        wait for CLK_PERIOD * 100;
        bus_read(x"0000000C", rd);  -- COUNTER (word offset 3 = byte 0xC)
        check("prescaler DIV4: 100 cycles -> 25 ticks", to_integer(unsigned(rd)) = 25, errors);

        -- Reset COUNTER, arm COMPARE + enable interrupt, wait for match.
        bus_write(x"0000000C", x"00000000");        -- COUNTER = 0
        bus_write(x"00000010", x"0000000A");        -- COMPARE = 10 (word offset 4 = byte 0x10)
        bus_write(x"00000004", x"00000001");        -- INT_CONFIG bit0 = 1 (enable)
        bus_read(x"00000008", rd);                  -- INT_STATUS (word offset 2 = byte 0x08) before match
        check("INT_STATUS clear before match", to_integer(unsigned(rd)) = 0, errors);
        check("irq_o low before match", irq = '0', errors);

        wait for CLK_PERIOD * 60;  -- 60 cycles @ DIV4 -> 15 ticks, well past compare=10

        bus_read(x"00000008", rd);
        check("INT_STATUS set after match", rd(0) = '1', errors);
        check("irq_o high after match", irq = '1', errors);

        -- Software clear.
        bus_write(x"00000008", x"00000000");        -- INT_STATUS = 0 (clear)
        bus_read(x"00000008", rd);
        check("INT_STATUS cleared by software write", to_integer(unsigned(rd)) = 0, errors);
        check("irq_o low after clear", irq = '0', errors);

        -- Must not re-trigger just from COUNTER continuing past COMPARE
        -- again without a fresh edge (counter only equals compare once
        -- per wrap, and DIV4 counting is monotonic here).
        wait for CLK_PERIOD * 40;
        bus_read(x"00000008", rd);
        check("INT_STATUS stays clear (no spurious re-trigger)", to_integer(unsigned(rd)) = 0, errors);

        -- Disabled interrupt: reset counter, disable INT_CONFIG, cross
        -- compare again -> must NOT set the flag.
        bus_write(x"00000004", x"00000000");        -- INT_CONFIG = 0 (disable)
        bus_write(x"0000000C", x"00000000");        -- COUNTER = 0
        wait for CLK_PERIOD * 60;
        bus_read(x"00000008", rd);
        check("INT_STATUS stays clear when INT_CONFIG disabled", to_integer(unsigned(rd)) = 0, errors);
        check("irq_o stays low when INT_CONFIG disabled", irq = '0', errors);

        report "Total errors: " & integer'image(errors);
        if errors = 0 then
            report "ALL CHECKS PASSED";
        end if;

        std.env.stop;
        wait;
    end process;

end architecture sim;
