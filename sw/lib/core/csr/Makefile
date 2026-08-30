# TinyMCU - CSR driver: header-only (static inline functions), nothing
# to archive into a .a. This Makefile only compile-checks the header on
# its own, the same way sw/lib/core/trap/ and the peripheral drivers get
# their own Makefile.
#
# Usage:
#   make       - compile-check tinymcu_csr.h (build/check.o)
#   make clean - clean the build
#
# Requires a RISC-V GCC cross-compiler on PATH. Override CROSS/ARCH the
# same way the example Makefiles under sw/*/ do, e.g.:
#   make CROSS=riscv32-unknown-elf- ARCH=rv32i

CROSS ?= riscv64-unknown-elf-
ARCH  ?= rv32im
CC    := $(CROSS)gcc

BUILD := build

ARCH_FLAGS := -march=$(ARCH)_zicsr -mabi=ilp32
WARN_FLAGS         := -Wall -Wextra
OPT_FLAGS          := -Os -g
FREESTANDING_FLAGS := -ffreestanding -fno-builtin -fno-pic -nostdlib -nostartfiles

CFLAGS := $(ARCH_FLAGS) $(WARN_FLAGS) $(OPT_FLAGS) -I. $(FREESTANDING_FLAGS)

.PHONY: all clean

all: $(BUILD)/check.o

$(BUILD):
	mkdir -p $(BUILD)

$(BUILD)/check.c: tinymcu_csr.h | $(BUILD)
	echo '#include "tinymcu_csr.h"' > $@

$(BUILD)/check.o: $(BUILD)/check.c
	$(CC) $(CFLAGS) -c -o $@ $<

clean:
	rm -rf $(BUILD)
