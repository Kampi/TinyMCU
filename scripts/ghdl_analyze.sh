#!/usr/bin/env bash
# Analyzes a set of VHDL files into a GHDL library without requiring
# them to be listed in dependency order: files are analyzed in passes,
# and a file that fails only because one of its dependencies hasn't been
# analyzed yet is simply deferred to the next pass, until either every
# file has succeeded or a whole pass makes no further progress (which
# means a real error, not just an ordering issue).
#
# Usage:
#   ghdl_analyze.sh <ghdl-flag> [<ghdl-flag> ...] -- <file.vhd> [<file.vhd> ...]
#
# Everything before "--" is passed through to "ghdl -a" as-is (e.g.
# --std=08, --workdir=..., -P..., --work=...); everything after "--" is
# the (unordered) list of files to analyze.
set -euo pipefail

ghdl_args=()
while [[ $# -gt 0 && "$1" != "--" ]]; do
    ghdl_args+=("$1")
    shift
done
if [[ $# -eq 0 ]]; then
    echo "ghdl_analyze.sh: missing '--' separator before the file list" >&2
    exit 1
fi
shift # drop the --
remaining=("$@")

err_log=$(mktemp)
trap 'rm -f "$err_log"' EXIT

pass=0
while [[ ${#remaining[@]} -gt 0 ]]; do
    pass=$((pass + 1))
    next_remaining=()
    progressed=0

    for f in "${remaining[@]}"; do
        if ghdl -a "${ghdl_args[@]}" "$f" 2>"$err_log"; then
            progressed=1
        else
            next_remaining+=("$f")
        fi
    done

    if [[ $progressed -eq 0 ]]; then
        echo "error: could not resolve an analysis order for:" >&2
        for f in "${next_remaining[@]}"; do
            echo "  $f" >&2
        done
        echo "--- last error (from $f) ---" >&2
        cat "$err_log" >&2
        exit 1
    fi

    remaining=("${next_remaining[@]}")
done
