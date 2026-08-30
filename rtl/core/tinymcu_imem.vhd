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
--   Instruction-fetch arbiter: presents Boot ROM, and, only when the
--   matching generic is set, kernel/TPA RAM + the RAM disk
--   (RAMDISK_ENABLE, sw/cpm-neo/ only) and XIP flash (XIP_ENABLE)
--   behind one fetch-side and one data-side port, instead of exposing
--   each of them separately to tinymcu_cpu.vhd.
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
        RAMDISK_ENABLE  : boolean := false;
        XIP_ENABLE      : boolean := false
    );
    port (
        -- Global control
        clk_i                   : in std_logic;

        -- PC-facing side
        fetch_addr_i            : in  word_t;
        fetch_dout_o            : out word_t;

        -- '1' while an in-flight fetch targets the XIP flash window and isn't ready yet (XIP_ENABLE only).
        fetch_stall_o           : out std_ulogic;

        -- Data bus
        data_req_i              : in  bus_req_t;
        data_rsp_o              : out bus_rsp_t;

        -- Fetch-side arbitration with RAM/RAM disk (RAMDISK_ENABLE only).
        fetch_pc_if_i           : in  word_t;
        ram_fetch_dout_i        : in  word_t;
        ramdisk_fetch_dout_i    : in  word_t;

        -- Fetch-side arbitration with XIP (XIP_ENABLE only). 
        xip_fetch_dout_i        : in word_t;
        xip_fetch_ready_i       : in std_ulogic
    );
end entity tinymcu_imem;

architecture tinymcu_imem_rtl of tinymcu_imem is
    -- 0 = Boot ROM
    constant BUS_MEMBERS : integer := 1;

    type dout_t is array (BUS_MEMBERS - 1 downto 0) of word_t;

    signal fetch_sel            : std_ulogic_vector(BUS_MEMBERS - 1 downto 0);
    signal data_sel             : std_ulogic_vector(BUS_MEMBERS - 1 downto 0);

    signal fetch_dout           : dout_t;
    signal data_dout            : dout_t;

    signal int_fetch            : word_t;
    signal int_data             : word_t;

    signal in_ram_window        : std_ulogic;
    signal in_ramdisk_window    : std_ulogic;
    signal in_xip_window        : std_ulogic;

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
    -- Select the instruction fetch target within this entity's own
    -- members (Boot ROM).
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
    -- Fetch-side arbitration with RAM/RAM disk/XIP
    ----------------------------------------------------------------------
    in_ram_window     <= '1' when (unsigned(fetch_pc_if_i) >= unsigned(RAM_BASE) and
                                   unsigned(fetch_pc_if_i) < unsigned(RAM_END))
                          else '0';

    in_ramdisk_window <= '1' when (unsigned(fetch_pc_if_i) >= unsigned(RAMDISK_BASE) and
                                   unsigned(fetch_pc_if_i) < unsigned(RAMDISK_END))
                          else '0';

    in_xip_window     <= '1' when (unsigned(fetch_pc_if_i) >= unsigned(XIP_FLASH_BASE) and
                                   unsigned(fetch_pc_if_i) < unsigned(XIP_FLASH_END))
                          else '0';

    fetch_mux_gen : if (RAMDISK_ENABLE or XIP_ENABLE) generate
        process (fetch_pc_if_i, int_fetch, ram_fetch_dout_i, ramdisk_fetch_dout_i,
                  in_ram_window, in_ramdisk_window, in_xip_window, xip_fetch_dout_i)
        begin
            if RAMDISK_ENABLE and in_ram_window = '1' then
                fetch_dout_o <= ram_fetch_dout_i;
            elsif RAMDISK_ENABLE and in_ramdisk_window = '1' then
                fetch_dout_o <= ramdisk_fetch_dout_i;
            elsif XIP_ENABLE and in_xip_window = '1' then
                fetch_dout_o <= xip_fetch_dout_i;
            else
                fetch_dout_o <= int_fetch;
            end if;
        end process;
    else generate
        fetch_dout_o <= int_fetch;
    end generate;

    fetch_stall_gen : if XIP_ENABLE generate
        fetch_stall_o <= '1' when (in_xip_window = '1' and xip_fetch_ready_i = '0') else '0';
    else generate
        fetch_stall_o <= '0';
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
