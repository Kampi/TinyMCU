#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later

"""Hand-assembled M-extension pipeline test program for
sim/core/tinymcu_tb_mult_cpu.vhd.

Exercises the multiplier through the full CPU pipeline (not just the
standalone unit, see sim/core/tinymcu_tb_mult.vhd for that): a plain
multiply, an ordinary instruction immediately after it (checks the
multiply's result isn't lost/misdirected once the pipeline advances),
and a second multiply directly following that instruction (checks
mult_start re-triggers correctly back-to-back).

sim/core/tinymcu_tb_mult_cpu.vhd's register checks are hardwired to
this exact program, so unlike asm.py this script does not generate a
checks block; the program here and the testbench must be kept in sync by
hand if either changes.

Program layout (word index -> byte address), for reference -- kept here
as prose, not regenerated:

    0x00: addi x1, x0, 6
    0x04: addi x2, x0, 7
    0x08: mul  x3, x1, x2   (expect 42)
    0x0C: addi x4, x0, 111  (must land in x4, not be lost/misdirected)
    0x10: mul  x5, x2, x2   (expect 49; mult right after another instr)
    0x14: jal  x0, 0 (halt)

Usage:
    asm_mult.py [--vhdl-file PATH]
"""

import argparse
import sys
from pathlib import Path

from lib.riscv_isa import ADDI, MUL, JAL
from lib.rom_writer import DEFAULT_VHDL_FILE, generate_program_block, splice_vhdl


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--vhdl-file", type=Path, default=DEFAULT_VHDL_FILE,
                         help=f"target ROM VHDL file (default: {DEFAULT_VHDL_FILE})")
    args = parser.parse_args()

    prog = []

    def emit(instr, comment=""):
        prog.append((instr, comment))

    emit(ADDI(1, 0, 6), "addi x1, x0, 6")
    emit(ADDI(2, 0, 7), "addi x2, x0, 7")
    emit(MUL(3, 1, 2), "mul  x3, x1, x2   (expect 42)")
    emit(ADDI(4, 0, 111), "addi x4, x0, 111  (must land in x4, not be lost/misdirected)")
    emit(MUL(5, 2, 2), "mul  x5, x2, x2   (expect 49; mult right after another instr)")
    emit(JAL(0, 0), "jal  x0, 0 (halt)")

    print(f"Program length: {len(prog)} instructions, {len(prog) * 4} bytes")

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
