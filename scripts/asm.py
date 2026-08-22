#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later

"""Tiny RV32I assembler that defines TinyMCU's hand-assembled demo/test
program -- and, from that same definition, both places that need to agree
with it: rtl/core/tinymcu_imem_bootrom.vhd (the ROM content) and
sim/tinymcu_tb_imem.vhd (the register checks that verify it ran
correctly). The program is written once, in this file, as emit()/chk()
calls; the ROM and the testbench are generated from it, so they cannot
drift apart from each other -- change the program here and re-run, and
both downstream files stay in sync.

Instruction encoders and opcode/CSR-address constants live in
lib/riscv_isa.py (shared with asm_irq.py); see there for encoding details
and the "not a general-purpose assembler" caveat. chk() calls are placed
wherever a register's value actually becomes final during emission (which
is not necessarily where it's first written -- e.g. x1 is set once early
and then again, incrementally, near the end); generate_checks_block()
sorts them into register order (x1, x2, ...) for the generated file, so
call order here only needs to match program order, not presentation order.

Writes into rtl/core/tinymcu_imem_bootrom.vhd's PROGRAM constant (between the
TINYMCU_PROGRAM_BEGIN/_END markers) and sim/tinymcu_tb_imem.vhd's check()
calls (between TINYMCU_CHECKS_BEGIN/_END), both via lib/rom_writer.py --
the same PROGRAM marker scripts/hex2rom.py writes compiled programs to,
just from hand-assembled instructions instead of an Intel HEX file
(hex2rom.py has no equivalent for the checks side, since it has no way to
know what a compiled program's register values are supposed to be).

Usage:
    asm.py [--vhdl-file PATH] [--tb-file PATH]
"""

import argparse
import sys
from pathlib import Path

from lib.riscv_isa import (
    ADDI, ADD, SUB, SW, SB, SH, LW, BEQ, LUI, AUIPC, JAL, JALR,
    CSRRW, CSRRS, CSRRC, CSRRWI,
    CSR_MSCRATCH, CSR_MVENDORID, CSR_MARCHID, CSR_MIMPID,
)
from lib.rom_writer import (
    DEFAULT_TB_FILE,
    DEFAULT_VHDL_FILE,
    CHECKS_MARKER_BEGIN,
    CHECKS_MARKER_END,
    generate_checks_block,
    generate_program_block,
    splice_vhdl,
)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--vhdl-file", type=Path, default=DEFAULT_VHDL_FILE,
                         help=f"target ROM VHDL file (default: {DEFAULT_VHDL_FILE})")
    parser.add_argument("--tb-file", type=Path, default=DEFAULT_TB_FILE,
                         help=f"target testbench VHDL file (default: {DEFAULT_TB_FILE})")
    args = parser.parse_args()

    prog = []
    checks = []

    def emit(instr, comment=""):
        prog.append((instr, comment))

    def addr():
        return len(prog) * 4

    def chk(reg, value, name):
        checks.append((name, reg, value))

    emit(ADDI(1, 0, 5), "addi x1, x0, 5")
    emit(ADDI(2, 0, 10), "addi x2, x0, 10")
    chk(2, 10, "x2  (10)")
    emit(ADD(3, 1, 2), "add  x3, x1, x2")
    chk(3, 15, "x3  (x1+x2)")
    emit(SUB(4, 2, 1), "sub  x4, x2, x1")
    chk(4, 5, "x4  (x2-x1)")

    # RAM lives at 0x0200_0000..0x02FF_FFFF (see tinymcu_addr_decoder.vhd
    # / tinymcu_pkg.vhd's RAM_BASE/RAM_END), not near address 0 -- x21
    # holds that base for every SW/LW/SB/SH below (x0-relative addressing
    # would land in the Boot-ROM/Flash region and never ack a write).
    emit(LUI(21, 0x02000), "lui  x21, 0x02000  (RAM base 0x02000000)")
    chk(21, 0x02000000, "x21 (RAM base)")

    emit(SW(3, 0, 21), "sw   x3, 0(x21)")
    emit(LW(5, 0, 21), "lw   x5, 0(x21)")
    chk(5, 15, "x5  (lw mem[0])")
    emit(BEQ(1, 4, 8), "beq  x1, x4, +8")
    emit(ADDI(6, 0, 111), "addi x6, x0, 111  (skipped)")
    chk(6, 0, "x6  (beq skip)")
    emit(ADDI(7, 0, 42), "addi x7, x0, 42")
    chk(7, 42, "x7  (42)")
    emit(LUI(8, 1), "lui  x8, 0x1")
    chk(8, 1 << 12, "x8  (lui 0x1)")
    emit(JAL(9, 8), "jal  x9, +8")
    chk(9, addr(), "x9  (jal link)")  # addr() already points past the jal, i.e. its own pc + 4
    emit(ADDI(10, 0, 999), "addi x10, x0, 999 (skipped)")
    chk(10, 0, "x10 (jal skip)")
    emit(ADDI(1, 1, 1), "addi x1, x1, 1")
    chk(1, 6, "x1  (5+1)")  # final value: 5 (first addi) + 1 (this one)

    jalr_base_instr_addr = addr() + 4  # address of the jalr instruction itself
    emit(ADDI(11, 0, jalr_base_instr_addr), f"addi x11, x0, {hex(jalr_base_instr_addr)}")
    chk(11, jalr_base_instr_addr, "x11 (jalr base)")
    jalr_addr = addr()
    emit(JALR(12, 11, 8), "jalr x12, x11, 8")
    chk(12, jalr_addr + 4, "x12 (jalr link)")
    emit(ADDI(13, 0, 777), "addi x13, x0, 777 (skipped)")
    chk(13, 0, "x13 (jalr skip)")
    emit(ADDI(14, 0, 55), "addi x14, x0, 55  (landing point)")
    chk(14, 55, "x14 (jalr landing point)")

    auipc_addr = addr()
    emit(AUIPC(15, 1), "auipc x15, 1")
    chk(15, auipc_addr + (1 << 12), "x15 (auipc pc+0x1000)")

    emit(ADDI(16, 0, 0xAA), "addi x16, x0, 0xAA")
    chk(16, 0xAA, "x16 (0xAA)")
    emit(SB(16, 4, 21), "sb   x16, 4(x21)")
    emit(ADDI(17, 0, -1), "addi x17, x0, -1")
    chk(17, 0xFFFFFFFF, "x17 (-1)")
    emit(SB(17, 5, 21), "sb   x17, 5(x21)")
    emit(LW(18, 4, 21), "lw   x18, 4(x21)")
    chk(18, 0xFFAA, "x18 (lw after 2x sb)")
    emit(ADDI(19, 0, 0x3CD), "addi x19, x0, 0x3CD")
    chk(19, 0x3CD, "x19 (0x3CD)")
    emit(SH(19, 8, 21), "sh   x19, 8(x21)")
    emit(LW(20, 8, 21), "lw   x20, 8(x21)")
    chk(20, 0x3CD, "x20 (lw after sh)")

    # CSRRW round-trip against mscratch (see tinymcu_cpu_csrfile.vhd):
    # x23 gets mscratch's value from BEFORE this write (0, its reset
    # value, since nothing wrote it earlier), and mscratch becomes x22.
    emit(ADDI(22, 0, 0x123), "addi x22, x0, 0x123")
    emit(CSRRW(23, CSR_MSCRATCH, 22), "csrrw x23, mscratch, x22")
    chk(23, 0, "x23 (csrrw old mscratch)")
    # Second csrrw with rs1=x0 reads back what the first one wrote (proves
    # the write actually happened, not just that reads return 0) and
    # clears mscratch again.
    emit(CSRRW(24, CSR_MSCRATCH, 0), "csrrw x24, mscratch, x0")
    chk(24, 0x123, "x24 (csrrw read back mscratch)")

    # csrrs: mscratch is 0 here (previous csrrw cleared it). Sets bits
    # 0xF0, then a second csrrs with rs1=x0 (or with 0 = no change) reads
    # them back to prove the set really happened.
    emit(ADDI(25, 0, 0xF0), "addi x25, x0, 0xF0")
    emit(CSRRS(26, CSR_MSCRATCH, 25), "csrrs x26, mscratch, x25")
    chk(26, 0, "x26 (csrrs old mscratch)")
    emit(CSRRS(27, CSR_MSCRATCH, 0), "csrrs x27, mscratch, x0")
    chk(27, 0xF0, "x27 (csrrs read back mscratch)")

    # csrrc: mscratch is 0xF0 here. Clears bits 0x30 (a subset of 0xF0),
    # leaving 0xC0; a second csrrc with rs1=x0 (and not 0 = no change)
    # reads that back.
    emit(ADDI(28, 0, 0x30), "addi x28, x0, 0x30")
    emit(CSRRC(29, CSR_MSCRATCH, 28), "csrrc x29, mscratch, x28")
    chk(29, 0xF0, "x29 (csrrc old mscratch)")
    emit(CSRRC(30, CSR_MSCRATCH, 0), "csrrc x30, mscratch, x0")
    chk(30, 0xC0, "x30 (csrrc read back mscratch)")

    # csrrwi: mscratch is 0xC0 here; the *I variants take a 5-bit
    # zero-extended immediate instead of rs1, exercising that separate
    # decode path (imm5 in tinymcu_cpu.vhd's "CSR operations" process).
    emit(CSRRWI(31, CSR_MSCRATCH, 5), "csrrwi x31, mscratch, 5")
    chk(31, 0xC0, "x31 (csrrwi old mscratch)")

    # mvendorid/marchid/mimpid are read-only, hardwired to 0 (see
    # tinymcu_cpu_csrfile.vhd). x22/x25/x28 are free again here: their
    # earlier role (holding a value for a csrrw/csrrs/csrrc source
    # register above) is long done by this point in program order, and
    # no chk() was ever registered for their old values -- checks only
    # observe each register's value at the very end of the program, not
    # at intermediate points. rs1=x1 (=6, non-zero) attempts a write on
    # each, to prove it's ignored, not just that reads happen to be 0.
    emit(CSRRW(22, CSR_MVENDORID, 1), "csrrw x22, mvendorid, x1  (read-only, write ignored)")
    chk(22, 0, "x22 (mvendorid)")
    emit(CSRRW(25, CSR_MARCHID, 1), "csrrw x25, marchid, x1  (read-only, write ignored)")
    chk(25, 0, "x25 (marchid)")
    emit(CSRRW(28, CSR_MIMPID, 1), "csrrw x28, mimpid, x1  (read-only, write ignored)")
    chk(28, 0, "x28 (mimpid)")

    emit(JAL(0, 0), "jal  x0, 0 (halt)")

    print(f"Program length: {len(prog)} instructions, {len(prog) * 4} bytes")
    print(f"jalr target = {hex((jalr_base_instr_addr + 8) & ~1)}, "
          f"expected x12 (link) = {hex(jalr_addr + 4)}")
    print(f"auipc pc = {hex(auipc_addr)}, expected x15 = {hex(auipc_addr + (1 << 12))}")

    words = [w for w, _ in prog]
    comments = [f"{i * 4:#04x}: {c}" for i, (_, c) in enumerate(prog)]
    program_block = generate_program_block(words, comments)
    checks_block = generate_checks_block(checks)

    try:
        splice_vhdl(args.vhdl_file, program_block)
        splice_vhdl(args.tb_file, checks_block, CHECKS_MARKER_BEGIN, CHECKS_MARKER_END)
    except (ValueError, OSError) as exc:
        print(f"error: {exc}", file=sys.stderr)
        sys.exit(1)

    print(f"Wrote {len(words)} word(s) into {args.vhdl_file}")
    print(f"Wrote {len(checks)} check(s) into {args.tb_file}")
    sys.exit(0)


