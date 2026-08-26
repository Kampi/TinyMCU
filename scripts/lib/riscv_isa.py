# SPDX-License-Identifier: GPL-3.0-or-later

"""RV32I/Zicsr instruction encoders and opcode/CSR-address constants.

Not a general-purpose assembler (no labels, no directives): callers emit
instructions in program order and compute jump/branch offsets by hand
against the resulting byte addresses, the same way asm.py/asm_irq.py do.

Only covers what tinymcu_cpu_control.vhd actually decodes (see
../README.md's "Supported Instructions"/"Not Supported Instructions"),
plus MRET.
"""


def b(v, width):
    return format(v & ((1 << width) - 1), '0{}b'.format(width))


def i_type(imm, rs1, funct3, rd, opcode):
    if imm < 0:
        imm += 0x1000
    s = b(imm, 12) + b(rs1, 5) + b(funct3, 3) + b(rd, 5) + b(opcode, 7)
    assert len(s) == 32
    return int(s, 2)


def s_type(imm, rs2, rs1, funct3, opcode):
    imm11_5 = (imm >> 5) & 0x7F
    imm4_0 = imm & 0x1F
    s = b(imm11_5, 7) + b(rs2, 5) + b(rs1, 5) + b(funct3, 3) + b(imm4_0, 5) + b(opcode, 7)
    assert len(s) == 32
    return int(s, 2)


def b_type(imm, rs2, rs1, funct3, opcode):
    imm12 = (imm >> 12) & 0x1
    imm10_5 = (imm >> 5) & 0x3F
    imm4_1 = (imm >> 1) & 0xF
    imm11 = (imm >> 11) & 0x1
    s = (b(imm12, 1) + b(imm10_5, 6) + b(rs2, 5) + b(rs1, 5) + b(funct3, 3) +
         b(imm4_1, 4) + b(imm11, 1) + b(opcode, 7))
    assert len(s) == 32
    return int(s, 2)


def u_type(imm20, rd, opcode):
    s = b(imm20, 20) + b(rd, 5) + b(opcode, 7)
    assert len(s) == 32
    return int(s, 2)


def j_type(imm, rd, opcode):
    imm20 = (imm >> 20) & 0x1
    imm10_1 = (imm >> 1) & 0x3FF
    imm11 = (imm >> 11) & 0x1
    imm19_12 = (imm >> 12) & 0xFF
    s = b(imm20, 1) + b(imm10_1, 10) + b(imm11, 1) + b(imm19_12, 8) + b(rd, 5) + b(opcode, 7)
    assert len(s) == 32
    return int(s, 2)


OPC_OP = 0b0110011
OPC_OPIMM = 0b0010011
OPC_LUI = 0b0110111
OPC_BRANCH = 0b1100011
OPC_JAL = 0b1101111
OPC_JALR = 0b1100111
OPC_LOAD = 0b0000011
OPC_STORE = 0b0100011
OPC_AUIPC = 0b0010111
OPC_SYSTEM = 0b1110011


def ADDI(rd, rs1, imm): return i_type(imm, rs1, 0b000, rd, OPC_OPIMM)
def ADD(rd, rs1, rs2): return int(b(0, 7) + b(rs2, 5) + b(rs1, 5) + b(0, 3) + b(rd, 5) + b(OPC_OP, 7), 2)
def SUB(rd, rs1, rs2): return int(b(0b0100000, 7) + b(rs2, 5) + b(rs1, 5) + b(0, 3) + b(rd, 5) + b(OPC_OP, 7), 2)
def MUL(rd, rs1, rs2): return int(b(0b0000001, 7) + b(rs2, 5) + b(rs1, 5) + b(0b000, 3) + b(rd, 5) + b(OPC_OP, 7), 2)
def DIV(rd, rs1, rs2): return int(b(0b0000001, 7) + b(rs2, 5) + b(rs1, 5) + b(0b100, 3) + b(rd, 5) + b(OPC_OP, 7), 2)
def DIVU(rd, rs1, rs2): return int(b(0b0000001, 7) + b(rs2, 5) + b(rs1, 5) + b(0b101, 3) + b(rd, 5) + b(OPC_OP, 7), 2)
def REM(rd, rs1, rs2): return int(b(0b0000001, 7) + b(rs2, 5) + b(rs1, 5) + b(0b110, 3) + b(rd, 5) + b(OPC_OP, 7), 2)
def REMU(rd, rs1, rs2): return int(b(0b0000001, 7) + b(rs2, 5) + b(rs1, 5) + b(0b111, 3) + b(rd, 5) + b(OPC_OP, 7), 2)
def SW(rs2, imm, rs1): return s_type(imm, rs2, rs1, 0b010, OPC_STORE)
def SB(rs2, imm, rs1): return s_type(imm, rs2, rs1, 0b000, OPC_STORE)
def SH(rs2, imm, rs1): return s_type(imm, rs2, rs1, 0b001, OPC_STORE)
def LW(rd, imm, rs1): return i_type(imm, rs1, 0b010, rd, OPC_LOAD)
def BEQ(rs1, rs2, imm): return b_type(imm, rs2, rs1, 0b000, OPC_BRANCH)
def LUI(rd, imm20): return u_type(imm20, rd, OPC_LUI)
def AUIPC(rd, imm20): return u_type(imm20, rd, OPC_AUIPC)
def JAL(rd, imm): return j_type(imm, rd, OPC_JAL)
def JALR(rd, rs1, imm): return i_type(imm, rs1, 0b000, rd, OPC_JALR)
def CSRRW(rd, csr, rs1): return i_type(csr, rs1, 0b001, rd, OPC_SYSTEM)
def CSRRS(rd, csr, rs1): return i_type(csr, rs1, 0b010, rd, OPC_SYSTEM)
def CSRRC(rd, csr, rs1): return i_type(csr, rs1, 0b011, rd, OPC_SYSTEM)
def CSRRWI(rd, csr, imm5): return i_type(csr, imm5, 0b101, rd, OPC_SYSTEM)
def CSRRSI(rd, csr, imm5): return i_type(csr, imm5, 0b110, rd, OPC_SYSTEM)
def CSRRCI(rd, csr, imm5): return i_type(csr, imm5, 0b111, rd, OPC_SYSTEM)
def MRET(): return i_type(0x302, 0, 0b000, 0, OPC_SYSTEM)

# CSR addresses (see tinymcu_cpu_csrfile.vhd / README.md "Implemented CSRs")
CSR_MSTATUS = 0x300
CSR_MIE = 0x304
CSR_MTVEC = 0x305
CSR_MSCRATCH = 0x340
CSR_MEPC = 0x341
CSR_MCAUSE = 0x342
CSR_MTVAL = 0x343
CSR_MIP = 0x344
CSR_MVENDORID = 0xF11
CSR_MARCHID = 0xF12
CSR_MIMPID = 0xF13
