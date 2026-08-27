# TinyMCU - printf demo build via Picolibc (RV32IM by default, freestanding, no OS)
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
#   make clean      - cleans the build
#
# Requires a RISC-V GCC cross-compiler on PATH, plus
# picolibc-riscv64-unknown-elf (see ../../README.md "Required tools" --
# that .deb package depends on this exact compiler, so its layout below
# matches it). Override CROSS if your toolchain uses a different
# triple, e.g.:
#   make CROSS=riscv32-unknown-elf-
# Override ARCH to target a different -march (see ARCH_FLAGS below), e.g.:
#   make ARCH=rv32i

CROSS   ?= riscv64-unknown-elf-
ARCH    ?= rv32im
CC      := $(CROSS)gcc
OBJCOPY := $(CROSS)objcopy
OBJDUMP := $(CROSS)objdump
PYTHON  := python3

BUILD    := build
LIB_DIR  := ../lib
HEX2ROM  := ../../scripts/hex2rom.py
IMEM_VHD := ../../rtl/core/tinymcu_imem_bootrom.vhd
LD_FILE	 := ../linker.ld

# rv32im: base integer ISA plus the M extension (MUL/DIV/REM etc., see
# ../../README.md "Extensions"); no A/F/D/C. Must match what tinymcu_cpu.vhd actually implements
ARCH_FLAGS := -march=$(ARCH) -mabi=ilp32

WARN_FLAGS         := -Wall -Wextra
OPT_FLAGS          := -Os -g
FREESTANDING_FLAGS := -ffreestanding -fno-builtin -fno-pic -nostdlib -nostartfiles
LINK_FLAGS         := -nostdlib -static -Wl,--no-relax

# Picolibc, prebuilt for this exact compiler/multilib -- used instead
# of newlib (no libc.a for this target from newlib without building it
# from source, and picolibc's printf/malloc are considerably smaller
# anyway). Only "stdout" needs hooking up (see
# ../lib/tinymcu_stdio.c), not a full set of newlib-style syscall
# stubs. -lgcc after -lc: picolibc's own object files can still need
# libgcc's software helpers (e.g. for 64-bit division inside printf),
# same reasoning as ARCH's own libgcc linkage.
PICOLIBC_ROOT  := /usr/lib/picolibc/riscv64-unknown-elf
PICOLIBC_FLAGS := -I$(PICOLIBC_ROOT)/include
PICOLIBC_LIBS  := -L$(PICOLIBC_ROOT)/lib/$(ARCH)/ilp32 -lc -lgcc

CFLAGS  := $(ARCH_FLAGS) $(WARN_FLAGS) $(OPT_FLAGS) -I$(LIB_DIR) $(FREESTANDING_FLAGS) $(PICOLIBC_FLAGS)
LDFLAGS := $(ARCH_FLAGS) -T $(LD_FILE) $(LINK_FLAGS) -Wl,-Map=$(BUILD)/main.map
SRCS := ../crt0.s main.c $(LIB_DIR)/tinymcu_timer.c $(LIB_DIR)/tinymcu_uart.c $(LIB_DIR)/tinymcu_stdio.c

.PHONY: all rom clean

all: $(BUILD)/main.elf $(BUILD)/main.bin $(BUILD)/main.hex $(BUILD)/main.lst

rom: $(BUILD)/main.hex
	$(PYTHON) $(HEX2ROM) $(BUILD)/main.hex --vhdl-file $(IMEM_VHD)

$(BUILD):
	mkdir -p $(BUILD)

$(BUILD)/main.elf: $(SRCS) $(LD_FILE) | $(BUILD)
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ $(SRCS) $(PICOLIBC_LIBS)

$(BUILD)/main.bin: $(BUILD)/main.elf
	$(OBJCOPY) -O binary $< $@

$(BUILD)/main.hex: $(BUILD)/main.elf
	$(OBJCOPY) -O ihex $< $@

$(BUILD)/main.lst: $(BUILD)/main.elf
	$(OBJDUMP) -d $< > $@

clean:
	rm -rf $(BUILD)
