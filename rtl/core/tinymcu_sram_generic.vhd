--------------------------------------------------------------------------------
-- SPDX-License-Identifier: GPL-3.0-or-later
--
-- Company:
-- Engineer: Daniel Kampert
--
-- Create Date: 14.06.2026
-- Design Name: TinyMCU
-- Module Name: tinymcu_sram_generic - tinymcu_sram_generic_rtl
-- Project Name: TinyMCU
-- Description:
--   Generic single-port SRAM building block.
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

entity tinymcu_sram_generic is
    generic (
        ADDR_WIDTH : integer := 10;
        DATA_WIDTH : integer := 32;

        -- Selects which DATA_WIDTH-bit slice of the auto-generated DISK
        -- constant's 32-bit words this instance's initial content is
        -- built from. See tinymcu_sram.vhd's ram_gen loop, which passes
        -- RAMDISK_LANE => i for its 4 DATA_WIDTH=8 byte-lane instances.
        RAMDISK_LANE : integer := 0;

        -- Word offset (32-bit words, matching DISK below) the DISK
        -- constant is copied in at, instead of word 0. 0 by default
        -- (matches this instance's own address 0). sw/cpm-neo/'s RAM
        -- disk uses its own dedicated tinymcu_sram instance (see
        -- tinymcu_addr_decoder.vhd's RAMDISK_TOP_BYTE), whose local
        -- address 0 already is TINYMCU_RAMDISK_BASE, so it keeps this at
        -- 0 too.
        RAMDISK_DISK_OFFSET : integer := 0
    );
    port (
        -- Global control
        clk_i       : in  std_ulogic;
        en_i        : in  std_ulogic;

        -- Word-addressed read/write port
        addr_i      : in  std_ulogic_vector((ADDR_WIDTH - 1) downto 0);
        din_i       : in  std_ulogic_vector((DATA_WIDTH - 1) downto 0);
        we_i        : in  std_ulogic;
        dout_o      : out std_ulogic_vector((DATA_WIDTH - 1) downto 0);

        -- Second, independent read-only port for instruction fetch
        fetch_addr_i : in  std_ulogic_vector((ADDR_WIDTH - 1) downto 0);
        fetch_dout_o : out std_ulogic_vector((DATA_WIDTH - 1) downto 0)
    );
end entity tinymcu_sram_generic;

architecture tinymcu_sram_generic_rtl of tinymcu_sram_generic is

    type mem_array_t is array (((2 ** ADDR_WIDTH) - 1) downto 0) of std_ulogic_vector((DATA_WIDTH - 1) downto 0);

    -- Builds this instance's initial contents: every word defaults to 0,
    -- then the auto-generated DISK constant below (see
    -- scripts/cpm_neo_ramdisk2rom.py) is copied in starting at word
    -- RAMDISK_DISK_OFFSET, taking each entry's RAMDISK_LANE-th DATA_WIDTH-bit slice.
    -- DISK is always 32-bit words, shared unchanged across every
    -- instance in tinymcu_sram.vhd's ram_gen loop.
    -- No parameters.
    -- Returns: the full 2**ADDR_WIDTH-word initial memory image, used as
    -- the "mem" signal's initializer below.
    function init_mem return mem_array_t is
        variable m : mem_array_t := (others => (others => '0'));

        -- TINYMCU_DISK_BEGIN (auto-generated, do not edit by hand)
        constant DISK : tinymcu.tinymcu_pkg.mem_array_t(0 to -1) := (others => (others => '0'));
        -- TINYMCU_DISK_END
    begin
        for i in DISK'range loop
            if (i + RAMDISK_DISK_OFFSET) <= m'high then
                m(i + RAMDISK_DISK_OFFSET) := DISK(i)(((RAMDISK_LANE * DATA_WIDTH) + DATA_WIDTH - 1) downto (RAMDISK_LANE * DATA_WIDTH));
            end if;
        end loop;
        return m;
    end function;

    signal mem : mem_array_t := init_mem;

begin

    process (clk_i)
    begin
        if rising_edge(clk_i) then
            if en_i = '1' then
                if we_i = '1' then
                    mem(to_integer(unsigned(addr_i))) <= din_i;
                end if;

                dout_o <= mem(to_integer(unsigned(addr_i)));
            end if;

            fetch_dout_o <= mem(to_integer(unsigned(fetch_addr_i)));
        end if;
    end process;

end architecture tinymcu_sram_generic_rtl;
