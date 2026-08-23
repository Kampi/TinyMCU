--------------------------------------------------------------------------------
-- SPDX-License-Identifier: GPL-3.0-or-later
--
-- Company:
-- Engineer: Daniel Kampert
--
-- Create Date: 24.08.2026
-- Design Name: TinyMCU
-- Module Name: tb_gpio - sim
-- Project Name: TinyMCU
-- Description:
--   Standalone functional test for tinymcu_periph_gpio.vhd.
--
-- Dependencies:
--   tinymcu.tinymcu_pkg, tinymcu.tinymcu_periph_gpio
--
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

library tinymcu;
use tinymcu.tinymcu_pkg.all;

entity tb_gpio is end entity tb_gpio;

architecture sim of tb_gpio is

    constant CLK_PERIOD : time := 10 ns;

    signal clk  : std_ulogic := '0';
    signal rst  : std_ulogic := '1';
    signal gpio : std_logic_vector(31 downto 0);
    signal req  : bus_req_t := (addr => (others => '0'), data => (others => '0'), ben => (others => '0'), we => '0', stb => '0');
    signal rsp  : bus_rsp_t;

begin

    clk <= not clk after CLK_PERIOD / 2;

    dut : entity tinymcu.tinymcu_periph_gpio
        port map (clk_i => clk, rst_i => rst, gpio_port_a => gpio,
                   gpio_req_i => req, gpio_rsp_o => rsp);

    gpio(3) <= '1';

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

        procedure check(name : string; cond : boolean) is
        begin
            if cond then
                report "OK   " & name;
            else
                report "FAIL " & name severity error;
                errors := errors + 1;
            end if;
        end procedure;
    begin
        wait for CLK_PERIOD * 3;
        rst <= '0';
        wait for CLK_PERIOD * 2;

        -- Reset state: all pins input, no pulls, output data 0.
        bus_read(x"00000004", rd);  -- DDR (word offset 1)
        check("DDR resets to all-input (0)", to_integer(unsigned(rd)) = 0);

        -- Pin 0 as output, drive it high then low, observe gpio_port_a.
        bus_write(x"00000004", x"00000001");  -- DDR bit0 = 1 (output)
        bus_write(x"00000010", x"00000001");  -- OUT bit0 = 1 (word offset 4)
        wait for CLK_PERIOD;
        check("pin 0 driven high via OUT", gpio(0) = '1');

        bus_write(x"00000010", x"00000000");  -- OUT bit0 = 0
        wait for CLK_PERIOD;
        check("pin 0 driven low via OUT", gpio(0) = '0');

        bus_read(x"00000014", rd);  -- IN (word offset 5) reads back OUT while DDR=output
        check("IN reflects the driven-low pin 0", rd(0) = '0');

        -- Pin 2 as input with a weak pull-up (no external driver on it).
        bus_write(x"00000008", x"00000004");  -- PULL_SEL bit2 = 1 (pull-up)
        bus_write(x"0000000C", x"00000004");  -- PULL_EN  bit2 = 1 (enabled)
        wait for CLK_PERIOD;
        bus_read(x"00000014", rd);  -- IN
        check("pin 2 reads high via weak pull-up", rd(2) = '1');

        -- Same pin, switch the pull to pull-down.
        bus_write(x"00000008", x"00000000");  -- PULL_SEL bit2 = 0 (pull-down)
        wait for CLK_PERIOD;
        bus_read(x"00000014", rd);
        check("pin 2 reads low via weak pull-down", rd(2) = '0');

        -- Pin 3: a real external driver (see the concurrent gpio(3) <= '1'
        -- above) overrides a pull-down configured on the same pin --
        -- proves the pull is genuinely weak, not a second strong driver.
        bus_write(x"00000008", x"00000000");  -- PULL_SEL bit3 = 0 (pull-down)
        bus_write(x"0000000C", x"0000000C");  -- PULL_EN  bits 2,3 = 1
        wait for CLK_PERIOD;
        bus_read(x"00000014", rd);
        check("external driver on pin 3 overrides its pull-down", rd(3) = '1');

        -- CONFIG: plain read/write storage, no defined bits yet.
        bus_write(x"00000000", x"DEADBEEF");
        bus_read(x"00000000", rd);
        check("CONFIG is plain read/write storage", rd = x"DEADBEEF");

        report "Total errors: " & integer'image(errors);
        if errors = 0 then
            report "ALL CHECKS PASSED";
        end if;

        std.env.stop;
        wait;
    end process;

end architecture sim;
