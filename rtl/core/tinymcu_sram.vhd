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
--   tinymcu_pkg, tinymcu_sram_generi
--
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library tinymcu;
use tinymcu.tinymcu_pkg.all;

entity tinymcu_sram is
    generic (
        ADDR_WIDTH : integer := 10
    );
    port (
        -- Global control
        clk_i : in  std_ulogic;
        rst_i : in  std_ulogic;

        -- Bus interface
        req_i : in  bus_req_t;
        rsp_o : out bus_rsp_t
    );
end entity tinymcu_sram;

architecture tinymcu_sram_rtl of tinymcu_sram is

    signal en : std_ulogic_vector(3 downto 0);

begin

    rsp_o.ack <= '0' when (rst_i = '1') else req_i.stb;

    en <= req_i.ben when req_i.stb = '1' else "0000";

    ram_gen : for i in 0 to 3 generate
        ram_inst : entity tinymcu.tinymcu_sram_generic
            generic map (
                ADDR_WIDTH => ADDR_WIDTH,
                DATA_WIDTH => 8
            )
            port map (
                clk_i  => clk_i,
                en_i   => en(i),
                we_i   => req_i.we,
                addr_i => req_i.addr(ADDR_WIDTH + 1 downto 2),
                din_i  => req_i.data(((i * 8) + 7) downto (i * 8)),
                dout_o => rsp_o.data(((i * 8) + 7) downto (i * 8))
            );
    end generate;

end architecture tinymcu_sram_rtl;
