# SPDX-License-Identifier: GPL-3.0-or-later

"""Shared helpers for writing generated content into VHDL files between a
pair of marker comments, without disturbing anything else in the file.
Used by:
  - asm.py (hand assembler) and hex2rom.py (compiled programs, via Intel
    HEX) to write rtl/core/tinymcu_imem_bootrom.vhd's PROGRAM constant
    (PROGRAM_MARKER_BEGIN/_END).
  - asm.py to also write sim/tinymcu_tb_imem.vhd's check(...) calls
    (CHECKS_MARKER_BEGIN/_END), so the hand-assembled demo program and
    the testbench that checks it can never drift apart from each other.
"""

import re
from pathlib import Path

PROGRAM_MARKER_BEGIN = "-- TINYMCU_PROGRAM_BEGIN"
PROGRAM_MARKER_END = "-- TINYMCU_PROGRAM_END"

CHECKS_MARKER_BEGIN = "-- TINYMCU_CHECKS_BEGIN"
CHECKS_MARKER_END = "-- TINYMCU_CHECKS_END"

# Backwards-compatible aliases (hex2rom.py imports these names).
MARKER_BEGIN = PROGRAM_MARKER_BEGIN
MARKER_END = PROGRAM_MARKER_END

DEFAULT_VHDL_FILE = Path(__file__).resolve().parent.parent.parent / "rtl" / "core" / "tinymcu_imem_bootrom.vhd"
DEFAULT_TB_FILE = Path(__file__).resolve().parent.parent.parent / "sim" / "tinymcu_tb_imem.vhd"


def generate_program_block(words, comments=None):
    """words: list of 32-bit ints, in address order starting at 0.
    comments: optional list of per-word comment strings (same length as
    words); each defaults to the word's byte address if omitted."""
    n = len(words)
    idx_width = max(len(str(n - 1)), 1)
    lines = [f"        constant PROGRAM : mem_array_t(0 to {n - 1}) := ("]
    for i, w in enumerate(words):
        sep = "," if i < n - 1 else ""
        comment = comments[i] if comments else f"0x{i * 4:04X}"
        lines.append(f'            {i:<{idx_width}d} => x"{w:08X}"{sep} -- {comment}')
    lines.append("        );")
    return "\n".join(lines)


def generate_checks_block(checks):
    """checks: list of (name, reg_index, expected_value) tuples. Emitted
    sorted by reg_index (x1, x2, ...), regardless of the order the
    caller collected them in: a value is often only final several
    instructions after the register is first touched (e.g. "addi x1,
    x1, 1" long after the initial "addi x1, x0, 5"), so callers record
    each check where its value actually becomes final, not in register
    order."""
    lines = []
    for name, reg, value in sorted(checks, key=lambda c: c[1]):
        lines.append(f'        check("{name}", dbg_regs({reg}), x"{value & 0xFFFFFFFF:08X}", errors);')
    return "\n".join(lines)


def splice_vhdl(vhdl_path, block, marker_begin=PROGRAM_MARKER_BEGIN, marker_end=PROGRAM_MARKER_END):
    text = vhdl_path.read_text()
    pattern = re.compile(re.escape(marker_begin) + r".*?" + re.escape(marker_end), re.DOTALL)
    if not pattern.search(text):
        raise ValueError(
            f"{vhdl_path}: markers {marker_begin!r}/{marker_end!r} not found; "
            f"is this the right file, and does it still have both marker comments?"
        )

    replacement = (
        f"{marker_begin} (auto-generated, do not edit by hand)\n"
        f"{block}\n"
        f"        {marker_end}"
    )
    new_text = pattern.sub(replacement, text, count=1)
    vhdl_path.write_text(new_text)
