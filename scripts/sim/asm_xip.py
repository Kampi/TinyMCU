#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later

"""Boot-ROM program for sim/core/tinymcu_tb_xip_cpu.vhd.

Runs the XIP controller through the full CPU pipeline (not just the
standalone unit, see sim/core/tinymcu_tb_xip.vhd for that): the CPU
starts executing from the Boot ROM, configures tinymcu_imem_xip.vhd's
CONFIG register (CPHA=0, CPOL=0, CLKDIV=0, ENABLE=1), then jumps into
the XIP flash window, where tinymcu_tb_xip_cpu.vhd's own simulated SPI
flash model supplies a second, short program fetched entirely over the
XIP bus.

sim/core/tinymcu_tb_xip_cpu.vhd's register checks and its simulated
flash program are hardwired to this exact boot sequence, so unlike
asm.py this script does not generate a checks block; this file and the
testbench must be kept in sync by hand if either changes.

Program layout (word index -> byte address), for reference

    0x00: lui  x1, 0x04000
    0x04: addi x1, x1, 0x300  (x1 = 0x04000300, XIP CONFIG)
    0x08: addi x2, x0, 4      (ENABLE=1, CPHA=0, CPOL=0, CLKDIV=0)
    0x0C: sw   x2, 0(x1)      (CONFIG <= 0x00000004)
    0x10: lui  x3, 0x8        (x3 = 0x00008000, XIP_FLASH_BASE)
    0x14: jalr x0, x3, 0      (jump into flash)

Usage:
    asm_xip.py [--vhdl-file PATH]
"""

import argparse
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from lib.riscv_isa import LUI, ADDI, SW, JALR
from lib.rom_writer import DEFAULT_VHDL_FILE, generate_program_block, splice_vhdl


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--vhdl-file", type=Path, default=DEFAULT_VHDL_FILE,
                         help=f"target ROM VHDL file (default: {DEFAULT_VHDL_FILE})")
    args = parser.parse_args()

    prog = []

    def emit(instr, comment=""):
        prog.append((instr, comment))

    emit(LUI(1, 0x04000), "lui  x1, 0x04000")
    emit(ADDI(1, 1, 0x300), "addi x1, x1, 0x300  (x1 = 0x04000300, XIP CONFIG)")
    emit(ADDI(2, 0, 4), "addi x2, x0, 4       (ENABLE=1, CPHA=0, CPOL=0, CLKDIV=0)")
    emit(SW(2, 0, 1), "sw   x2, 0(x1)       (CONFIG <= 0x00000004)")
    emit(LUI(3, 0x8), "lui  x3, 0x8         (x3 = 0x00008000, XIP_FLASH_BASE)")
    emit(JALR(0, 3, 0), "jalr x0, x3, 0       (jump into flash)")

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
