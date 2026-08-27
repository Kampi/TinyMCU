--------------------------------------------------------------------------------
-- SPDX-License-Identifier: GPL-3.0-or-later
--
-- Company:
-- Engineer: Daniel Kampert
--
-- Create Date: 14.06.2026
-- Design Name: TinyMCU
-- Module Name: tinymcu_cpu - tinymcu_cpu_rtl
-- Project Name: TinyMCU
-- Description:
--   RV32 core with Harvard architecture and a 3-stage pipeline:
--
--     Stage 1 (IF)  Fetch    : pc_reg addresses the instruction memory
--                              (tinymcu_imem); its boot-ROM read is
--                              registered (BRAM-style, one cycle of
--                              latency), so pc_if buffers the address
--                              for one cycle to stay paired with the
--                              instruction once it actually arrives.
--     Stage 2 (ID)  Buffer   : instr_if becomes valid; pc_if/instr_if
--                              are latched into pc_ex/instr_ex once
--                              not stalled.
--     Stage 3 (EX)  Execute  : decode (tinymcu_cpu_control), register read/write,
--                              ALU, branch/jump resolution, data memory
--                              access (tinymcu_sram's read is likewise
--                              registered; its ack is delayed to match,
--                              so the existing bus-stall mechanism
--                              absorbs that latency without any extra
--                              pipeline stage there).
--
--   A taken branch/jump/trap squashes two in-flight fetches (not one),
--   and every stall (bus wait, mult/div busy) needs a two-cycle
--   redirect-style recovery back to pc_if once it clears.
--
-- Dependencies:
--   tinymcu_pkg, tinymcu_imem, tinymcu_cpu_control, tinymcu_cpu_regfile,
--   tinymcu_cpu_csrfile, tinymcu_cpu_alu, tinymcu_addr_decoder,
--   tinymcu_sram, tinymcu_periph, tinymcu_periph_gpio
--
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library tinymcu;
use tinymcu.tinymcu_pkg.all;

entity tinymcu_cpu is
    generic (
        IMEM_ADDR_WIDTH : integer := 13;
        RAM_ADDR_WIDTH  : integer := 10;

        -- Simulation only: prints "PC=0x... INSTR=0x... <mnemonic>" every
        -- cycle an instruction is in EX, using tinymcu_pkg.vhd's
        -- disassemble(). Default off so testbenches that don't want the
        -- noise (e.g. tinymcu_tb_core.vhd) are unaffected;
        -- tinymcu_tb_software.vhd turns it on.
        TRACE_ENABLE    : boolean := false
    );
    port (
        -- Global control
        clk_i           : in std_logic;
        rst_i           : in std_logic;

        -- External interrupt request
        ext_irq_i       : in std_logic;

        -- GPIO ports
        gpio_port_a     : inout std_logic_vector(31 downto 0);

        -- UART
        uart_tx_o       : out std_logic;
        uart_rx_i       : in std_logic := '1';
        uart_rts_o      : out std_logic;
        uart_cts_i      : in std_logic := '1';

        -- Simulation/debug only; leave unconnected in the FPGA top level.
        debug_regs_o    : out reg_array_t
    );
end entity tinymcu_cpu;

architecture tinymcu_cpu_rtl of tinymcu_cpu is

    -- Fetch stage
    signal pc_reg       : word_t;
    signal next_pc      : word_t;
    signal instr_if     : word_t;

    -- IF/ID buffer: tinymcu_imem's boot-ROM read is registered (BRAM-style, one cycle of latency, so
    -- instr_if lags the pc_reg value that produced it by one cycle
    signal pc_if        : word_t;

    -- ID/EX pipeline register
    signal instr_ex     : word_t;
    signal pc_ex        : word_t;

    -- '1' for one cycle the first time a (new) instruction sits in EX
    signal dispatched   : std_ulogic;

    -- '1' for one extra cycle after redirect
    signal redirect_d1  : std_ulogic;

    -- '1' while a multi cycle instruction is active to hold the pipeline
    signal stall        : std_ulogic;

    -- '1' for exactly the cycle a stall (bus wait, mult/div busy)
    signal stall_d1     : std_ulogic;

    -- Flush the pipeline
    signal resume_flush : std_ulogic;

    -- Decoded fields
    signal opcode       : std_ulogic_vector(6 downto 0);
    signal funct3       : std_ulogic_vector(2 downto 0);
    signal rd           : std_ulogic_vector(4 downto 0);
    signal rs1          : std_ulogic_vector(4 downto 0);
    signal rs2          : std_ulogic_vector(4 downto 0);

    -- Immediates
    signal imm_i        : word_t;
    signal imm_s        : word_t;
    signal imm_b        : word_t;
    signal imm_u        : word_t;
    signal imm_j        : word_t;

    -- Control signals
    signal alu_op       : std_ulogic_vector(14 downto 0);
    signal alu_a_sel    : std_ulogic;
    signal alu_b_sel    : std_ulogic_vector(2 downto 0);
    signal reg_we       : std_ulogic;
    signal ram_we       : std_ulogic;
    signal is_jal       : std_ulogic;
    signal is_jalr      : std_ulogic;
    signal is_branch    : std_ulogic;
    signal is_mret      : std_ulogic;
    signal is_trap      : std_ulogic;

    -- Register file
    signal rs1_val      : word_t;
    signal rs2_val      : word_t;
    signal rd_data      : word_t;

    -- ALU
    signal alu_op_a     : word_t;
    signal alu_op_b     : word_t;
    signal alu_result   : word_t;

    -- Multiplier
    signal mult_result  : word_t;
    signal mult_start   : std_ulogic;
    signal mult_busy    : std_ulogic;
    signal mult_valid   : std_ulogic;
    signal is_mult      : std_ulogic;

    -- Division
    signal div_quotient : word_t;
    signal div_remain   : word_t;
    signal div_start    : std_ulogic;
    signal div_busy     : std_ulogic;
    signal div_valid    : std_ulogic;
    signal is_div       : std_ulogic;

    -- Branch / Jump / Trap resolution
    signal branch_taken     : std_ulogic;
    signal redirect         : std_ulogic;
    signal redirect_target  : word_t;

    -- Data memory
    signal ram_in       : word_t;
    signal ram_ben      : std_ulogic_vector(3 downto 0);
    signal load_data    : word_t;

    -- Data memory bus
    signal cpu_req      : bus_req_t;
    signal cpu_rsp      : bus_rsp_t;
    signal imem_req     : bus_req_t;
    signal imem_rsp     : bus_rsp_t;
    signal ram_req      : bus_req_t;
    signal ram_rsp      : bus_rsp_t;
    signal periph_req   : bus_req_t;
    signal periph_rsp   : bus_rsp_t;
    signal gpio_req     : bus_req_t;
    signal gpio_rsp     : bus_rsp_t;
    signal timer_req    : bus_req_t;
    signal timer_rsp    : bus_rsp_t;
    signal uart_req     : bus_req_t;
    signal uart_rsp     : bus_rsp_t;

    -- IRQ signals
    signal periph_timer_irq : std_ulogic;

    -- '1' when this source is both enabled (mie) and pending (mip)
    signal msi_pending  : std_ulogic;
    signal mti_pending  : std_ulogic;
    signal mei_pending  : std_ulogic;

    -- CSR file
    signal csr_addr     : std_ulogic_vector(11 downto 0);
    signal csr_rdata    : word_t;
    signal csr_wdata    : word_t;
    signal mtvec        : word_t;
    signal mstatus      : word_t;
    signal mie          : word_t;
    signal mip          : word_t;
    signal mepc         : word_t;
    signal csr_we       : std_ulogic;

begin

    ----------------------------------------------------------------------
    -- Fetch stage: instruction memory
    ----------------------------------------------------------------------
    u_imem : entity tinymcu.tinymcu_imem
        generic map (IMEM_ADDR_WIDTH => IMEM_ADDR_WIDTH)
        port map (
            clk_i        => clk_i,
            fetch_addr_i => pc_reg,
            fetch_dout_o => instr_if,
            data_req_i   => imem_req,
            data_rsp_o   => imem_rsp
        );

    -- Continue with the pipeline flush on a rising edge of "stall_dl"
    resume_flush <= '1' when (stall_d1 = '1' and stall = '0') else '0';

    ----------------------------------------------------------------------
    -- Stall logic
    ----------------------------------------------------------------------
    process (clk_i)
    begin
        if rising_edge(clk_i) then
            if rst_i = '1' then
                stall_d1 <= '0';
            else
                stall_d1 <= stall;
            end if;
        end if;
    end process;

    -- Hold the pipeline when
    --  The bus slave hasn´t acked the message
    --  The multiplier is busy
    --  The division is busy
    stall <= (cpu_req.stb and not cpu_rsp.ack) or mult_busy or div_busy;

    ----------------------------------------------------------------------
    -- PC and pipeline register
    ----------------------------------------------------------------------
    process (clk_i)
    begin
        if rising_edge(clk_i) then
            if rst_i = '1' then
                pc_reg      <= (others => '0');
                pc_if       <= (others => '0');
                pc_ex       <= (others => '0');
                instr_ex    <= NOP_INSTR;
                redirect_d1 <= '1';
            elsif stall = '1' then
                -- Current EX instruction's memory access hasn't been
                -- acknowledged yet. Hold PC and instr_ex/pc_ex exactly
                -- as they are and re-issue the same request next cycle.
                -- pc_if freezes right along with pc_reg here (it does
                -- NOT update unconditionally) -- it's what remembers
                -- the address resume_flush needs to re-fetch below.
                null;
            else
                pc_ex <= pc_if;
                redirect_d1 <= redirect or resume_flush;

                if redirect = '1' or redirect_d1 = '1' or resume_flush = '1' then
                    instr_ex <= NOP_INSTR;
                else
                    instr_ex <= instr_if;
                end if;

                if resume_flush = '1' then
                    pc_reg <= pc_if;
                else
                    pc_if  <= pc_reg;
                    pc_reg <= next_pc;
                end if;
            end if;
        end if;
    end process;

    -- Increase the program counter or use the redirect target when a redirection occurs
    next_pc <= redirect_target when redirect = '1' else std_ulogic_vector(unsigned(pc_reg) + 4);

    -- Use this process to generate a one cycle pulse at the beginning of each new instruction behind the pipeline
    process (clk_i)
    begin
        if rising_edge(clk_i) then
            if rst_i = '1' then
                dispatched <= '0';
            else
                dispatched <= not stall;
            end if;
        end if;
    end process;

    ----------------------------------------------------------------------
    -- Instruction decoder
    ----------------------------------------------------------------------
    u_control : entity tinymcu.tinymcu_cpu_control
        port map (
            instr_i         => instr_ex,
            opcode_o        => opcode,
            rd_o            => rd,
            rs1_o           => rs1,
            rs2_o           => rs2,
            funct3_o        => funct3,
            imm_i_o         => imm_i,
            imm_s_o         => imm_s,
            imm_b_o         => imm_b,
            imm_u_o         => imm_u,
            imm_j_o         => imm_j,
            alu_op_o        => alu_op,
            alu_a_sel_o     => alu_a_sel,
            alu_b_sel_o     => alu_b_sel,
            reg_we_o        => reg_we,
            ram_we_o        => ram_we,
            is_jal_o        => is_jal,
            is_jalr_o       => is_jalr,
            is_branch_o     => is_branch,
            is_mret_o       => is_mret,
            is_csr_o        => csr_we,
            is_mult_o       => is_mult,
            is_div_o        => is_div
        );

    ----------------------------------------------------------------------
    -- Register file
    ----------------------------------------------------------------------
    u_regfile : entity tinymcu.tinymcu_cpu_regfile
        port map (
            clk_i           => clk_i,
            rs1_addr_i      => rs1,
            rs2_addr_i      => rs2,
            rs1_data_o      => rs1_val,
            rs2_data_o      => rs2_val,
            we_i            => reg_we and not stall,
            rd_addr_i       => rd,
            rd_data_i       => rd_data,
            debug_regs_o    => debug_regs_o
        );

    rd_data <= load_data    when opcode = OPC_LOAD                                                          else
               csr_rdata    when opcode = OPC_SYSTEM                                                        else
               mult_result  when is_mult = '1' and mult_valid = '1'                                         else
               div_remain   when is_div = '1' and div_valid = '1' and (funct3 = "110" or funct3 = "111")    else
               div_quotient when is_div = '1' and div_valid = '1' and (funct3 = "100" or funct3 = "101")    else
               alu_result;

    ----------------------------------------------------------------------
    -- Multiplier
    ----------------------------------------------------------------------
    u_mult : entity tinymcu.tinymcu_cpu_mult
        port map (
            clk_i       => clk_i,
            rst_i       => rst_i,
            op_a_i      => rs1_val,
            op_b_i      => rs2_val,
            result_o    => mult_result,
            start_i     => mult_start,
            busy_o      => mult_busy,
            valid_o     => mult_valid,
            funct3_i    => funct3
        );

    -- Start the multiplication (one clock cycle pulse) as soon as a dispatched event happens
    mult_start <= dispatched and is_mult;

    ----------------------------------------------------------------------
    -- Division
    ----------------------------------------------------------------------
    u_div : entity tinymcu.tinymcu_cpu_div
        port map (
            clk_i       => clk_i,
            rst_i       => rst_i,
            op_a_i      => rs1_val,
            op_b_i      => rs2_val,
            quotient_o  => div_quotient,
            remainder_o => div_remain,
            start_i     => div_start,
            busy_o      => div_busy,
            valid_o     => div_valid,
            funct3_i    => funct3
        );

    -- Start the division (one clock cycle pulse) as soon as a dispatched event happens
    div_start <= dispatched and is_div;

    ----------------------------------------------------------------------
    -- ALU
    ----------------------------------------------------------------------
    u_alu : entity tinymcu.tinymcu_cpu_alu
        port map (
            op_a_i    => alu_op_a,
            op_b_i    => alu_op_b,
            alu_op_i  => alu_op,
            result_o  => alu_result
        );

    alu_op_a <= pc_ex when alu_a_sel = CONST_ALU_SELECT_PC else
                rs1_val;

    with alu_b_sel select
        alu_op_b <= rs2_val         when OPB_REG,
                    imm_i           when OPB_IMM_I,
                    imm_s           when OPB_IMM_S,
                    imm_u           when OPB_IMM_U,
                    x"00000004"     when OPB_CONST4,
                    (others => '0') when others;

    ----------------------------------------------------------------------
    -- Load operations
    ----------------------------------------------------------------------
    process (funct3, alu_result, cpu_rsp)
        variable byte_val : std_ulogic_vector(7 downto 0);
        variable half_val : std_ulogic_vector(15 downto 0);
    begin
        case alu_result(1 downto 0) is
            when "00"   => byte_val := std_ulogic_vector(cpu_rsp.data(7 downto 0));
            when "01"   => byte_val := std_ulogic_vector(cpu_rsp.data(15 downto 8));
            when "10"   => byte_val := std_ulogic_vector(cpu_rsp.data(23 downto 16));
            when others => byte_val := std_ulogic_vector(cpu_rsp.data(31 downto 24));
        end case;

        if alu_result(1) = '0' then
            half_val := std_ulogic_vector(cpu_rsp.data(15 downto 0));
        else
            half_val := std_ulogic_vector(cpu_rsp.data(31 downto 16));
        end if;

        case funct3 is
            when "000"  => load_data <= std_ulogic_vector(resize(signed(byte_val), 32));   -- LB
            when "001"  => load_data <= std_ulogic_vector(resize(signed(half_val), 32));   -- LH
            when "100"  => load_data <= std_ulogic_vector(resize(unsigned(byte_val), 32)); -- LBU
            when "101"  => load_data <= std_ulogic_vector(resize(unsigned(half_val), 32)); -- LHU
            when others => load_data <= cpu_rsp.data;                                      -- LW
        end case;
    end process;

    ----------------------------------------------------------------------
    -- Store operations
    ----------------------------------------------------------------------
    process (funct3, alu_result, rs2_val)
    begin
        case funct3 is
            when "000" =>  -- SB
                case alu_result(1 downto 0) is
                    when "00"   => ram_ben <= "0001";
                    when "01"   => ram_ben <= "0010";
                    when "10"   => ram_ben <= "0100";
                    when others => ram_ben <= "1000";
                end case;

                -- The byte to write is determined by "ram_ben"
                ram_in <= rs2_val(7 downto 0) & rs2_val(7 downto 0) &
                          rs2_val(7 downto 0) & rs2_val(7 downto 0);

            when "001" =>  -- SH
                if alu_result(1) = '0' then
                    ram_ben <= "0011";
                else
                    ram_ben <= "1100";
                end if;

                ram_in <= rs2_val(15 downto 0) & rs2_val(15 downto 0);

            when others =>  -- SW
                ram_ben <= "1111";
                ram_in  <= rs2_val;

        end case;
    end process;

    ----------------------------------------------------------------------
    -- CSR operations
    ----------------------------------------------------------------------
    process (funct3, csr_rdata, rs1_val, instr_ex)
        variable imm5 : word_t;
    begin
        imm5 := (others => '0');
        imm5(4 downto 0) := instr_ex(19 downto 15);

        case funct3 is
            when CSR_RW  => csr_wdata <= rs1_val;
            when CSR_RS  => csr_wdata <= csr_rdata or rs1_val;
            when CSR_RC  => csr_wdata <= csr_rdata and not rs1_val;
            when CSR_RWI => csr_wdata <= imm5;
            when CSR_RSI => csr_wdata <= csr_rdata or imm5;
            when CSR_RCI => csr_wdata <= csr_rdata and not imm5;
            when others  => csr_wdata <= (others => '0');

        end case;
    end process;

    ----------------------------------------------------------------------
    -- CSR Register file
    ----------------------------------------------------------------------
    csr_addr <= instr_ex(31 downto 20);
    u_csrfile : entity tinymcu.tinymcu_cpu_csrfile
        port map (
            clk_i           => clk_i,
            rst_i           => rst_i,
            ext_irq_i       => ext_irq_i,
            timer_irq_i     => periph_timer_irq,
            software_irq_i  => '0',
            trap_i          => is_trap,
            trap_pc_i       => pc_ex,
            is_mret_i       => is_mret,
            mtvec_o         => mtvec,
            mstatus_o       => mstatus,
            mie_o           => mie,
            mip_o           => mip,
            mepc_o          => mepc,
            csr_addr_i      => csr_addr,
            csr_wdata_i     => csr_wdata,
            csr_we_i        => csr_we,
            csr_rdata_o     => csr_rdata
        );

    msi_pending <= mie(IRQ_MSI_BIT) and mip(IRQ_MSI_BIT);
    mti_pending <= mie(IRQ_MTI_BIT) and mip(IRQ_MTI_BIT);
    mei_pending <= mie(IRQ_MEI_BIT) and mip(IRQ_MEI_BIT);

    -- Signal a trap when MIE is set and an interrupt is pending
    is_trap <= '1' when (mstatus(3) = '1' and
                         (msi_pending = '1' or mti_pending = '1' or mei_pending = '1') and
                         stall = '0')
                else '0';

    ----------------------------------------------------------------------
    -- Branch comparator and jump target addresses
    ----------------------------------------------------------------------
    process (funct3, rs1_val, rs2_val)
        variable eq, slt, ult : boolean;
    begin
        eq  := (rs1_val = rs2_val);
        slt := (signed(rs1_val) < signed(rs2_val));
        ult := (unsigned(rs1_val) < unsigned(rs2_val));
        case funct3 is
            when "000"  => branch_taken <= '1' when eq       else '0'; -- BEQ
            when "001"  => branch_taken <= '1' when not eq   else '0'; -- BNE
            when "100"  => branch_taken <= '1' when slt      else '0'; -- BLT
            when "101"  => branch_taken <= '1' when not slt  else '0'; -- BGE
            when "110"  => branch_taken <= '1' when ult      else '0'; -- BLTU
            when "111"  => branch_taken <= '1' when not ult  else '0'; -- BGEU
            when others => branch_taken <= '0';

        end case;
    end process;

    ----------------------------------------------------------------------
    -- Jump / Branch / Trap target address selection
    ----------------------------------------------------------------------
    process (is_trap, is_mret, is_jal, is_jalr, pc_ex, imm_j, imm_b, imm_i, rs1_val, mtvec, mepc, mei_pending, msi_pending, mti_pending)
        variable vec_cause  : integer range 0 to 15;
        variable mtvec_base : word_t;
    begin
        if mei_pending = '1' then
            vec_cause := IRQ_MEI_BIT;
        elsif msi_pending = '1' then
            vec_cause := IRQ_MSI_BIT;
        else
            vec_cause := IRQ_MTI_BIT;
        end if;

        mtvec_base := mtvec(31 downto 2) & "00";

        if is_trap = '1' then
            -- Vector mode
            if mtvec(1 downto 0) = "01" then
                redirect_target <= std_ulogic_vector(unsigned(mtvec_base) + to_unsigned(vec_cause * 4, 32));
            -- Direct mode
            else
                redirect_target <= mtvec_base;
            end if;
        elsif is_mret = '1' then
            redirect_target <= mepc;
        elsif is_jal = '1' then
            redirect_target <= std_ulogic_vector(unsigned(pc_ex) + unsigned(imm_j));
        elsif is_jalr = '1' then
            redirect_target <= std_ulogic_vector(unsigned(rs1_val) + unsigned(imm_i));

            -- JALR requires to set bit 0 to 0, regardless of the result
            redirect_target(0) <= '0';
        else
            redirect_target <= std_ulogic_vector(unsigned(pc_ex) + unsigned(imm_b));
        end if;
    end process;

    -- Enable redirection to the redirect target
    redirect <= '1' when (is_trap = '1') or 
                         (is_mret = '1') or 
                         (is_jal = '1') or 
                         (is_jalr = '1') or 
                         (is_branch = '1' and branch_taken = '1') 
                else '0';

    ----------------------------------------------------------------------
    -- Data memory bus
    ----------------------------------------------------------------------
    u_addr_decoder : entity tinymcu.tinymcu_addr_decoder
        port map (
            cpu_rsp_o       => cpu_rsp,
            cpu_req_i       => cpu_req,
            imem_req_o      => imem_req,
            imem_rsp_i      => imem_rsp,
            ram_req_o       => ram_req,
            ram_rsp_i       => ram_rsp,
            periph_req_o    => periph_req,
            periph_rsp_i    => periph_rsp
        );

    ----------------------------------------------------------------------
    -- SRAM
    ----------------------------------------------------------------------
    u_sram : entity tinymcu.tinymcu_sram
        generic map (ADDR_WIDTH => RAM_ADDR_WIDTH)
        port map (
            clk_i   => clk_i,
            rst_i   => rst_i,
            req_i   => ram_req,
            rsp_o   => ram_rsp
        );

    cpu_req.addr <= alu_result;
    cpu_req.data <= ram_in;
    cpu_req.ben  <= ram_ben;
    cpu_req.we   <= ram_we;
    cpu_req.stb  <= '1' when (opcode = OPC_LOAD or opcode = OPC_STORE) else '0';

    ----------------------------------------------------------------------
    -- Peripheral address decoder
    ----------------------------------------------------------------------
    u_periph : entity tinymcu.tinymcu_periph
        port map (
            periph_req_i  => periph_req,
            periph_rsp_o  => periph_rsp,
            gpio_req_o    => gpio_req,
            gpio_rsp_i    => gpio_rsp,
            timer_req_o   => timer_req,
            timer_rsp_i   => timer_rsp,
            uart_req_o    => uart_req,
            uart_rsp_i    => uart_rsp
        );

    ----------------------------------------------------------------------
    -- GPIO Peripheral
    ----------------------------------------------------------------------
    u_periph_gpio : entity tinymcu.tinymcu_periph_gpio
        port map (
            clk_i       => clk_i,
            rst_i       => rst_i,
            gpio_req_i  => gpio_req,
            gpio_rsp_o  => gpio_rsp,
            gpio_port_a => gpio_port_a
        );

    ----------------------------------------------------------------------
    -- Timer Peripheral
    ----------------------------------------------------------------------
    u_periph_timer : entity tinymcu.tinymcu_periph_timer
        port map (
            clk_i       => clk_i,
            rst_i       => rst_i,
            irq_o       => periph_timer_irq,
            timer_req_i => timer_req,
            timer_rsp_o => timer_rsp
        );

    ----------------------------------------------------------------------
    -- UART Peripheral
    ----------------------------------------------------------------------
    u_periph_uart : entity tinymcu.tinymcu_periph_uart
        port map (
            clk_i       => clk_i,
            rst_i       => rst_i,
            uart_req_i  => uart_req,
            uart_rsp_o  => uart_rsp,
            tx_o        => uart_tx_o,
            rx_i        => uart_rx_i,
            rts_o       => uart_rts_o,
            cts_i       => uart_cts_i
        );

    ----------------------------------------------------------------------
    -- Simulation-only instruction trace (see TRACE_ENABLE above)
    ----------------------------------------------------------------------
    trace_gen : if TRACE_ENABLE generate
        process (clk_i)
        begin
            if rising_edge(clk_i) and rst_i = '0' then
                report "PC=0x" & to_hex(pc_ex) & "  INSTR=0x" & to_hex(instr_ex) & "  " & disassemble(pc_ex, instr_ex);
            end if;
        end process;
    end generate;

end architecture tinymcu_cpu_rtl;
