--------------------------------------------------------------------------------
-- SPDX-License-Identifier: GPL-3.0-or-later
--
-- Company:
-- Engineer: Daniel Kampert
--
-- Create Date: 14.06.2026
-- Design Name: TinyMCU
-- Module Name: tinymcu_cpu_csrfile - tinymcu_cpu_csrfile_rtl
-- Project Name: TinyMCU
-- Description:
--   Minimal M-mode CSR file: the 6 registers required for trap handling
--   (mstatus, mie, mtvec, mepc, mcause, mip) plus mscratch (handler
--   prologue helper) and mtval (trap-specific info.
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

entity tinymcu_cpu_csrfile is
    port (
        -- Global control
        clk_i           : in  std_ulogic;
        rst_i           : in  std_ulogic;

        -- Trap inputs
        ext_irq_i       : in  std_ulogic;
        timer_irq_i     : in  std_ulogic;
        software_irq_i  : in  std_ulogic;

        -- Trap control signals
        trap_i          : in  std_ulogic;
        trap_pc_i       : in  word_t;
        is_mret_i       : in  std_ulogic;

        -- Status outputs
        mtvec_o         : out word_t;
        mstatus_o       : out word_t;
        mie_o           : out word_t;
        mip_o           : out word_t;
        mepc_o          : out word_t;

        -- Read/write port
        csr_addr_i      : in  std_ulogic_vector(11 downto 0);
        csr_wdata_i     : in  word_t;
        csr_we_i        : in  std_ulogic;
        csr_rdata_o     : out word_t
    );
end entity tinymcu_cpu_csrfile;

architecture tinymcu_cpu_csrfile_rtl of tinymcu_cpu_csrfile is

    constant CSR_MSTATUS    : std_ulogic_vector(11 downto 0) := x"300";
    constant CSR_MIE        : std_ulogic_vector(11 downto 0) := x"304";
    constant CSR_MTVEC      : std_ulogic_vector(11 downto 0) := x"305";
    constant CSR_MSCRATCH   : std_ulogic_vector(11 downto 0) := x"340";
    constant CSR_MEPC       : std_ulogic_vector(11 downto 0) := x"341";
    constant CSR_MCAUSE     : std_ulogic_vector(11 downto 0) := x"342";
    constant CSR_MTVAL      : std_ulogic_vector(11 downto 0) := x"343";
    constant CSR_MIP        : std_ulogic_vector(11 downto 0) := x"344";
    constant CSR_MVENDORID  : std_ulogic_vector(11 downto 0) := x"F11";
    constant CSR_MARCHID    : std_ulogic_vector(11 downto 0) := x"F12";
    constant CSR_MIMPID     : std_ulogic_vector(11 downto 0) := x"F13";

    signal mstatus          : word_t;
    signal mie              : word_t;
    signal mtvec            : word_t;
    signal mscratch         : word_t;
    signal mepc             : word_t;
    signal mcause           : word_t;
    signal mtval            : word_t;
    signal mip              : word_t;
    signal mip_temp         : word_t;

begin

    mip_temp <= mip(31 downto IRQ_MEI_BIT + 1) & ext_irq_i &
                mip(IRQ_MEI_BIT - 1 downto IRQ_MTI_BIT + 1) & timer_irq_i &
                mip(IRQ_MTI_BIT - 1 downto IRQ_MSI_BIT + 1) & software_irq_i &
                mip(IRQ_MSI_BIT - 1 downto 0);

    ----------------------------------------------------------------------
    -- Register read
    ----------------------------------------------------------------------
    process (csr_addr_i, mstatus, mie, mtvec, mscratch, mepc, mcause, mtval, mip_temp)
    begin
        case csr_addr_i is
            when CSR_MSTATUS    => csr_rdata_o <= mstatus;
            when CSR_MIE        => csr_rdata_o <= mie;
            when CSR_MTVEC      => csr_rdata_o <= mtvec;
            when CSR_MSCRATCH   => csr_rdata_o <= mscratch;
            when CSR_MEPC       => csr_rdata_o <= mepc;
            when CSR_MCAUSE     => csr_rdata_o <= mcause;
            when CSR_MTVAL      => csr_rdata_o <= mtval;
            when CSR_MIP        => csr_rdata_o <= mip_temp;
            when CSR_MVENDORID  => csr_rdata_o <= MVENDORID;
            when CSR_MARCHID    => csr_rdata_o <= MARCHID;
            when CSR_MIMPID     => csr_rdata_o <= MIMPID;
            when others         => csr_rdata_o <= (others => '0');
        end case;
    end process;

    ----------------------------------------------------------------------
    -- Register write
    ----------------------------------------------------------------------
    process (clk_i)
    begin
        if rising_edge(clk_i) then
            if rst_i = '1' then
                mstatus  <= (others => '0');
                mie      <= (others => '0');
                mtvec    <= (others => '0');
                mscratch <= (others => '0');
                mepc     <= (others => '0');
                mcause   <= (others => '0');
                mtval    <= (others => '0');
                mip      <= (others => '0');
            elsif trap_i = '1' then
                mepc <= trap_pc_i;

                if (mie(IRQ_MEI_BIT) and mip_temp(IRQ_MEI_BIT)) = '1' then
                    mcause <= '1' & std_ulogic_vector(to_unsigned(IRQ_MEI_BIT, 31));
                elsif (mie(IRQ_MSI_BIT) and mip_temp(IRQ_MSI_BIT)) = '1' then
                    mcause <= '1' & std_ulogic_vector(to_unsigned(IRQ_MSI_BIT, 31));
                else
                    mcause <= '1' & std_ulogic_vector(to_unsigned(IRQ_MTI_BIT, 31));
                end if;

                mstatus(7) <= mstatus(3);   -- MPIE <- MIE
                mstatus(3) <= '0';          -- MIE <- 0
            elsif is_mret_i = '1' then
                mstatus(3) <= mstatus(7);   -- MIE <- MPIE
            elsif csr_we_i = '1' then
                case csr_addr_i is
                    when CSR_MSTATUS  => mstatus        <= csr_wdata_i;
                    when CSR_MIE      => mie            <= csr_wdata_i;
                    when CSR_MTVEC    => mtvec          <= csr_wdata_i;
                    when CSR_MSCRATCH => mscratch       <= csr_wdata_i;
                    when CSR_MEPC     => mepc           <= csr_wdata_i;
                    when CSR_MCAUSE   => mcause         <= csr_wdata_i;
                    when CSR_MTVAL    => mtval          <= csr_wdata_i;
                    when CSR_MIP      => mip            <= csr_wdata_i;
                    when others       => null;
                end case;
            end if;
        end if;
    end process;

    mtvec_o     <= mtvec;
    mstatus_o   <= mstatus;
    mie_o       <= mie;
    mip_o       <= mip_temp;
    mepc_o      <= mepc;

end architecture tinymcu_cpu_csrfile_rtl;
