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
        constant PROGRAM : mem_array_t(0 to 5) := (
            0 => x"00600093", -- 0x00: addi x1, x0, 6
            1 => x"00700113", -- 0x04: addi x2, x0, 7
            2 => x"022081B3", -- 0x08: mul  x3, x1, x2   (expect 42)
            3 => x"06F00213", -- 0x0c: addi x4, x0, 111  (must land in x4, not be lost/misdirected)
            4 => x"022102B3", -- 0x10: mul  x5, x2, x2   (expect 49; mult right after another instr)
            5 => x"0000006F" -- 0x14: jal  x0, 0 (halt)
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
    -- be) forces Vivado to infer distributed RAM (LUTs) instead of BRAM,
    -- which is fine at 4 KB but a real problem at 32 KB. See tinymcu_cpu.vhd's
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
