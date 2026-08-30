--------------------------------------------------------------------------------
-- SPDX-License-Identifier: GPL-3.0-or-later
--
-- Company:
-- Engineer: Daniel Kampert
--
-- Create Date: 30.08.2026
-- Design Name: TinyMCU
-- Module Name: tb_xip_cpu - sim
-- Project Name: TinyMCU
-- Description:
--   Runs the XIP controller through the full CPU pipeline (tinymcu_cpu),
--   not just the standalone unit (see sim/core/tinymcu_tb_xip.vhd for
--   that). The CPU boots from the Boot ROM, whose program
--   (scripts/sim/asm_xip.py) configures tinymcu_imem_xip.vhd's CONFIG
--   register and jumps into the XIP flash window; from there, every
--   fetch goes out over the simulated SPI bus below to FLASH_PROGRAM, a
--   second, short program standing in for a real external flash chip's
--   content.
--
--   Register checks are hardwired to both programs; see
--   scripts/sim/asm_xip.py's header for the Boot ROM side and
--   FLASH_PROGRAM below for the flash side.
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

entity tb_xip_cpu is
end entity tb_xip_cpu;

architecture sim of tb_xip_cpu is

    constant CLK_PERIOD : time := 10 ns;

    constant OPCODE_READ : std_ulogic_vector(7 downto 0) := x"03";

    -- Simulated external SPI flash content, fetched entirely over the
    -- XIP bus once the Boot ROM program (scripts/sim/asm_xip.py) jumps
    -- to XIP_FLASH_BASE. Hand-encoded the same way asm_div.py/
    -- asm_mult.py's target programs are, see this file's header
    -- comment.
    --   0x008000: addi x10, x0, 0xAA
    --   0x008004: addi x11, x0, 0x55
    --   0x008008: add  x12, x10, x11  (0xFF)
    --   0x00800C: jal  x0, 0 (halt)
    type flash_mem_t is array (0 to 3) of std_ulogic_vector(31 downto 0);
    constant FLASH_PROGRAM : flash_mem_t := (
        0 => x"0AA00513",
        1 => x"05500593",
        2 => x"00B50633",
        3 => x"0000006F"
    );

    signal clk : std_ulogic := '0';
    signal rst : std_ulogic := '1';

    signal dbg_regs : reg_array_t;

    signal miso : std_logic := '1';
    signal sclk : std_logic;
    signal ss_n : std_logic;
    signal mosi : std_logic;

begin

    clk <= not clk after CLK_PERIOD / 2;

    dut : entity tinymcu.tinymcu_cpu
        generic map (
            IMEM_ADDR_WIDTH => 13,
            RAM_ADDR_WIDTH  => 8,
            XIP_ENABLE      => true
        )
        port map (
            clk_i        => clk,
            rst_i        => rst,
            ext_irq_i    => '0',
            gpio_port    => open,
            debug_regs_o => dbg_regs,
            xip_miso_i   => miso,
            xip_sclk_o   => sclk,
            xip_ss_n_o   => ss_n,
            xip_mosi_o   => mosi
        );

    ----------------------------------------------------------------------
    -- Simulated SPI NOR flash, read-only (opcode 0x03 only; the CPU
    -- only ever fetches instructions over XIP here, it never writes).
    -- Trimmed down from sim/core/tinymcu_tb_xip.vhd's own flash model,
    -- which also supports Page Program for its write-engine tests.
    ----------------------------------------------------------------------
    flash_model : process
        variable header : std_ulogic_vector(31 downto 0);
        variable idx    : integer;
        variable rdata  : std_ulogic_vector(31 downto 0);
    begin
        loop
            wait until falling_edge(ss_n);

            header := (others => '0');
            for i in 0 to 31 loop
                wait until rising_edge(sclk);
                header := header(30 downto 0) & mosi;
            end loop;

            idx := (to_integer(unsigned(header(23 downto 0))) -
                    to_integer(unsigned(XIP_FLASH_BASE(23 downto 0)))) / 4;

            -- Sent low-address-byte first, matching tinymcu_imem_xip.vhd's
            -- read-engine reassembly (address+0 = the word's low byte,
            -- see that file's header comment), so FLASH_PROGRAM's
            -- entries can stay written as the plain instruction word,
            -- byte-reversed only here for the wire.
            if header(31 downto 24) = OPCODE_READ and idx >= 0 and idx <= FLASH_PROGRAM'high then
                rdata := FLASH_PROGRAM(idx)(7 downto 0) & FLASH_PROGRAM(idx)(15 downto 8) &
                         FLASH_PROGRAM(idx)(23 downto 16) & FLASH_PROGRAM(idx)(31 downto 24);
            else
                rdata := (others => '0');
            end if;

            for i in 0 to 31 loop
                wait until falling_edge(sclk);
                miso  <= rdata(31);
                rdata := rdata(30 downto 0) & '0';
            end loop;

            wait until rising_edge(ss_n);
            miso <= '1';
        end loop;
    end process;

    stim : process
        variable errors : integer := 0;
    begin
        rst <= '1';
        wait for CLK_PERIOD * 3;
        rst <= '0';

        -- Boot program (6 fast Boot-ROM instructions) + 4 XIP fetches,
        -- each a full 64-bit opcode+addr+data transfer at CLKDIV=0
        -- (~1300 ns apiece, see sim/core/tinymcu_tb_xip.vhd's own
        -- timing) -> generous margin.
        wait for 8000 ns;

        check("x10 (0xAA, first flash-fetched instruction)", dbg_regs(10), x"000000AA", errors);
        check("x11 (0x55, second flash-fetched instruction)", dbg_regs(11), x"00000055", errors);
        check("x12 (0xAA+0x55=0xFF, computed after two XIP fetches)", dbg_regs(12), x"000000FF", errors);

        report "Total errors: " & integer'image(errors);
        if errors = 0 then
            report "ALL CHECKS PASSED";
        end if;

        std.env.stop;
        wait;
    end process;

end architecture sim;
