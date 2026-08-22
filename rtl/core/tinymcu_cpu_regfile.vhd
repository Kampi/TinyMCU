--------------------------------------------------------------------------------
-- SPDX-License-Identifier: GPL-3.0-or-later
--
-- Company:
-- Engineer: Daniel Kampert
--
-- Create Date: 14.06.2026
-- Design Name: TinyMCU
-- Module Name: tinymcu_cpu_regfile - tinymcu_cpu_regfile_rtl
-- Project Name: TinyMCU
-- Description:
--   32 x 32-bit RISC-V register file. x0 is hardwired to zero. Reads are
--   asynchronous (combinational), writes are synchronous to the rising
--   clock edge. Since exactly one instruction reads and writes the
--   register file per cycle in the 2-stage core, no forwarding is needed.
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

entity tinymcu_cpu_regfile is
    port (
        -- Global control
        clk_i           : in  std_ulogic;

        -- Read port 1
        rs1_data_o      : out word_t;
        rs1_addr_i      : in  std_ulogic_vector(4 downto 0);

        -- Read port 2
        rs2_data_o      : out word_t;
        rs2_addr_i      : in  std_ulogic_vector(4 downto 0);

        -- Write port
        we_i            : in  std_ulogic;
        rd_addr_i       : in  std_ulogic_vector(4 downto 0);
        rd_data_i       : in  word_t;

        -- Simulation/debug only; leave unconnected in the FPGA top level.
        debug_regs_o    : out reg_array_t
    );
end entity tinymcu_cpu_regfile;

architecture tinymcu_cpu_regfile_rtl of tinymcu_cpu_regfile is

    signal regs : reg_array_t := (others => (others => '0'));

begin

    rs1_data_o <= regs(to_integer(unsigned(rs1_addr_i)));
    rs2_data_o <= regs(to_integer(unsigned(rs2_addr_i)));
    debug_regs_o <= regs;

    ----------------------------------------------------------------------
    -- Register write
    ----------------------------------------------------------------------
    process (clk_i)
    begin
        if rising_edge(clk_i) then
            if we_i = '1' and rd_addr_i /= "00000" then
                regs(to_integer(unsigned(rd_addr_i))) <= rd_data_i;
            end if;
        end if;
    end process;

end architecture tinymcu_cpu_regfile_rtl;
