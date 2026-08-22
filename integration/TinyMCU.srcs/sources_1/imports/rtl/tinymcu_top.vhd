--------------------------------------------------------------------------------
-- SPDX-License-Identifier: GPL-3.0-or-later
--
-- Company:
-- Engineer: Daniel Kampert
--
-- Create Date: 18.06.2026
-- Design Name: TinyMCU
-- Module Name: tinymcu_top - tinymcu_top_rtl
-- Project Name: TinyMCU
-- Description: Simple top file to implement the TinyMCU into a FPGA.

-- Dependencies:
--   tinymcu_pkg, tinymcu_cpu
--
-- Additional Comments:
--
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;

library tinymcu;
use tinymcu.tinymcu_pkg.all;

entity tinymcu_top is
    generic (
        IMEM_ADDR_WIDTH : integer := 10;
        RAM_ADDR_WIDTH  : integer := 10
    );
    port (
        -- Global control
        clk_i       : in std_logic;
        rst_i       : in std_logic;

        -- GPIO ports
        gpio_port_a : inout std_logic_vector(3 downto 0)
    );
end entity tinymcu_top;

architecture tinymcu_top_rtl of tinymcu_top is

    component Clock is
        port (
            ClockIn     : in std_logic;
            ClockOut    : out std_logic;
            Reset       : in std_logic
        );
    end component Clock;

    signal IRQ          : std_logic := '0';
    signal ClockOut     : std_logic;
    signal GPIO_Out     : std_logic_vector(31 downto 0);
    signal debug_regs   : reg_array_t;

begin

    u_clock: component Clock
         port map (
          ClockIn   => clk_i,
          ClockOut  => ClockOut,
          Reset     => rst_i
        );

    u_cpu : entity tinymcu.tinymcu_cpu
        generic map (
            IMEM_ADDR_WIDTH => IMEM_ADDR_WIDTH,
            RAM_ADDR_WIDTH  => RAM_ADDR_WIDTH,
            TRACE_ENABLE    => false
        )
        port map (
            clk_i           => ClockOut,
            rst_i           => rst_i,
            ext_irq_i       => IRQ,
            gpio_port_a     => GPIO_Out,
            debug_regs_o    => debug_regs
        );

        gpio_port_a <= GPIO_Out(3 downto 0);

end architecture tinymcu_top_rtl;
