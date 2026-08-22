#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later

"""Sets rtl/tinymcu_pkg.vhd's MIMPID constant (the mimpid CSR's hardwired
value, see tinymcu_cpu_csrfile.vhd) from a release version string, so a
CI/CD release workflow can stamp the build's version into the CPU's
identification CSR without hand-editing VHDL.

RISC-V doesn't standardize mimpid's internal format (unlike mvendorid/
marchid, it's entirely vendor-defined), so this packs a semantic-version-
style MAJOR.MINOR.PATCH into the 32-bit word: MAJOR in bits 31:24 (0-255),
MINOR in bits 23:16 (0-255), PATCH in bits 15:0 (0-65535). Software can
recover it with:
    major = (mimpid >> 24) & 0xFF
    minor = (mimpid >> 16) & 0xFF
    patch = mimpid & 0xFFFF

Usage (typically from a CI/CD release job, not by hand):
    set_mimpid.py 1.4.2
    set_mimpid.py v1.4.2
    set_mimpid.py                 # falls back to $RELEASE_VERSION

Exits non-zero (and writes nothing) if the version string doesn't parse
as MAJOR.MINOR.PATCH or any part is out of range, so a malformed release
tag fails the CI job loudly instead of silently writing a wrong value.
"""

import argparse
import os
import re
import sys
from pathlib import Path

DEFAULT_PKG_FILE = Path(__file__).resolve().parent.parent / "rtl" / "tinymcu_pkg.vhd"

MARKER_BEGIN = "-- TINYMCU_MIMPID_BEGIN"
MARKER_END = "-- TINYMCU_MIMPID_END"

VERSION_RE = re.compile(r"^v?(\d+)\.(\d+)\.(\d+)$")


def parse_version(version):
    """version: e.g. "1.4.2" or "v1.4.2". Returns (major, minor, patch)."""
    m = VERSION_RE.match(version.strip())
    if not m:
        raise ValueError(f"{version!r} is not a MAJOR.MINOR.PATCH version (optionally prefixed with 'v')")
    major, minor, patch = (int(g) for g in m.groups())
    for name, value, limit in (("major", major, 0xFF), ("minor", minor, 0xFF), ("patch", patch, 0xFFFF)):
        if value > limit:
            raise ValueError(f"{name}={value} exceeds the field's range (0-{limit})")
    return major, minor, patch


def pack_mimpid(major, minor, patch):
    return (major << 24) | (minor << 16) | patch


def splice_mimpid(pkg_path, line):
    text = pkg_path.read_text()
    pattern = re.compile(re.escape(MARKER_BEGIN) + r".*?" + re.escape(MARKER_END), re.DOTALL)
    if not pattern.search(text):
        raise ValueError(
            f"{pkg_path}: markers {MARKER_BEGIN!r}/{MARKER_END!r} not found; "
            f"is this the right file, and does it still have both marker comments?"
        )
    replacement = f"{MARKER_BEGIN} (auto-generated, do not edit by hand)\n{line}\n    {MARKER_END}"
    new_text = pattern.sub(replacement, text, count=1)
    pkg_path.write_text(new_text)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("version", nargs="?", default=os.environ.get("RELEASE_VERSION"),
                         help="release version, e.g. 1.4.2 or v1.4.2 "
                              "(default: $RELEASE_VERSION environment variable)")
    parser.add_argument("--pkg-file", type=Path, default=DEFAULT_PKG_FILE,
                         help=f"target package file (default: {DEFAULT_PKG_FILE})")
    args = parser.parse_args()

    if not args.version:
        print("error: no version given (pass it as an argument or set $RELEASE_VERSION)", file=sys.stderr)
        sys.exit(1)

    try:
        major, minor, patch = parse_version(args.version)
    except ValueError as exc:
        print(f"error: {exc}", file=sys.stderr)
        sys.exit(1)

    value = pack_mimpid(major, minor, patch)
    line = (
        f'    constant MIMPID : std_ulogic_vector(31 downto 0) := x"{value:08X}";'
    )

    try:
        splice_mimpid(args.pkg_file, line)
    except (ValueError, OSError) as exc:
        print(f"error: {exc}", file=sys.stderr)
        sys.exit(1)

    print(f"Set MIMPID = 0x{value:08X} (v{major}.{minor}.{patch}) in {args.pkg_file}")
    sys.exit(0)
