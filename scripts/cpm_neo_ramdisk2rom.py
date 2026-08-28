#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later

"""Bakes a CP/M Neo disk image into rtl/core/tinymcu_sram_generic.vhd's
DISK constant, the same way hex2rom.py bakes a program into the Boot ROM.

TinyMCU has no SPI/SD/flash controller yet, so sw/cpm-neo/platform/tinymcu/
bios.c's bios_read()/bios_write() are backed by TinyMCU's own SRAM
instead. Its own independent block at TINYMCU_RAMDISK_BASE (bios.c),
decoded at its own top-byte window (tinymcu_addr_decoder.vhd's
RAMDISK_TOP_BYTE), separate from the kernel/TPA's own SRAM block. This
script is what actually gets a real disk image's bytes into that window
on real hardware: it writes into tinymcu_sram_generic.vhd's DISK
constant, which every one of the four DATA_WIDTH=8 byte-lane instances
(tinymcu_sram.vhd's ram_gen loop) slices its own initial content from.

Only meaningful for sw/cpm-neo/. This is not a general-purpose tool like
hex2rom.py/rom2hex.py, hence its own script rather than a flag on those.
sw/cpm-neo/Makefile's "make ramdisk" target is the usual way to run this
It passes --max-words derived from rtl/core/tinymcu_cpu.vhd's
RAMDISK_ADDR_WIDTH generic, so the two can't silently drift apart. Only
rely on this script's own DEFAULT_MAX_WORDS below when running it
standalone.

Usage:
    cpm_neo_ramdisk2rom.py [image] [--vhdl-file PATH] [--max-words N]

image defaults to sw/cpm-neo/sysgen/build/disk.img (sysgen new's output).
The image is taken byte-for-byte from its start; this script errors out
rather than silently truncating an oversized one, which would otherwise
corrupt whatever landed at the cut point (kernel image, directory
blocks, ...).
"""

import argparse
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from lib.rom_writer import DISK_MARKER_BEGIN, DISK_MARKER_END, generate_program_block, splice_vhdl

REPO_ROOT = Path(__file__).resolve().parent.parent
DEFAULT_IMAGE = REPO_ROOT / "sw" / "cpm-neo" / "sysgen" / "build" / "disk.img"
DEFAULT_VHDL_FILE = REPO_ROOT / "rtl" / "core" / "tinymcu_sram_generic.vhd"

# 128 KB RAM disk / 4 bytes per word. Matches bios.c's
# TINYMCU_RAMDISK_SECTORS (256 * 512 B = 128 KB) for the default
# RAMDISK_ADDR_WIDTH=15 (rtl/core/tinymcu_cpu.vhd, see
# sw/cpm-neo/Makefile). Only a fallback for standalone use -- "make
# ramdisk" always overrides this via --max-words.
DEFAULT_MAX_WORDS = 32768


def bytes_to_words(data):
    """Packs raw bytes into 32-bit little-endian words, zero-padding the
    final word if the length isn't a multiple of 4."""
    if len(data) % 4:
        data = data + b"\x00" * (4 - len(data) % 4)
    return [
        data[i] | (data[i + 1] << 8) | (data[i + 2] << 16) | (data[i + 3] << 24)
        for i in range(0, len(data), 4)
    ]


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("image", type=Path, nargs="?", default=DEFAULT_IMAGE,
                         help=f"disk image to write into the RAM disk (default: {DEFAULT_IMAGE})")
    parser.add_argument("--vhdl-file", type=Path, default=DEFAULT_VHDL_FILE,
                         help=f"target VHDL file (default: {DEFAULT_VHDL_FILE})")
    parser.add_argument("--max-words", type=int, default=DEFAULT_MAX_WORDS,
                         help=f"reject the image if it needs more than this many 32-bit "
                              f"words -- must match tinymcu_sram_generic.vhd's DISK_OFFSET "
                              f"budget and bios.c's TINYMCU_RAMDISK_SECTORS, "
                              f"default: {DEFAULT_MAX_WORDS}")
    args = parser.parse_args()

    try:
        data = args.image.read_bytes()
        if not data:
            raise ValueError(f"{args.image}: empty file")

        words = bytes_to_words(data)
        if len(words) > args.max_words:
            raise ValueError(
                f"{args.image}: needs {len(words)} words ({len(data)} bytes), "
                f"exceeds --max-words={args.max_words} ({args.max_words * 4} bytes). "
                f"Build a smaller image (sysgen new --no-sys --no-extra skips both "
                f"the bundled system and optional apps), add specific files by hand "
                f"instead of the full app bundle, or grow the RAM disk's budget if "
                f"the target FPGA's BRAM allows it (see sw/cpm-neo/Makefile's "
                f"RAMDISK_ADDR_WIDTH)."
            )

        comments = [f"0x{0x03000000 + i * 4:08X}" for i in range(len(words))]
        program_block = generate_program_block(
            words, comments=comments,
            const_name="DISK", type_name="tinymcu.tinymcu_pkg.mem_array_t",
        )
        splice_vhdl(args.vhdl_file, program_block,
                    marker_begin=DISK_MARKER_BEGIN, marker_end=DISK_MARKER_END)
    except (ValueError, OSError) as exc:
        print(f"error: {exc}", file=sys.stderr)
        sys.exit(1)

    print(f"Wrote {len(words)} word(s) from {args.image} into {args.vhdl_file}")
    sys.exit(0)
