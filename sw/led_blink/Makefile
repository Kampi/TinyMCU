# TinyMCU - LED blink demo build (RV32I only, freestanding, no OS)
#
# Usage:
#   make            - build build/main.elf, .bin, .hex (Intel HEX) and
#                      .lst (disassembly)
#   make rom        - like "make", then write build/main.hex into
#                      ../../rtl/core/tinymcu_imem_bootrom.vhd via
#                      ../../scripts/hex2rom.py (overwrites the ROM's
#                      current PROGRAM constant -- run
#                      ../../scripts/rom2hex.py first if you want to
#                      keep a copy of what's there now)
#   make clean		- cleans the build
#
# Requires a RISC-V GCC cross-compiler on PATH. Override CROSS if your
# toolchain uses a different triple, e.g.:
#   make CROSS=riscv32-unknown-elf-

CROSS   ?= riscv64-unknown-elf-
CC      := $(CROSS)gcc
OBJCOPY := $(CROSS)objcopy
OBJDUMP := $(CROSS)objdump
PYTHON  := python3

BUILD    := build
LIB_DIR  := ../lib
HEX2ROM  := ../../scripts/hex2rom.py
IMEM_VHD := ../../rtl/core/tinymcu_imem_bootrom.vhd
LD_FILE	 := ../linker.ld

# RV32I only: no M/A/F/D/C. csrr/csrw/csrs/csrc (tinymcu_csr.h) still
# assemble under plain "i" -- this toolchain (GCC 10.2/binutils, checked
# via `riscv64-unknown-elf-gcc -march=rv32i_zicsr ...`) predates -march
# gating CSR mnemonics behind an explicit "_zicsr" suffix and rejects
# that suffix outright ("unsupported ISA subset 'z'"); a newer toolchain
# that does gate it would need -march=rv32i_zicsr here instead. Must
# match what tinymcu_cpu.vhd actually implements otherwise (see
# ../../README.md "Extensions"). In particular, do not rely on
# '*'/'/'/'%' on int anywhere in the sources without also linking libgcc
# (not done here) -- see main.c.
ARCH_FLAGS := -march=rv32i -mabi=ilp32

CFLAGS  := $(ARCH_FLAGS) -Wall -Wextra -Os -g -I$(LIB_DIR) \
           -ffreestanding -fno-builtin -fno-pic -nostdlib -nostartfiles
LDFLAGS := $(ARCH_FLAGS) -T $(LD_FILE) -nostdlib -static \
           -Wl,--no-relax -Wl,-Map=$(BUILD)/main.map
SRCS := ../crt0.s $(LIB_DIR)/tinymcu_trap.S main.c $(LIB_DIR)/tinymcu_gpio.c \
        $(LIB_DIR)/tinymcu_timer.c $(LIB_DIR)/tinymcu_trap.c

.PHONY: all rom clean

all: $(BUILD)/main.elf $(BUILD)/main.bin $(BUILD)/main.hex $(BUILD)/main.lst

rom: $(BUILD)/main.hex
	$(PYTHON) $(HEX2ROM) $(BUILD)/main.hex --vhdl-file $(IMEM_VHD)

$(BUILD):
	mkdir -p $(BUILD)

$(BUILD)/main.elf: $(SRCS) $(LD_FILE) | $(BUILD)
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ $(SRCS)

$(BUILD)/main.bin: $(BUILD)/main.elf
	$(OBJCOPY) -O binary $< $@

$(BUILD)/main.hex: $(BUILD)/main.elf
	$(OBJCOPY) -O ihex $< $@

$(BUILD)/main.lst: $(BUILD)/main.elf
	$(OBJDUMP) -d $< > $@

clean:
	rm -rf $(BUILD)
