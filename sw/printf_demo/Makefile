# TinyMCU - printf demo build via Picolibc (RV32IM by default, freestanding, no OS)
#
# Usage:
#   make            - build build/main.elf, .bin, .hex (Intel HEX) and
#                      .lst (disassembly)
#   make rom        - like "make", then write build/main.hex into
#                      ../../rtl/core/tinymcu_imem_bootrom.vhd via
#                      ../../scripts/hex2rom.py (overwrites the ROM's
#                      current PROGRAM constant, run
#                      ../../scripts/rom2hex.py first if you want to
#                      keep a copy of what's there now). Also disables
#                      the RAM disk (../../rtl/Makefile's
#                      disable-ramdisk) first, since this program has no
#                      use for it.
#   make clean      - cleans the build (this directory only, not the
#                      driver libraries under sw/lib/)
#
# Requires a RISC-V GCC cross-compiler on PATH, plus
# picolibc-riscv64-unknown-elf (see ../../README.md "Required tools",
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

# Each driver lives in its own directory under sw/lib/ with its own
# Makefile, building a libtinymcu_<name>.a there (see e.g.
# sw/lib/peripherals/uart/Makefile). This example needs Timer and UART;
# tinymcu_stdio.c itself is runtime glue rather than a driver (see
# sw/lib/tinymcu_stdio.c's own header comment), so it stays a plain
# source file compiled alongside main.c below, not a library.
LIB_TIMER_DIR := ../lib/peripherals/timer
LIB_UART_DIR  := ../lib/peripherals/uart

LIB_TIMER := $(LIB_TIMER_DIR)/build/libtinymcu_timer.a
LIB_UART  := $(LIB_UART_DIR)/build/libtinymcu_uart.a
LIBS      := $(LIB_TIMER) $(LIB_UART)

# rv32im: base integer ISA plus the M extension (MUL/DIV/REM etc., see
# ../../README.md "Extensions"); no A/F/D/C. Must match what tinymcu_cpu.vhd actually implements
ARCH_FLAGS := -march=$(ARCH)_zicsr -mabi=ilp32

WARN_FLAGS         := -Wall -Wextra
OPT_FLAGS          := -Os -g
FREESTANDING_FLAGS := -ffreestanding -fno-builtin -fno-pic -nostdlib -nostartfiles
LINK_FLAGS         := -nostdlib -static -Wl,--no-relax

# Picolibc, prebuilt for this exact compiler/multilib, used instead of
# newlib (no libc.a for this target from newlib without building it
# from source, and picolibc's printf/malloc are considerably smaller
# anyway). Only "stdout" needs hooking up (see
# ../lib/tinymcu_stdio.c), not a full set of newlib-style syscall
# stubs. -lgcc after -lc: picolibc's own object files can still need
# libgcc's software helpers (e.g. for 64-bit division inside printf),
# same reasoning as ARCH's own libgcc linkage.
PICOLIBC_ROOT  := /usr/lib/picolibc/riscv64-unknown-elf
PICOLIBC_FLAGS := -I$(PICOLIBC_ROOT)/include
PICOLIBC_LIBS  := -L$(PICOLIBC_ROOT)/lib/$(ARCH)/ilp32 -lc -lgcc

CFLAGS  := $(ARCH_FLAGS) $(WARN_FLAGS) $(OPT_FLAGS) -I$(LIB_TIMER_DIR) -I$(LIB_UART_DIR) $(FREESTANDING_FLAGS) $(PICOLIBC_FLAGS)
LDFLAGS := $(ARCH_FLAGS) -T $(LD_FILE) $(LINK_FLAGS) -Wl,-Map=$(BUILD)/main.map
SRCS := ../crt0.s main.c $(LIB_DIR)/tinymcu_stdio.c

.PHONY: all rom clean lib-timer lib-uart

all: $(BUILD)/main.elf $(BUILD)/main.bin $(BUILD)/main.hex $(BUILD)/main.lst

rom: $(BUILD)/main.hex
	$(MAKE) -C ../../rtl disable-ramdisk
	$(PYTHON) $(HEX2ROM) $(BUILD)/main.hex --vhdl-file $(IMEM_VHD)

$(BUILD):
	mkdir -p $(BUILD)

lib-timer:
	$(MAKE) -C $(LIB_TIMER_DIR) CROSS=$(CROSS) ARCH=$(ARCH)

lib-uart:
	$(MAKE) -C $(LIB_UART_DIR) CROSS=$(CROSS) ARCH=$(ARCH)

$(BUILD)/main.elf: $(SRCS) $(LD_FILE) lib-timer lib-uart | $(BUILD)
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ $(SRCS) $(LIBS) $(PICOLIBC_LIBS)

$(BUILD)/main.bin: $(BUILD)/main.elf
	$(OBJCOPY) -O binary $< $@

$(BUILD)/main.hex: $(BUILD)/main.elf
	$(OBJCOPY) -O ihex $< $@

$(BUILD)/main.lst: $(BUILD)/main.elf
	$(OBJDUMP) -d $< > $@

clean:
	rm -rf $(BUILD)
