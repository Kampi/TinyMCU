# TinyMCU - LED blink demo build (RV32IM by default, freestanding, no OS)
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

CFLAGS  := $(ARCH_FLAGS) $(WARN_FLAGS) $(OPT_FLAGS) -I$(LIB_DIR) $(FREESTANDING_FLAGS)
LDFLAGS := $(ARCH_FLAGS) -T $(LD_FILE) $(LINK_FLAGS) -Wl,-Map=$(BUILD)/main.map
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
