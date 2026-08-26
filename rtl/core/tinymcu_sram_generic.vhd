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
        DATA_WIDTH : integer := 32
    );
    port (
        -- Global control
        clk_i   : in  std_ulogic;
        en_i    : in  std_ulogic;

        -- Word-addressed read/write port
        addr_i  : in  std_ulogic_vector((ADDR_WIDTH - 1) downto 0);
        din_i   : in  std_ulogic_vector((DATA_WIDTH - 1) downto 0);
        we_i    : in  std_ulogic;
        dout_o  : out std_ulogic_vector((DATA_WIDTH - 1) downto 0)
    );
end entity tinymcu_sram_generic;

architecture tinymcu_sram_generic_rtl of tinymcu_sram_generic is

    type mem_array_t is array (((2 ** ADDR_WIDTH) - 1) downto 0) of std_ulogic_vector((DATA_WIDTH - 1) downto 0);

    signal mem : mem_array_t := (others => (others => '0'));

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
        end if;
    end process;

end architecture tinymcu_sram_generic_rtl;
