--------------------------------------------------------------------------------
-- SPDX-License-Identifier: GPL-3.0-or-later
--
-- Company:
-- Engineer: Daniel Kampert
--
-- Create Date: 14.06.2026
-- Design Name: TinyMCU
-- Module Name: tinymcu_cpu_control - tinymcu_cpu_control_rtl
-- Project Name: TinyMCU
-- Description:
--   Instruction decoder / control unit of TinyMCU.
--
-- Dependencies:
--   tinymcu_pkg
--
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;

library tinymcu;
use tinymcu.tinymcu_pkg.all;

entity tinymcu_cpu_control is
    port (
        -- Instruction input
        instr_i     : in  word_t;

        -- Raw instruction fields
        opcode_o    : out std_ulogic_vector(6 downto 0);
        rd_o        : out std_ulogic_vector(4 downto 0);
        rs1_o       : out std_ulogic_vector(4 downto 0);
        rs2_o       : out std_ulogic_vector(4 downto 0);
        funct3_o    : out std_ulogic_vector(2 downto 0);

        -- Immediates (already sign-extended to 32 bits)
        imm_i_o     : out word_t;
        imm_s_o     : out word_t;
        imm_b_o     : out word_t;
        imm_u_o     : out word_t;
        imm_j_o     : out word_t;

        -- ALU control
        alu_op_o    : out std_ulogic_vector(14 downto 0);
        alu_a_sel_o : out std_ulogic;
        alu_b_sel_o : out std_ulogic_vector(2 downto 0);

        -- Other control signals
        reg_we_o    : out std_ulogic;
        ram_we_o    : out std_ulogic;
        is_jal_o    : out std_ulogic;
        is_jalr_o   : out std_ulogic;
        is_branch_o : out std_ulogic;
        is_mret_o   : out std_ulogic;
        is_csr_o    : out std_ulogic
    );
end entity tinymcu_cpu_control;

architecture tinymcu_cpu_control_rtl of tinymcu_cpu_control is

    signal opcode     : std_ulogic_vector(6 downto 0);
    signal funct3     : std_ulogic_vector(2 downto 0);
    signal funct7     : std_ulogic_vector(6 downto 0);
    signal is_csr     : std_ulogic;
    signal funct7_alu : std_ulogic_vector(6 downto 0);
    signal subfunc    : std_ulogic_vector(4 downto 0);

begin

    ----------------------------------------------------------------------
    -- Field extraction
    ----------------------------------------------------------------------
    opcode <= std_ulogic_vector(instr_i(6 downto 0));
    funct3 <= std_ulogic_vector(instr_i(14 downto 12));

    funct7 <= std_ulogic_vector(instr_i(31 downto 25));

    opcode_o <= opcode;
    funct3_o <= funct3;
    rd_o     <= std_ulogic_vector(instr_i(11 downto 7));
    rs1_o    <= std_ulogic_vector(instr_i(19 downto 15));
    rs2_o    <= std_ulogic_vector(instr_i(24 downto 20));

    ----------------------------------------------------------------------
    -- Immediate generation
    ----------------------------------------------------------------------
    imm_i_o <= sext(instr_i(31 downto 20), 32);
    imm_s_o <= sext(instr_i(31 downto 25) & instr_i(11 downto 7), 32);
    imm_b_o <= sext(instr_i(31) & instr_i(7) & instr_i(30 downto 25) & instr_i(11 downto 8) & '0', 32);
    imm_u_o <= instr_i(31 downto 12) & x"000";
    imm_j_o <= sext(instr_i(31) & instr_i(19 downto 12) & instr_i(20) & instr_i(30 downto 21) & '0', 32);

    ----------------------------------------------------------------------
    -- ALU operand and operation selection
    ----------------------------------------------------------------------
    funct7_alu <= funct7 when (opcode = OPC_OP or
                               (opcode = OPC_OPIMM and (funct3 = "001" or funct3 = "101")))
                  else (others => '0');

    -- subfunc disambiguates the five OPC_OPIMM/funct3=001/funct7=0110000
    -- unary ops (CLZ/CTZ/CPOP/SEXT.B/SEXT.H, see tinymcu_pkg.vhd's ALU_*
    -- constants) via instr(24 downto 20), the one place that isn't a real
    -- rs2 register for exactly that combination. Forced to the "11111"
    -- sentinel everywhere else, including ROL (OPC_OP, same funct7/
    -- funct3, but there instr(24 downto 20) is a genuine rs2 and must not
    -- leak into alu_op).
    subfunc <= std_ulogic_vector(instr_i(24 downto 20))
               when (opcode = OPC_OPIMM and funct3 = "001" and funct7 = "0110000")
               else "11111";

    process (opcode, funct3, funct7_alu, subfunc)
    begin
        -- Defaults
        alu_a_sel_o <= '0';
        alu_b_sel_o <= OPB_IMM_I;
        alu_op_o    <= ALU_ADD;

        case opcode is
            when OPC_OP =>
                alu_a_sel_o <= '0';
                alu_b_sel_o <= OPB_REG;
                alu_op_o    <= funct7_alu & funct3 & subfunc;

            when OPC_OPIMM =>
                alu_a_sel_o <= '0';
                alu_b_sel_o <= OPB_IMM_I;
                alu_op_o    <= funct7_alu & funct3 & subfunc;

            when OPC_LOAD =>
                alu_a_sel_o <= CONST_ALU_SELECT_REG;
                alu_b_sel_o <= OPB_IMM_I;
                alu_op_o    <= ALU_ADD;

            when OPC_STORE =>
                alu_a_sel_o <= CONST_ALU_SELECT_REG;
                alu_b_sel_o <= OPB_IMM_S;
                alu_op_o    <= ALU_ADD;

            when OPC_LUI =>
                alu_a_sel_o <= CONST_ALU_SELECT_REG;
                alu_b_sel_o <= OPB_IMM_U;
                alu_op_o    <= ALU_PASSB;

            -- x[rd] = pc + 4
            -- pc += sext(offset)
            when OPC_JAL =>
                alu_a_sel_o <= CONST_ALU_SELECT_PC;
                alu_b_sel_o <= OPB_CONST4;
                alu_op_o    <= ALU_ADD;

            -- x[rd]=pc + 4
            -- pc = (x[rs1] + sext(offset)) & ∼1
            when OPC_JALR =>
                alu_a_sel_o <= CONST_ALU_SELECT_PC;
                alu_b_sel_o <= OPB_CONST4;
                alu_op_o    <= ALU_ADD;

            -- x[rd] = pc + sext(immediate[31:12] << 12)
            when OPC_AUIPC =>
                alu_a_sel_o <= CONST_ALU_SELECT_PC;
                alu_b_sel_o <= OPB_IMM_U;
                alu_op_o    <= ALU_ADD;

            -- CSR* instructions don't use the ALU at all (see
            -- tinymcu_cpu.vhd's "CSR operations" process and
            -- tinymcu_cpu_csrfile.vhd).
            -- Defaults below are harmless.
            when OPC_SYSTEM =>
                alu_a_sel_o <= CONST_ALU_SELECT_REG;
                alu_b_sel_o <= OPB_IMM_I;
                alu_op_o    <= ALU_ADD;

            when others => -- OPC_BRANCH, NOP
                alu_a_sel_o <= CONST_ALU_SELECT_REG;
                alu_b_sel_o <= OPB_IMM_I;
                alu_op_o    <= ALU_ADD;
        end case;
    end process;

    ----------------------------------------------------------------------
    -- CSR related signals
    ----------------------------------------------------------------------
    is_csr <= '1' when (opcode = OPC_SYSTEM and
                        (funct3 = CSR_RW or funct3 = CSR_RS or funct3 = CSR_RC or
                         funct3 = CSR_RWI or funct3 = CSR_RSI or funct3 = CSR_RCI))
              else '0';
    is_csr_o <= is_csr;

    ----------------------------------------------------------------------
    -- Trap related signals
    ----------------------------------------------------------------------
    is_mret_o <= '1' when (opcode = OPC_SYSTEM and funct3 = "000" and instr_i(31 downto 20) = x"302") else '0';

    ----------------------------------------------------------------------
    -- Register file related signals
    ----------------------------------------------------------------------
    reg_we_o <= '1' when (opcode = OPC_OP or opcode = OPC_OPIMM or opcode = OPC_LUI or
                          opcode = OPC_JAL or opcode = OPC_JALR or opcode = OPC_LOAD or
                          opcode = OPC_AUIPC or is_csr = '1')
                else '0';

    ----------------------------------------------------------------------
    -- SRAM related signals
    ----------------------------------------------------------------------
    ram_we_o <= '1' when opcode = OPC_STORE else '0';

    ----------------------------------------------------------------------
    -- Branch & Jump related signals
    ----------------------------------------------------------------------
    is_jal_o    <= '1' when opcode = OPC_JAL    else '0';
    is_jalr_o   <= '1' when opcode = OPC_JALR   else '0';
    is_branch_o <= '1' when opcode = OPC_BRANCH else '0';

end architecture tinymcu_cpu_control_rtl;
