--------------------------------------------------------------------------------
-- SPDX-License-Identifier: GPL-3.0-or-later
--
-- Company:
-- Engineer: Daniel Kampert
--
-- Create Date: 14.06.2026
-- Design Name: TinyMCU
-- Module Name: tinymcu_addr_decoder - tinymcu_addr_decoder_rtl
-- Project Name: TinyMCU
-- Description:
--   Address range                 Target        Description
--   0x0000_0000 - 0x00FF_FFFF     imem_req_o    Boot ROM + Flash (tinymcu_imem); ROM_BASE and
--                                               FLASH_BASE both fall inside this one window.
--   0x0200_0000 - 0x02FF_FFFF     ram_req_o     RAM (tinymcu_sram); RAM_BASE.
--   0x0400_0000 - 0x04FF_FFFF     periph_req_o  Peripherals (tinymcu_periph.vhd); PERIPHERALS_BASE.
--   Any other address             -             Unmapped: reads as 0
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

entity tinymcu_addr_decoder is
    port (
        -- CPU-facing bus
        cpu_rsp_o   : out bus_rsp_t;
        cpu_req_i   : in  bus_req_t;

        -- RAM-facing bus
        ram_req_o   : out bus_req_t;
        ram_rsp_i   : in  bus_rsp_t;

        -- Instruction memory-facing bus
        imem_req_o  : out bus_req_t;
        imem_rsp_i  : in  bus_rsp_t;

        -- Peripherals-facing bus
        periph_req_o : out bus_req_t;
        periph_rsp_i : in  bus_rsp_t
    );
end entity tinymcu_addr_decoder;

architecture tinymcu_addr_decoder_rtl of tinymcu_addr_decoder is
    -- 0 = RAM
    -- 1 = Instruction memory
    -- 2 = Peripherals
    constant BUS_MEMBERS : integer := 3;

    type port_req_t is array (BUS_MEMBERS - 1 downto 0) of bus_req_t;
    type port_rsp_t is array (BUS_MEMBERS - 1 downto 0) of bus_rsp_t;

    signal port_req : port_req_t;
    signal port_rsp : port_rsp_t;

    signal port_sel : std_ulogic_vector(BUS_MEMBERS - 1 downto 0);

    signal int_rsp : bus_rsp_t;
begin

    port_sel(0) <= '1' when cpu_req_i.addr(31 downto 24) = RAM_BASE(31 downto 24) else '0';
    port_sel(1) <= '1' when cpu_req_i.addr(31 downto 24) = ROM_BASE(31 downto 24) else '0';
    port_sel(2) <= '1' when cpu_req_i.addr(31 downto 24) = PERIPHERALS_BASE(31 downto 24) else '0';

    ram_req_o   <= port_req(0);
    port_rsp(0) <= ram_rsp_i;

    imem_req_o  <= port_req(1);
    port_rsp(1) <= imem_rsp_i;

    periph_req_o <= port_req(2);
    port_rsp(2)  <= periph_rsp_i;

    -- Bus request: every target gets the full request every cycle, but
    -- only the selected one gets a real strobe.
    request : process (cpu_req_i, port_sel)
    begin
        for i in 0 to BUS_MEMBERS - 1 loop
            port_req(i)     <= cpu_req_i;
            port_req(i).stb <= cpu_req_i.stb and port_sel(i);
        end loop;
    end process;

    -- Bus response: mask each target's response by whether it was
    -- actually selected before OR-combining, so an unselected (possibly
    -- undriven) target can never corrupt the result.
    response : process (port_rsp, port_sel)
        variable rsp : bus_rsp_t;
    begin
        rsp := BUS_RSP_IDLE;

        for i in 0 to BUS_MEMBERS - 1 loop
            if port_sel(i) = '1' then
                rsp.data := rsp.data or port_rsp(i).data;
                rsp.ack  := rsp.ack  or port_rsp(i).ack;
            end if;
        end loop;

        int_rsp <= rsp;
    end process;

    cpu_rsp_o.data <= int_rsp.data;
    cpu_rsp_o.ack  <= int_rsp.ack when (unsigned(port_sel) /= 0) else cpu_req_i.stb;
    cpu_rsp_o.err  <= '0' when (unsigned(port_sel) /= 0) else '1';

end architecture tinymcu_addr_decoder_rtl;
