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
    signal irq  : std_ulogic;
    signal req  : bus_req_t := BUS_REQ_IDLE;
    signal rsp  : bus_rsp_t;

begin

    clk <= not clk after CLK_PERIOD / 2;

    dut : entity tinymcu.tinymcu_periph_gpio
        port map (
            clk_i => clk,
            rst_i => rst,
            gpio_port => gpio,
            gpio_req_i => req,
            gpio_rsp_o => rsp,
            irq_o => irq
        );

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
    begin
        wait for CLK_PERIOD * 3;
        rst <= '0';
        wait for CLK_PERIOD * 2;

        -- Reset state: all pins input, no pulls, output data 0.
        bus_read(x"00000004", rd);  -- DDR (word offset 1)
        check("DDR resets to all-input (0)", to_integer(unsigned(rd)) = 0, errors);

        -- Pin 0 as output, drive it high then low, observe gpio_port.
        bus_write(x"00000004", x"00000001");  -- DDR bit0 = 1 (output)
        bus_write(x"00000010", x"00000001");  -- OUT bit0 = 1 (word offset 4)
        wait for CLK_PERIOD;
        check("pin 0 driven high via OUT", gpio(0) = '1', errors);

        bus_write(x"00000010", x"00000000");  -- OUT bit0 = 0
        wait for CLK_PERIOD;
        check("pin 0 driven low via OUT", gpio(0) = '0', errors);

        bus_read(x"00000014", rd);  -- IN (word offset 5) reads back OUT while DDR=output
        check("IN reflects the driven-low pin 0", rd(0) = '0', errors);

        -- Pin 2 as input with a weak pull-up (no external driver on it).
        bus_write(x"00000008", x"00000004");  -- PULL_SEL bit2 = 1 (pull-up)
        bus_write(x"0000000C", x"00000004");  -- PULL_EN  bit2 = 1 (enabled)
        wait for CLK_PERIOD;
        bus_read(x"00000014", rd);  -- IN
        check("pin 2 reads high via weak pull-up", rd(2) = '1', errors);

        -- Same pin, switch the pull to pull-down.
        bus_write(x"00000008", x"00000000");  -- PULL_SEL bit2 = 0 (pull-down)
        wait for CLK_PERIOD;
        bus_read(x"00000014", rd);
        check("pin 2 reads low via weak pull-down", rd(2) = '0', errors);

        -- Pin 3: a real external driver (see the concurrent gpio(3) <= '1'
        -- above) overrides a pull-down configured on the same pin,
        -- proving the pull is genuinely weak, not a second strong driver.
        bus_write(x"00000008", x"00000000");  -- PULL_SEL bit3 = 0 (pull-down)
        bus_write(x"0000000C", x"0000000C");  -- PULL_EN  bits 2,3 = 1
        wait for CLK_PERIOD;
        bus_read(x"00000014", rd);
        check("external driver on pin 3 overrides its pull-down", rd(3) = '1', errors);

        -- ---- Interrupts ----

        -- Reset state: INT_CONFIG/INT_STATUS both 0, irq_o low.
        bus_read(x"00000018", rd);  -- INT_CONFIG (word offset 6)
        check("INT_CONFIG resets to 0", to_integer(unsigned(rd)) = 0, errors);
        bus_read(x"0000001C", rd);  -- INT_STATUS (word offset 7)
        check("INT_STATUS resets to 0", to_integer(unsigned(rd)) = 0, errors);
        check("irq_o low with nothing enabled", irq = '0', errors);

        -- Pin 5, per-pin interrupt enabled, global enable (CONFIG bit0) still off.
        bus_write(x"00000018", x"00000020");  -- INT_CONFIG bit5 = 1
        gpio(5) <= '1';
        wait for CLK_PERIOD * 2;
        bus_read(x"0000001C", rd);
        check("edge ignored while global interrupt enable is off", rd(5) = '0', errors);
        check("irq_o stays low while global interrupt enable is off", irq = '0', errors);

        -- Enable the global interrupt too. The level is already settled
        -- (gpio_port_prev caught up during the wait above), so this must
        -- not retrigger on its own.
        bus_write(x"00000000", x"00000001");  -- CONFIG bit0 = 1 (global enable)
        wait for CLK_PERIOD * 2;
        bus_read(x"0000001C", rd);
        check("enabling globally doesn't retrigger an already-settled level", rd(5) = '0', errors);

        -- A real falling edge on pin 5, now with both enables active.
        gpio(5) <= '0';
        wait for CLK_PERIOD * 2;
        bus_read(x"0000001C", rd);
        check("falling edge on an enabled pin sets its status bit", rd(5) = '1', errors);
        check("irq_o goes high", irq = '1', errors);

        -- Pin 6 is not enabled in INT_CONFIG, so its edge must not set a bit.
        gpio(6) <= '1';
        wait for CLK_PERIOD * 2;
        bus_read(x"0000001C", rd);
        check("disabled pin's edge doesn't set its status bit", rd(6) = '0', errors);

        -- Sticky: must not self-clear just because there's no new edge.
        wait for CLK_PERIOD * 5;
        bus_read(x"0000001C", rd);
        check("status bit stays set without a software clear", rd(5) = '1', errors);
        check("irq_o stays high without a software clear", irq = '1', errors);

        -- Software acknowledges by writing INT_STATUS.
        bus_write(x"0000001C", x"00000000");
        wait for CLK_PERIOD;
        bus_read(x"0000001C", rd);
        check("INT_STATUS clears on write", to_integer(unsigned(rd)) = 0, errors);
        check("irq_o drops after clearing", irq = '0', errors);

        -- ---- Debounce (CONFIG bits 15:1) ----

        -- Pin 7 was never driven before this point, so it floats ('Z' ->
        -- 'X' through to_x01). Settle it to a clean, defined '0' while
        -- debounce is still disabled (threshold 0 tracks the raw pad
        -- immediately), *before* raising the threshold below. Otherwise
        -- gpio_debounced(7) would carry that undefined history into the
        -- new threshold instead of starting from a known level.
        gpio(7) <= '0';
        wait for CLK_PERIOD * 2;

        -- Clear CONFIG first (the interrupt block above left bit0 set),
        -- then set a debounce threshold of 4 cycles, global interrupt
        -- enable still on, pin 7 armed.
        bus_write(x"00000000", x"00000009");  -- bits 15:1 = 4, bit0 = 1
        bus_write(x"00000018", x"000000A0");  -- INT_CONFIG bits 5,7 = 1
        bus_write(x"0000001C", x"00000000");  -- clear any stale flags
        wait for CLK_PERIOD * 3;

        -- A glitch shorter than the threshold: pin 7 flips high for only
        -- 2 cycles, well under the 4-cycle requirement, then back low.
        gpio(7) <= '1';
        wait for CLK_PERIOD * 2;
        gpio(7) <= '0';
        wait for CLK_PERIOD * 6;
        bus_read(x"0000001C", rd);
        check("glitch shorter than the debounce threshold is rejected", rd(7) = '0', errors);

        -- A real change held for longer than the threshold.
        gpio(7) <= '1';
        wait for CLK_PERIOD * 6;
        bus_read(x"0000001C", rd);
        check("change held past the debounce threshold sets the flag", rd(7) = '1', errors);

        bus_write(x"0000001C", x"00000000");  -- clear before the next section
        bus_write(x"00000000", x"00000001");  -- back to debounce disabled, global enable on

        -- CONFIG: plain read/write storage outside bits 15:0.
        bus_write(x"00000000", x"DEADBEEF");
        bus_read(x"00000000", rd);
        check("CONFIG is plain read/write storage", rd = x"DEADBEEF", errors);

        report "Total errors: " & integer'image(errors);
        if errors = 0 then
            report "ALL CHECKS PASSED";
        end if;

        std.env.stop;
        wait;
    end process;

end architecture sim;
