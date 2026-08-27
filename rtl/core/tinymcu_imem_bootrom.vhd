--------------------------------------------------------------------------------
-- SPDX-License-Identifier: GPL-3.0-or-later
--
-- Company:
-- Engineer: Daniel Kampert
--
-- Create Date: 14.06.2026
-- Design Name: TinyMCU
-- Module Name: tinymcu_imem_bootrom - tinymcu_imem_bootrom_rtl
-- Project Name: TinyMCU
-- Description:
--   Boot-ROM target for tinymcu_imem.vhd's instruction-memory bus
--   multiplexer.
--
-- Dependencies:
--   tinymcu_pkg
--
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library tinymcu;
use tinymcu.tinymcu_pkg.all;

entity tinymcu_imem_bootrom is
    generic (
        ADDR_WIDTH  : integer := 13
    );
    port (
        clk_i : in std_logic;

        fetch_addr_i : in  word_t;
        fetch_dout_o : out word_t;

        data_addr_i  : in  word_t;
        data_dout_o  : out word_t
    );
end entity tinymcu_imem_bootrom;

architecture tinymcu_imem_bootrom_rtl of tinymcu_imem_bootrom is

    -- Builds the boot ROM's initial contents: every word defaults to NOP_INSTR, then the
    -- auto-generated PROGRAM constant below (see scripts/asm.py / scripts/hex2rom.py) is copied
    -- in starting at word 0.
    -- No parameters.
    -- Returns: the full 2**ADDR_WIDTH-word initial memory image, used as the "mem" signal's
    -- initializer below.
    function init_mem return mem_array_t is
        variable m : mem_array_t(0 to ((2 ** ADDR_WIDTH) - 1)) := (others => NOP_INSTR);

        -- TINYMCU_PROGRAM_BEGIN (auto-generated, do not edit by hand)
        constant PROGRAM : mem_array_t(0 to 17) := (
            0  => x"04000093", -- 0x00: addi x1, x0, 0x40  (handler address)
            1  => x"30509073", -- 0x04: csrrw x0, mtvec, x1
            2  => x"00800113", -- 0x08: addi x2, x0, 8  (MIE bit)
            3  => x"30011073", -- 0x0c: csrrw x0, mstatus, x2  (mstatus.MIE = 1)
            4  => x"000011B7", -- 0x10: lui  x3, 1
            5  => x"80018193", -- 0x14: addi x3, x3, -2048  (x3 = 0x800, MEIE bit)
            6  => x"30419073", -- 0x18: csrrw x0, mie, x3  (mie.MEIE = 1)
            7  => x"00138393", -- 0x1c: loop: addi x7, x7, 1
            8  => x"FFDFF06F", -- 0x20: jal  x0, loop
            9  => x"00000013", -- 0x24: nop (padding)
            10 => x"00000013", -- 0x28: nop (padding)
            11 => x"00000013", -- 0x2c: nop (padding)
            12 => x"00000013", -- 0x30: nop (padding)
            13 => x"00000013", -- 0x34: nop (padding)
            14 => x"00000013", -- 0x38: nop (padding)
            15 => x"00000013", -- 0x3c: nop (padding)
            16 => x"0DE00313", -- 0x40: handler: addi x6, x0, 222  (marker: handler ran)
            17 => x"30200073" -- 0x44: mret
        );
        -- TINYMCU_PROGRAM_END
    begin
        for i in PROGRAM'range loop
            m(i) := PROGRAM(i);
        end loop;
        return m;
    end function;

    signal mem : mem_array_t(0 to ((2 ** ADDR_WIDTH) - 1)) := init_mem;

begin

    -- Registered reads: Xilinx 7-series Block RAM primitives are
    -- synchronous-read only. A combinational read here (as this used to
    -- be) forces Vivado to infer distributed RAM (LUTs) instead of BRAM
    -- -- fine at 4 KB, but a real problem at 32 KB. See tinymcu_cpu.vhd's
    -- "PC and IF/EX pipeline register" for how the resulting one-cycle
    -- fetch latency is accounted for.
    process (clk_i)
    begin
        if rising_edge(clk_i) then
            fetch_dout_o <= mem(to_integer(unsigned(fetch_addr_i(ADDR_WIDTH + 1 downto 2))));
            data_dout_o  <= mem(to_integer(unsigned(data_addr_i(ADDR_WIDTH + 1 downto 2))));
        end if;
    end process;

end architecture tinymcu_imem_bootrom_rtl;
