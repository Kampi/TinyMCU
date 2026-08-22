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
--   Instruction-memory bus multiplexer: presents Boot ROM, Flash, and
--   (eventually) XIP behind one fetch-side and one data-side port,
--   instead of exposing each of them separately to tinymcu_cpu.vhd.
--
-- Dependencies:
--   tinymcu_pkg, tinymcu_imem_bootro
--
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library tinymcu;
use tinymcu.tinymcu_pkg.all;

entity tinymcu_imem is
    generic (
        IMEM_ADDR_WIDTH : integer := 10
    );
    port (
        -- PC-facing side
        fetch_addr_i : in  word_t;
        fetch_dout_o : out word_t;

        -- Data bus
        data_req_i  : in  bus_req_t;
        data_rsp_o  : out bus_rsp_t
    );
end entity tinymcu_imem;

architecture tinymcu_imem_rtl of tinymcu_imem is
    -- 0 = Boot ROM
    -- 1 = Flash (Not implemented yet)
    -- 2 = XIP (Not implemented yet)
    constant BUS_MEMBERS : integer := 1;

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
            fetch_addr_i => fetch_addr_i,
            fetch_dout_o => fetch_dout(0),
            data_addr_i  => data_req_i.addr,
            data_dout_o  => data_dout(0)
        );

    ----------------------------------------------------------------------
    -- Select the instruction fetch target
    ----------------------------------------------------------------------
    fetch_sel(0) <= '1' when unsigned(fetch_addr_i(31 downto IMEM_ADDR_WIDTH + 2)) = 0 else '0';
    fetch : process (fetch_dout, fetch_sel)
        variable tmp_fetch : word_t;
    begin
        tmp_fetch := (others => '0');

        for i in 0 to BUS_MEMBERS - 1 loop
            if fetch_sel(i) = '1' then
                tmp_fetch := fetch_dout(i);
            end if;
        end loop;

        int_fetch <= tmp_fetch;
    end process;

    fetch_dout_o <= int_fetch;

    ----------------------------------------------------------------------
    -- Select the data target
    ----------------------------------------------------------------------
    data_sel(0) <= '1' when unsigned(data_req_i.addr(31 downto IMEM_ADDR_WIDTH + 2)) = 0 else '0';
    data : process (data_dout, data_sel)
        variable tmp_data  : word_t;
    begin
        tmp_data  := (others => '0');

        for i in 0 to BUS_MEMBERS - 1 loop
            if data_sel(i) = '1' then
                tmp_data  := data_dout(i);
            end if;
        end loop;

        int_data  <= tmp_data;
    end process;

    data_rsp_o.data <= int_data;
    data_rsp_o.ack  <= data_req_i.stb;
    data_rsp_o.err  <= '0' when ((unsigned(fetch_sel) /= 0) or (unsigned(data_sel) /= 0)) else '1';

end architecture tinymcu_imem_rtl;
