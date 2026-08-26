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
--   multiplexer (see there for how fetch/data traffic gets routed here).
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
        ADDR_WIDTH  : integer := 10
    );
    port (
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
        constant PROGRAM : mem_array_t(0 to 40) := (
            0  => x"00500093", -- 0x00: addi x1, x0, 5
            1  => x"00A00113", -- 0x04: addi x2, x0, 10
            2  => x"002081B3", -- 0x08: add  x3, x1, x2
            3  => x"40110233", -- 0x0c: sub  x4, x2, x1
            4  => x"02000AB7", -- 0x10: lui  x21, 0x02000  (RAM base 0x02000000)
            5  => x"003AA023", -- 0x14: sw   x3, 0(x21)
            6  => x"000AA283", -- 0x18: lw   x5, 0(x21)
            7  => x"00408463", -- 0x1c: beq  x1, x4, +8
            8  => x"06F00313", -- 0x20: addi x6, x0, 111  (skipped)
            9  => x"02A00393", -- 0x24: addi x7, x0, 42
            10 => x"00001437", -- 0x28: lui  x8, 0x1
            11 => x"008004EF", -- 0x2c: jal  x9, +8
            12 => x"3E700513", -- 0x30: addi x10, x0, 999 (skipped)
            13 => x"00108093", -- 0x34: addi x1, x1, 1
            14 => x"03C00593", -- 0x38: addi x11, x0, 0x3c
            15 => x"00858667", -- 0x3c: jalr x12, x11, 8
            16 => x"30900693", -- 0x40: addi x13, x0, 777 (skipped)
            17 => x"03700713", -- 0x44: addi x14, x0, 55  (landing point)
            18 => x"00001797", -- 0x48: auipc x15, 1
            19 => x"0AA00813", -- 0x4c: addi x16, x0, 0xAA
            20 => x"010A8223", -- 0x50: sb   x16, 4(x21)
            21 => x"FFF00893", -- 0x54: addi x17, x0, -1
            22 => x"011A82A3", -- 0x58: sb   x17, 5(x21)
            23 => x"004AA903", -- 0x5c: lw   x18, 4(x21)
            24 => x"3CD00993", -- 0x60: addi x19, x0, 0x3CD
            25 => x"013A9423", -- 0x64: sh   x19, 8(x21)
            26 => x"008AAA03", -- 0x68: lw   x20, 8(x21)
            27 => x"12300B13", -- 0x6c: addi x22, x0, 0x123
            28 => x"340B1BF3", -- 0x70: csrrw x23, mscratch, x22
            29 => x"34001C73", -- 0x74: csrrw x24, mscratch, x0
            30 => x"0F000C93", -- 0x78: addi x25, x0, 0xF0
            31 => x"340CAD73", -- 0x7c: csrrs x26, mscratch, x25
            32 => x"34002DF3", -- 0x80: csrrs x27, mscratch, x0
            33 => x"03000E13", -- 0x84: addi x28, x0, 0x30
            34 => x"340E3EF3", -- 0x88: csrrc x29, mscratch, x28
            35 => x"34003F73", -- 0x8c: csrrc x30, mscratch, x0
            36 => x"3402DFF3", -- 0x90: csrrwi x31, mscratch, 5
            37 => x"F1109B73", -- 0x94: csrrw x22, mvendorid, x1  (read-only, write ignored)
            38 => x"F1209CF3", -- 0x98: csrrw x25, marchid, x1  (read-only, write ignored)
            39 => x"F1309E73", -- 0x9c: csrrw x28, mimpid, x1  (read-only, write ignored)
            40 => x"0000006F" -- 0xa0: jal  x0, 0 (halt)
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

    fetch_dout_o <= mem(to_integer(unsigned(fetch_addr_i(ADDR_WIDTH + 1 downto 2))));
    data_dout_o <= mem(to_integer(unsigned(data_addr_i(ADDR_WIDTH + 1 downto 2))));

end architecture tinymcu_imem_bootrom_rtl;
