#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later

"""Reads rtl/core/tinymcu_imem_bootrom.vhd's PROGRAM constant and writes its
contents out as an Intel HEX file -- the reverse of hex2rom.py. Useful
for snapshotting whatever program is currently embedded in the ROM
before overwriting it with a new one.

Usage:
    rom2hex.py [output.hex] [--vhdl-file PATH]
"""

import argparse
import re
import sys
from pathlib import Path

from lib.rom_writer import DEFAULT_VHDL_FILE, PROGRAM_MARKER_BEGIN as MARKER_BEGIN, PROGRAM_MARKER_END as MARKER_END

DEFAULT_OUTPUT = Path("sw/imem_backup.hex")
WORD_RE = re.compile(r'x"([0-9A-Fa-f]{8})"')


def extract_words(vhdl_path):
    text = vhdl_path.read_text()
    pattern = re.compile(re.escape(MARKER_BEGIN) + r"(.*?)" + re.escape(MARKER_END), re.DOTALL)
    m = pattern.search(text)
    if not m:
        raise ValueError(f"{vhdl_path}: markers {MARKER_BEGIN!r}/{MARKER_END!r} not found")
    return [int(h, 16) for h in WORD_RE.findall(m.group(1))]


def write_intel_hex(path, words, bytes_per_record=16):
    data = bytearray()
    for w in words:
        data += w.to_bytes(4, "little")

    with open(path, "w") as f:
        for i in range(0, len(data), bytes_per_record):
            chunk = data[i:i + bytes_per_record]
            addr16 = i & 0xFFFF
            record = bytes([len(chunk), (addr16 >> 8) & 0xFF, addr16 & 0xFF, 0x00]) + chunk
            checksum = (-sum(record)) & 0xFF
            f.write(":" + record.hex().upper() + f"{checksum:02X}\n")
        f.write(":00000001FF\n")  # End Of File record


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("output", type=Path, nargs="?", default=DEFAULT_OUTPUT,
                         help=f"output Intel HEX file (default: {DEFAULT_OUTPUT}, "
                              f"relative to the current directory)")
    parser.add_argument("--vhdl-file", type=Path, default=DEFAULT_VHDL_FILE,
                         help=f"source VHDL file (default: {DEFAULT_VHDL_FILE})")
    args = parser.parse_args()

    try:
        words = extract_words(args.vhdl_file)
        if not words:
            raise ValueError(f"{args.vhdl_file}: no PROGRAM entries found between markers")
        args.output.parent.mkdir(parents=True, exist_ok=True)
        write_intel_hex(args.output, words)
    except (ValueError, OSError) as exc:
        print(f"error: {exc}", file=sys.stderr)
        sys.exit(1)

    print(f"Wrote {len(words)} word(s) from {args.vhdl_file} into {args.output}")
    sys.exit(0)
