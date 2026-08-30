--------------------------------------------------------------------------------
-- SPDX-License-Identifier: GPL-3.0-or-later
--
-- Company:
-- Engineer: Daniel Kampert
--
-- Create Date: 14.06.2026
-- Design Name: TinyMCU
-- Module Name: tinymcu_sram - tinymcu_sram_rtl
-- Project Name: TinyMCU
-- Description:
--   Data memory (RAM) of the TinyMCU core.
--
-- Dependencies:
--   tinymcu_pkg, tinymcu_sram_generic
--
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library tinymcu;
use tinymcu.tinymcu_pkg.all;

entity tinymcu_sram is
    generic (
        ADDR_WIDTH : integer := 10;

        -- When false, the ram_gen instances below are left out of the
        -- design entirely (no SRAM array, no BRAM rather than merely
        -- shrunk), and this instance instead behaves like any other
        -- unmapped bus target: reads 0, acks the same cycle. Used by
        -- tinymcu_cpu.vhd's u_ramdisk (ENABLE => RAMDISK_ENABLE); u_sram
        -- (kernel/TPA RAM) always leaves this at its default true.
        ENABLE : boolean := true
    );
    port (
        -- Global control
        clk_i : in  std_ulogic;
        rst_i : in  std_ulogic;

        -- Bus interface
        req_i : in  bus_req_t;
        rsp_o : out bus_rsp_t;

        -- Second, independent read-only port for instruction fetch,
        -- see tinymcu_sram_generic.vhd's fetch_addr_i/fetch_dout_o.
        -- Full byte address in (word_t), sliced the same way req_i.addr
        -- is below; whether tinymcu_cpu.vhd ever actually wires this to
        -- anything is gated by its own RAMDISK_ENABLE generic.
        fetch_addr_i : in  word_t;
        fetch_dout_o : out word_t
    );
end entity tinymcu_sram;

architecture tinymcu_sram_rtl of tinymcu_sram is

    signal en : std_ulogic_vector(3 downto 0);

begin

    sram_gen : if ENABLE generate

        process (clk_i)
        begin
            if rising_edge(clk_i) then
                if rst_i = '1' then
                    rsp_o.ack <= '0';
                else
                    rsp_o.ack <= req_i.stb;
                end if;
            end if;
        end process;

        en <= req_i.ben when req_i.stb = '1' else "0000";

        ram_gen : for i in 0 to 3 generate
            ram_inst : entity tinymcu.tinymcu_sram_generic
                generic map (
                    ADDR_WIDTH      => ADDR_WIDTH,
                    DATA_WIDTH      => 8,
                    RAMDISK_LANE    => i
                )
                port map (
                    clk_i        => clk_i,
                    en_i         => en(i),
                    we_i         => req_i.we,
                    addr_i       => req_i.addr(ADDR_WIDTH + 1 downto 2),
                    din_i        => req_i.data(((i * 8) + 7) downto (i * 8)),
                    dout_o       => rsp_o.data(((i * 8) + 7) downto (i * 8)),
                    fetch_addr_i => fetch_addr_i(ADDR_WIDTH + 1 downto 2),
                    fetch_dout_o => fetch_dout_o(((i * 8) + 7) downto (i * 8))
                );
        end generate;

    else generate
        rsp_o.data   <= (others => '0');
        rsp_o.ack    <= req_i.stb;
        rsp_o.err    <= '0';
        fetch_dout_o <= (others => '0');
    end generate;

end architecture tinymcu_sram_rtl;

--------------------------------------------------------------------------------
-- Module Name: tinymcu_ram_subsystem - tinymcu_ram_subsystem_rtl
-- Description:
--   Bundles tinymcu_cpu.vhd's two tinymcu_sram instances. Kernel/TPA
--   RAM (always present) and the RAM disk (sw/cpm-neo/ only, ENABLE =>
--   RAMDISK_ENABLE) behind one entity, so tinymcu_cpu.vhd instantiates
--   a single memory subsystem instead of wiring up two tinymcu_sram
--   instances itself. Both instances share one fetch address (PC always
--   addresses both in parallel; tinymcu_imem.vhd's fetch_mux_gen is what
--   actually decides which of ram_fetch_dout_o/ramdisk_fetch_dout_o, if
--   either, matters for a given PC), so there's exactly one
--   fetch_addr_i, not one per instance.
--
-- Dependencies:
--   tinymcu_pkg, tinymcu_sram
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;

library tinymcu;
use tinymcu.tinymcu_pkg.all;

entity tinymcu_ram_subsystem is
    generic (
        RAM_ADDR_WIDTH     : integer := 14;
        RAMDISK_ADDR_WIDTH : integer := 15;
        RAMDISK_ENABLE : boolean := false
    );
    port (
        clk_i : in  std_ulogic;
        rst_i : in  std_ulogic;

        -- Kernel/TPA RAM bus
        ram_req_i : in  bus_req_t;
        ram_rsp_o : out bus_rsp_t;

        -- RAM disk bus
        ramdisk_req_i : in  bus_req_t;
        ramdisk_rsp_o : out bus_rsp_t;

        -- Shared fetch address
        fetch_addr_i          : in  word_t;
        ram_fetch_dout_o      : out word_t;
        ramdisk_fetch_dout_o  : out word_t
    );
end entity tinymcu_ram_subsystem;

architecture tinymcu_ram_subsystem_rtl of tinymcu_ram_subsystem is
begin

    u_sram : entity tinymcu.tinymcu_sram
        generic map (
            ADDR_WIDTH  => RAM_ADDR_WIDTH
        )
        port map (
            clk_i        => clk_i,
            rst_i        => rst_i,
            req_i        => ram_req_i,
            rsp_o        => ram_rsp_o,
            fetch_addr_i => fetch_addr_i,
            fetch_dout_o => ram_fetch_dout_o
        );

    u_ramdisk : entity tinymcu.tinymcu_sram
        generic map (
            ADDR_WIDTH => RAMDISK_ADDR_WIDTH,
            ENABLE     => RAMDISK_ENABLE
        )
        port map (
            clk_i        => clk_i,
            rst_i        => rst_i,
            req_i        => ramdisk_req_i,
            rsp_o        => ramdisk_rsp_o,
            fetch_addr_i => fetch_addr_i,
            fetch_dout_o => ramdisk_fetch_dout_o
        );

end architecture tinymcu_ram_subsystem_rtl;
