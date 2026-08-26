#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later

"""Hand-assembled IRQ/MRET round-trip test program for
sim/core/tinymcu_tb_irq.vhd.

sim/core/tinymcu_tb_irq.vhd's register checks (x6 = 222, x7 > 0) are
hardwired to this exact program (see its header comment for the expected
layout), so unlike asm.py this script does not generate a checks block;
the program here and the testbench must be kept in sync by hand if
either changes.

Program layout (word index -> byte address), for reference -- kept here as
prose, not regenerated: if the emit() calls below change, re-run this
script to update the ROM, and update this table (and tinymcu_tb_irq.vhd's
own copy) by hand too.

    0x00: addi x1, x0, 0x40       (handler address)
    0x04: csrrw x0, mtvec, x1
    0x08: addi x2, x0, 8  (MIE bit)
    0x0C: csrrw x0, mstatus, x2  (mstatus.MIE = 1)
    0x10: lui  x3, 1
    0x14: addi x3, x3, -2048  (x3 = 0x800, MEIE bit)
    0x18: csrrw x0, mie, x3  (mie.MEIE = 1)
    0x1C: loop: addi x7, x7, 1
    0x20: jal  x0, loop
    0x24-0x3C: nop (padding up to the handler address)
    0x40: handler: addi x6, x0, 222  (marker: handler ran)
    0x44: mret

Usage:
    asm_irq.py [--vhdl-file PATH]
"""

import argparse
import sys
from pathlib import Path

from lib.riscv_isa import ADDI, LUI, CSRRW, JAL, MRET, CSR_MSTATUS, CSR_MIE, CSR_MTVEC
from lib.rom_writer import DEFAULT_VHDL_FILE, generate_program_block, splice_vhdl


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--vhdl-file", type=Path, default=DEFAULT_VHDL_FILE,
                         help=f"target ROM VHDL file (default: {DEFAULT_VHDL_FILE})")
    args = parser.parse_args()

    prog = []

    def emit(instr, comment=""):
        prog.append((instr, comment))

    def addr():
        return len(prog) * 4

    def pad_to(word_index):
        while len(prog) < word_index:
            emit(ADDI(0, 0, 0), "nop (padding)")

    HANDLER_ADDR = 0x40  # word index 16, see sim/core/tinymcu_tb_irq.vhd's header

    emit(ADDI(1, 0, HANDLER_ADDR), f"addi x1, x0, {hex(HANDLER_ADDR)}  (handler address)")
    emit(CSRRW(0, CSR_MTVEC, 1), "csrrw x0, mtvec, x1")
    emit(ADDI(2, 0, 1 << 3), "addi x2, x0, 8  (MIE bit)")
    emit(CSRRW(0, CSR_MSTATUS, 2), "csrrw x0, mstatus, x2  (mstatus.MIE = 1)")
    emit(LUI(3, 1), "lui  x3, 1")
    emit(ADDI(3, 3, -2048), "addi x3, x3, -2048  (x3 = 0x800, MEIE bit)")
    emit(CSRRW(0, CSR_MIE, 3), "csrrw x0, mie, x3  (mie.MEIE = 1)")

    loop_addr = addr()
    emit(ADDI(7, 7, 1), "loop: addi x7, x7, 1")
    emit(JAL(0, loop_addr - addr()), "jal  x0, loop")

    pad_to(HANDLER_ADDR // 4)
    assert addr() == HANDLER_ADDR, f"padding landed at {hex(addr())}, expected {hex(HANDLER_ADDR)}"

    emit(ADDI(6, 0, 222), "handler: addi x6, x0, 222  (marker: handler ran)")
    emit(MRET(), "mret")

    print(f"Program length: {len(prog)} instructions, {len(prog) * 4} bytes")
    print(f"Handler at {hex(HANDLER_ADDR)}, loop body at {hex(loop_addr)}")

    words = [w for w, _ in prog]
    comments = [f"{i * 4:#04x}: {c}" for i, (_, c) in enumerate(prog)]
    program_block = generate_program_block(words, comments)

    try:
        splice_vhdl(args.vhdl_file, program_block)
    except (ValueError, OSError) as exc:
        print(f"error: {exc}", file=sys.stderr)
        sys.exit(1)

    print(f"Wrote {len(words)} word(s) into {args.vhdl_file}")
    sys.exit(0)
