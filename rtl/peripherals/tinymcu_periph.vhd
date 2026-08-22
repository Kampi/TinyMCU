--------------------------------------------------------------------------------
-- SPDX-License-Identifier: GPL-3.0-or-later
--
-- Company:
-- Engineer: Daniel Kampert
--
-- Create Date: 14.06.2026
-- Design Name: TinyMCU
-- Module Name: tinymcu_periph - tinymcu_periph_rtl
-- Project Name: TinyMCU
-- Description:
--   Address range                 Target        Meaning
--   0x0400_0000 - 0x0400_00FF     gpio_req_o    GPIO (tinymcu_periph_gpio); GPIO_BASE.
--   0x0400_0100 - 0x0400_01FF     timer_req_o   Timer (tinymcu_periph_timer); TIMER_BASE.
--   Any other address              -            Unmapped: reads as 0
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

entity tinymcu_periph is
    port (
        -- Address Decoder-facing side
        periph_req_i : in  bus_req_t;
        periph_rsp_o : out bus_rsp_t;

        -- GPIO-facing bus
        gpio_req_o : out bus_req_t;
        gpio_rsp_i : in  bus_rsp_t;

        -- Timer-facing bus
        timer_req_o : out bus_req_t;
        timer_rsp_i : in  bus_rsp_t
    );
end entity tinymcu_periph;

architecture tinymcu_periph_rtl of tinymcu_periph is
    -- 0 = GPIO
    -- 1 = Timer
    constant BUS_MEMBERS : integer := 2;

    type port_req_t is array (BUS_MEMBERS - 1 downto 0) of bus_req_t;
    type port_rsp_t is array (BUS_MEMBERS - 1 downto 0) of bus_rsp_t;

    signal port_req : port_req_t;
    signal port_rsp : port_rsp_t;

    signal port_sel : std_ulogic_vector(BUS_MEMBERS - 1 downto 0);

    signal int_rsp  : bus_rsp_t;
begin

    port_sel(0) <= '1' when periph_req_i.addr(31 downto 8) = GPIO_BASE(31 downto 8)    else '0';
    port_sel(1) <= '1' when periph_req_i.addr(31 downto 8) = TIMER_BASE(31 downto 8) else '0';

    gpio_req_o  <= port_req(0);
    port_rsp(0) <= gpio_rsp_i;

    timer_req_o <= port_req(1);
    port_rsp(1) <= timer_rsp_i;

    -- Bus request: every target gets the full request every cycle, but
    -- only the selected one gets a real strobe.
    request : process (periph_req_i, port_sel)
    begin
        for i in 0 to BUS_MEMBERS - 1 loop
            port_req(i)     <= periph_req_i;
            port_req(i).stb <= periph_req_i.stb and port_sel(i);
        end loop;
    end process;

    -- Bus response: mask each target's response by whether it was
    -- actually selected before OR-combining, so an unselected (possibly
    -- undriven) target can never corrupt the result.
    response : process (port_rsp, port_sel)
        variable tmp_v : bus_rsp_t;
    begin
        tmp_v := BUS_RSP_IDLE;

        for i in 0 to BUS_MEMBERS - 1 loop
            if port_sel(i) = '1' then
                tmp_v.data := tmp_v.data or port_rsp(i).data;
                tmp_v.ack  := tmp_v.ack  or port_rsp(i).ack;
            end if;
        end loop;

        int_rsp <= tmp_v;
    end process;

    periph_rsp_o.data <= int_rsp.data;
    periph_rsp_o.ack  <= int_rsp.ack when (unsigned(port_sel) /= 0) else periph_req_i.stb;
    periph_rsp_o.err  <= '0' when (unsigned(port_sel) /= 0) else '1';

end architecture tinymcu_periph_rtl;
