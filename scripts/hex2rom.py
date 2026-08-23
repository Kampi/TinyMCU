#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later

"""Writes an Intel HEX file's contents into rtl/core/tinymcu_imem_bootrom.vhd's
PROGRAM constant, replacing whatever was there before.

Splices the generated VHDL between the TINYMCU_PROGRAM_BEGIN/_END marker
comments in the target file (see rtl/core/tinymcu_imem_bootrom.vhd and
lib/rom_writer.py) rather than regenerating the whole file, so everything
else in it (entity, generics, comments) is left untouched.

Usage:
    hex2rom.py <hexfile> [--vhdl-file PATH] [--max-words N]
"""

import argparse
import sys
from pathlib import Path

from lib.rom_writer import DEFAULT_VHDL_FILE, generate_program_block, splice_vhdl

DEFAULT_MAX_WORDS = 1024  # matches tinymcu_imem_bootrom's default ADDR_WIDTH => 10 (2**10 words)


def parse_intel_hex(path):
    """Returns a sparse {byte_address: byte_value} dict."""
    mem = {}
    base_addr = 0
    seen_eof = False

    with open(path, "r") as f:
        for lineno, raw_line in enumerate(f, 1):
            line = raw_line.strip()
            if not line:
                continue
            if not line.startswith(":"):
                raise ValueError(f"{path}:{lineno}: line does not start with ':'")

            try:
                data = bytes.fromhex(line[1:])
            except ValueError as exc:
                raise ValueError(f"{path}:{lineno}: invalid hex data: {exc}") from exc
            if len(data) < 5:
                raise ValueError(f"{path}:{lineno}: record too short")

            byte_count = data[0]
            addr16 = (data[1] << 8) | data[2]
            rec_type = data[3]
            payload = data[4:4 + byte_count]
            checksum = data[4 + byte_count]

            if len(payload) != byte_count:
                raise ValueError(f"{path}:{lineno}: byte count does not match record length")
            calc_checksum = (-sum(data[:4 + byte_count])) & 0xFF
            if calc_checksum != checksum:
                raise ValueError(f"{path}:{lineno}: checksum mismatch "
                                  f"(got 0x{checksum:02X}, expected 0x{calc_checksum:02X})")

            if rec_type == 0x00:  # Data
                for i, b in enumerate(payload):
                    mem[base_addr + addr16 + i] = b
            elif rec_type == 0x01:  # End Of File
                seen_eof = True
                break
            elif rec_type == 0x02:  # Extended Segment Address
                base_addr = ((payload[0] << 8) | payload[1]) << 4
            elif rec_type == 0x04:  # Extended Linear Address
                base_addr = ((payload[0] << 8) | payload[1]) << 16
            elif rec_type in (0x03, 0x05):  # Start Segment/Linear Address: entry point, not memory content
                pass
            else:
                raise ValueError(f"{path}:{lineno}: unsupported record type 0x{rec_type:02X}")

    if not seen_eof:
        raise ValueError(f"{path}: missing End Of File record")
    return mem


def bytes_to_words(mem, max_words):
    """Packs a sparse byte dict into a list of 32-bit little-endian words,
    covering address 0 up to the highest address present. Missing bytes
    within that range default to 0x00."""
    if not mem:
        return []

    max_addr = max(mem)
    n_words = (max_addr // 4) + 1
    if n_words > max_words:
        raise ValueError(
            f"program needs {n_words} words (up to byte address 0x{max_addr:X}), "
            f"exceeds --max-words={max_words}"
        )

    words = []
    for w in range(n_words):
        base = w * 4
        b0 = mem.get(base, 0)
        b1 = mem.get(base + 1, 0)
        b2 = mem.get(base + 2, 0)
        b3 = mem.get(base + 3, 0)
        words.append((b3 << 24) | (b2 << 16) | (b1 << 8) | b0)
    return words


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("hexfile", type=Path, help="Intel HEX file to write into the ROM")
    parser.add_argument("--vhdl-file", type=Path, default=DEFAULT_VHDL_FILE,
                         help=f"target VHDL file (default: {DEFAULT_VHDL_FILE})")
    parser.add_argument("--max-words", type=int, default=DEFAULT_MAX_WORDS,
                         help=f"reject the program if it needs more than this many 32-bit "
                              f"words -- must match the ROM's ADDR_WIDTH generic "
                              f"(2**ADDR_WIDTH), default: {DEFAULT_MAX_WORDS}")
    args = parser.parse_args()

    try:
        mem = parse_intel_hex(args.hexfile)
        words = bytes_to_words(mem, args.max_words)
        if not words:
            raise ValueError(f"{args.hexfile}: no data records found")
        program_block = generate_program_block(words)
        splice_vhdl(args.vhdl_file, program_block)
    except (ValueError, OSError) as exc:
        print(f"error: {exc}", file=sys.stderr)
        sys.exit(1)

    print(f"Wrote {len(words)} word(s) from {args.hexfile} into {args.vhdl_file}")
    sys.exit(0)
