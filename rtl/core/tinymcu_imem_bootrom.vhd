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
        constant PROGRAM : mem_array_t(0 to 145) := (
            0   => x"02000197", -- 0x0000
            1   => x"00018193", -- 0x0004
            2   => x"02000117", -- 0x0008
            3   => x"3F810113", -- 0x000C
            4   => x"02000297", -- 0x0010
            5   => x"FF028293", -- 0x0014
            6   => x"02000317", -- 0x0018
            7   => x"FE830313", -- 0x001C
            8   => x"0062D863", -- 0x0020
            9   => x"0002A023", -- 0x0024
            10  => x"00428293", -- 0x0028
            11  => x"FF5FF06F", -- 0x002C
            12  => x"00000297", -- 0x0030
            13  => x"21628293", -- 0x0034
            14  => x"02000317", -- 0x0038
            15  => x"FC830313", -- 0x003C
            16  => x"02000397", -- 0x0040
            17  => x"FC038393", -- 0x0044
            18  => x"00735C63", -- 0x0048
            19  => x"0002AE03", -- 0x004C
            20  => x"01C32023", -- 0x0050
            21  => x"00428293", -- 0x0054
            22  => x"00430313", -- 0x0058
            23  => x"FEDFF06F", -- 0x005C
            24  => x"00000097", -- 0x0060
            25  => x"00C080E7", -- 0x0064
            26  => x"0000006F", -- 0x0068
            27  => x"FF010113", -- 0x006C
            28  => x"00000693", -- 0x0070
            29  => x"00000613", -- 0x0074
            30  => x"00000593", -- 0x0078
            31  => x"68300513", -- 0x007C
            32  => x"00112623", -- 0x0080
            33  => x"00812423", -- 0x0084
            34  => x"00912223", -- 0x0088
            35  => x"00000097", -- 0x008C
            36  => x"0B8080E7", -- 0x0090
            37  => x"00000097", -- 0x0094
            38  => x"060080E7", -- 0x0098
            39  => x"00700513", -- 0x009C
            40  => x"00000097", -- 0x00A0
            41  => x"03C080E7", -- 0x00A4
            42  => x"00004437", -- 0x00A8
            43  => x"000007B7", -- 0x00AC
            44  => x"D0840413", -- 0x00B0
            45  => x"23878493", -- 0x00B4
            46  => x"00000097", -- 0x00B8
            47  => x"030080E7", -- 0x00BC
            48  => x"FEA47CE3", -- 0x00C0
            49  => x"00000097", -- 0x00C4
            50  => x"030080E7", -- 0x00C8
            51  => x"00048513", -- 0x00CC
            52  => x"00000097", -- 0x00D0
            53  => x"0A8080E7", -- 0x00D4
            54  => x"FE1FF06F", -- 0x00D8
            55  => x"040007B7", -- 0x00DC
            56  => x"10A7A023", -- 0x00E0
            57  => x"00008067", -- 0x00E4
            58  => x"040007B7", -- 0x00E8
            59  => x"10C7A503", -- 0x00EC
            60  => x"00008067", -- 0x00F0
            61  => x"040007B7", -- 0x00F4
            62  => x"1007A623", -- 0x00F8
            63  => x"00008067", -- 0x00FC
            64  => x"040007B7", -- 0x0100
            65  => x"10A7A823", -- 0x0104
            66  => x"00008067", -- 0x0108
            67  => x"040007B7", -- 0x010C
            68  => x"00100713", -- 0x0110
            69  => x"10E7A223", -- 0x0114
            70  => x"00008067", -- 0x0118
            71  => x"040007B7", -- 0x011C
            72  => x"1007A223", -- 0x0120
            73  => x"00008067", -- 0x0124
            74  => x"040007B7", -- 0x0128
            75  => x"1087A503", -- 0x012C
            76  => x"00157513", -- 0x0130
            77  => x"00008067", -- 0x0134
            78  => x"040007B7", -- 0x0138
            79  => x"1007A423", -- 0x013C
            80  => x"00008067", -- 0x0140
            81  => x"00D66633", -- 0x0144
            82  => x"040007B7", -- 0x0148
            83  => x"00B66633", -- 0x014C
            84  => x"20C7A023", -- 0x0150
            85  => x"20A7A223", -- 0x0154
            86  => x"00008067", -- 0x0158
            87  => x"040007B7", -- 0x015C
            88  => x"20078793", -- 0x0160
            89  => x"0087A703", -- 0x0164
            90  => x"00177713", -- 0x0168
            91  => x"FE071CE3", -- 0x016C
            92  => x"00A7A623", -- 0x0170
            93  => x"00008067", -- 0x0174
            94  => x"FF010113", -- 0x0178
            95  => x"00812423", -- 0x017C
            96  => x"00112623", -- 0x0180
            97  => x"00050413", -- 0x0184
            98  => x"00044503", -- 0x0188
            99  => x"00051A63", -- 0x018C
            100 => x"00C12083", -- 0x0190
            101 => x"00812403", -- 0x0194
            102 => x"01010113", -- 0x0198
            103 => x"00008067", -- 0x019C
            104 => x"00000097", -- 0x01A0
            105 => x"FBC080E7", -- 0x01A4
            106 => x"00140413", -- 0x01A8
            107 => x"FDDFF06F", -- 0x01AC
            108 => x"040007B7", -- 0x01B0
            109 => x"2087A503", -- 0x01B4
            110 => x"00257513", -- 0x01B8
            111 => x"00008067", -- 0x01BC
            112 => x"040007B7", -- 0x01C0
            113 => x"2087A503", -- 0x01C4
            114 => x"00457513", -- 0x01C8
            115 => x"00008067", -- 0x01CC
            116 => x"040007B7", -- 0x01D0
            117 => x"20078793", -- 0x01D4
            118 => x"0087A703", -- 0x01D8
            119 => x"00277713", -- 0x01DC
            120 => x"FE070CE3", -- 0x01E0
            121 => x"0107A503", -- 0x01E4
            122 => x"00008067", -- 0x01E8
            123 => x"040007B7", -- 0x01EC
            124 => x"2147A703", -- 0x01F0
            125 => x"00176713", -- 0x01F4
            126 => x"20E7AA23", -- 0x01F8
            127 => x"00008067", -- 0x01FC
            128 => x"040007B7", -- 0x0200
            129 => x"2147A703", -- 0x0204
            130 => x"FFE77713", -- 0x0208
            131 => x"20E7AA23", -- 0x020C
            132 => x"00008067", -- 0x0210
            133 => x"040007B7", -- 0x0214
            134 => x"2187A503", -- 0x0218
            135 => x"00157513", -- 0x021C
            136 => x"00008067", -- 0x0220
            137 => x"040007B7", -- 0x0224
            138 => x"2187A703", -- 0x0228
            139 => x"FFE77713", -- 0x022C
            140 => x"20E7AC23", -- 0x0230
            141 => x"00008067", -- 0x0234
            142 => x"6C6C6548", -- 0x0238
            143 => x"6F57206F", -- 0x023C
            144 => x"0D646C72", -- 0x0240
            145 => x"0000000A" -- 0x0244
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
