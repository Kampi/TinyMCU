--------------------------------------------------------------------------------
-- SPDX-License-Identifier: GPL-3.0-or-later
--
-- Company:
-- Engineer: Daniel Kampert
--
-- Create Date: 14.06.2026
-- Design Name: TinyMCU
-- Module Name: tinymcu_imem - tinymcu_imem_rtl
-- Project Name: TinyMCU
-- Description:
--   Instruction-fetch arbiter: presents Boot ROM, Flash, (eventually)
--   XIP, and -- only when RAMDISK_ENABLE -- kernel/TPA RAM and the RAM
--   disk (sw/cpm-neo/ only) behind one fetch-side and one data-side
--   port, instead of exposing each of them separately to
--   tinymcu_cpu.vhd. Real RISC-V cores execute out of RAM as a matter
--   of course (an OS kernel loaded into RAM by its own bootloader and
--   run directly from there is the normal case, not a special one);
--   TinyMCU never had this until RAMDISK_ENABLE existed to mark exactly
--   the class of build (sw/cpm-neo/) that actually needs it -- classic
--   sw/*-style fixed ROM programs never do, and get no new logic or
--   timing path when it's false. The data bus side only ever covers the
--   Boot ROM/Flash/XIP window regardless -- RAM/RAM disk have their own
--   data-bus path through tinymcu_addr_decoder.vhd already.
--
-- Dependencies:
--   tinymcu_pkg, tinymcu_imem_bootrom
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library tinymcu;
use tinymcu.tinymcu_pkg.all;

entity tinymcu_imem is
    generic (
        IMEM_ADDR_WIDTH : integer := 13;

        -- See tinymcu_cpu.vhd's own generic of the same name.
        RAMDISK_ENABLE : boolean := false
    );
    port (
        -- Global control
        clk_i : in std_logic;

        -- PC-facing side
        fetch_addr_i : in  word_t;
        fetch_dout_o : out word_t;

        -- Data bus
        data_req_i  : in  bus_req_t;
        data_rsp_o  : out bus_rsp_t;

        -- Fetch-side arbitration with RAM/RAM disk (RAMDISK_ENABLE
        -- only). fetch_pc_if_i selects, not fetch_addr_i: the Boot ROM's
        -- own fetch read below is synchronous/registered, same as
        -- u_sram's/u_ramdisk's, so ram_fetch_dout_i/ramdisk_fetch_dout_i
        -- reflect fetch_addr_i from ONE CYCLE AGO, not this cycle's
        -- value -- fetch_pc_if_i is tinymcu_cpu.vhd's own pc_if, already
        -- a one-cycle-delayed echo of that older value, so it is what's
        -- actually time-aligned with them right now.
        fetch_pc_if_i        : in  word_t;
        ram_fetch_dout_i      : in  word_t;
        ramdisk_fetch_dout_i  : in  word_t
    );
end entity tinymcu_imem;

architecture tinymcu_imem_rtl of tinymcu_imem is
    -- 0 = Boot ROM
    -- 1 = Flash (Not implemented yet)
    -- 2 = XIP (Not implemented yet)
    constant BUS_MEMBERS : integer := 1;

    -- Mirrors tinymcu_addr_decoder.vhd's own local RAMDISK_TOP_BYTE
    -- constant (deliberately not shared via tinymcu_pkg.vhd -- RAM disk
    -- addressing is a sw/cpm-neo/-specific concern, see that file's own
    -- comment). Used only by fetch_mux_gen below.
    constant RAMDISK_TOP_BYTE : std_ulogic_vector(7 downto 0) := x"03";

    type dout_t is array (BUS_MEMBERS - 1 downto 0) of word_t;

    signal fetch_sel    : std_ulogic_vector(BUS_MEMBERS - 1 downto 0);
    signal data_sel     : std_ulogic_vector(BUS_MEMBERS - 1 downto 0);

    signal fetch_dout   : dout_t;
    signal data_dout    : dout_t;

    signal int_fetch    : word_t;
    signal int_data     : word_t;

begin

    u_imem : entity tinymcu.tinymcu_imem_bootrom
        generic map (ADDR_WIDTH => IMEM_ADDR_WIDTH)
        port map (
            clk_i        => clk_i,
            fetch_addr_i => fetch_addr_i,
            fetch_dout_o => fetch_dout(0),
            data_addr_i  => data_req_i.addr,
            data_dout_o  => data_dout(0)
        );

    ----------------------------------------------------------------------
    -- Select the instruction fetch target within THIS entity's own
    -- members (Boot ROM/Flash/XIP) -- unrelated to fetch_mux_gen below,
    -- which arbitrates between this result and RAM/RAM disk.
    ----------------------------------------------------------------------
    fetch_sel(0) <= '1' when unsigned(fetch_addr_i(31 downto IMEM_ADDR_WIDTH + 2)) = 0 else '0';
    fetch : process (fetch_dout, fetch_sel)
        variable fetch : word_t;
    begin
        fetch := (others => '0');

        for i in 0 to BUS_MEMBERS - 1 loop
            if fetch_sel(i) = '1' then
                fetch := fetch_dout(i);
            end if;
        end loop;

        int_fetch <= fetch;
    end process;

    ----------------------------------------------------------------------
    -- Fetch-side arbitration with RAM/RAM disk (RAMDISK_ENABLE only)
    --
    -- When false, fetch_dout_o is wired straight from int_fetch, byte-
    -- identical to this entity's behavior before RAMDISK_ENABLE existed
    -- -- classic builds get no new logic, no new timing path, and no
    -- ability to run code out of RAM at all, on purpose (see
    -- tinymcu_cpu.vhd's own RAMDISK_ENABLE comment). When true, PC
    -- addresses outside this entity's own window (int_fetch would
    -- already read 0 for those -- see fetch_sel above) fall through to
    -- whichever of RAM/RAM disk fetch_pc_if_i's top byte actually
    -- matches.
    ----------------------------------------------------------------------
    fetch_mux_gen : if RAMDISK_ENABLE generate
        process (fetch_pc_if_i, int_fetch, ram_fetch_dout_i, ramdisk_fetch_dout_i)
        begin
            if fetch_pc_if_i(31 downto 24) = RAM_BASE(31 downto 24) then
                fetch_dout_o <= ram_fetch_dout_i;
            elsif fetch_pc_if_i(31 downto 24) = RAMDISK_TOP_BYTE then
                fetch_dout_o <= ramdisk_fetch_dout_i;
            else
                fetch_dout_o <= int_fetch;
            end if;
        end process;
    else generate
        fetch_dout_o <= int_fetch;
    end generate;

    ----------------------------------------------------------------------
    -- Select the data target
    ----------------------------------------------------------------------
    data_sel(0) <= '1' when unsigned(data_req_i.addr(31 downto IMEM_ADDR_WIDTH + 2)) = 0 else '0';
    data : process (data_dout, data_sel)
        variable data  : word_t;
    begin
        data  := (others => '0');

        for i in 0 to BUS_MEMBERS - 1 loop
            if data_sel(i) = '1' then
                data  := data_dout(i);
            end if;
        end loop;

        int_data  <= data;
    end process;

    data_rsp_o.data <= int_data;
    data_rsp_o.err  <= '0' when ((unsigned(fetch_sel) /= 0) or (unsigned(data_sel) /= 0)) else '1';


    ----------------------------------------------------------------------
    -- Bus ackknowledge
    ----------------------------------------------------------------------
    process (clk_i)
    begin
        if rising_edge(clk_i) then
            data_rsp_o.ack <= data_req_i.stb;
        end if;
    end process;

end architecture tinymcu_imem_rtl;
