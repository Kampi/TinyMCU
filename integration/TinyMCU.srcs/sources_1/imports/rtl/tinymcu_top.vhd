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
-- Description: Simple top file for Vivado to implement the TinyMCU into a FPGA.

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
        IMEM_ADDR_WIDTH    : integer := 13;
        RAM_ADDR_WIDTH     : integer := 14;
        RAMDISK_ENABLE     : boolean := false;
        RAMDISK_ADDR_WIDTH : integer := 15
    );
    port (
        -- Global control
        clk_i       : in std_logic;
        rst_i       : in std_logic;

        -- GPIO ports
        gpio_port   : inout std_logic_vector(3 downto 0);

        -- UART
        uart_tx_o   : out std_logic;
        uart_rx_i   : in  std_logic
    );
end entity tinymcu_top;

architecture tinymcu_top_rtl of tinymcu_top is

    component Clock is
        port (
            ClockIn     : in  std_logic;
            ILA_Clock   : out std_logic;
            Locked      : out std_logic;
            MCU_Clock   : out std_logic;
            Reset       : in  std_logic
        );
    end component Clock;

    signal Locked       : std_logic;
    signal IRQ          : std_logic := '0';
    signal MCU_Clock    : std_logic;
    signal ILA_Clock    : std_logic;
    signal CTS          : std_logic;
    signal RTS          : std_logic;
    signal GPIO_Out     : std_logic_vector(31 downto 0);
    signal debug_regs   : reg_array_t;

    -- Holds the design in reset until the MMCM has locked (not just while
    -- rst_i is asserted), and releases it synchronously to ClockOut via a
    -- 2-flop synchronizer so the release edge can never be metastable in
    -- that clock domain. Async assert.
    signal Reset_Async    : std_logic;
    signal Reset_Sync     : std_logic_vector(1 downto 0) := (others => '1');
    signal System_Reset   : std_logic;

begin

    u_clock: component Clock
         port map (
            ClockIn   => clk_i,
            MCU_Clock => MCU_Clock,
            Reset     => rst_i,
            Locked    => Locked,
            ILA_Clock => ILA_Clock
        );

    Reset_Async <= rst_i and not Locked;
    System_Reset <= Reset_Sync(1);

    sync_rst : process (MCU_Clock, Reset_Async)
    begin
        if Reset_Async = '1' then
            Reset_Sync <= (others => '1');
        elsif rising_edge(MCU_Clock) then
            Reset_Sync <= Reset_Sync(0) & '0';
        end if;
    end process sync_rst;

    u_cpu : entity tinymcu.tinymcu_cpu
        generic map (
            IMEM_ADDR_WIDTH    => IMEM_ADDR_WIDTH,
            RAM_ADDR_WIDTH     => RAM_ADDR_WIDTH,
            RAMDISK_ENABLE     => RAMDISK_ENABLE,
            RAMDISK_ADDR_WIDTH => RAMDISK_ADDR_WIDTH,
            TRACE_ENABLE       => false
        )
        port map (
            clk_i           => MCU_Clock,
            rst_i           => System_Reset,
            ext_irq_i       => IRQ,
            gpio_port       => GPIO_Out,
            uart_tx_o       => uart_tx_o,
            uart_rx_i       => uart_rx_i,
            uart_rts_o      => RTS,
            uart_cts_i      => CTS,
            debug_regs_o    => debug_regs
        );

        -- Bidirectional pass-through for the 4 physical pins: GPIO_Out is a
        -- resolved signal, so both directions can drive it concurrently.
        gpio_port            <= GPIO_Out(3 downto 0);
        GPIO_Out(3 downto 0) <= gpio_port;

end architecture tinymcu_top_rtl;
