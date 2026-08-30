# TinyMCU - LED blink demo build (RV32IM by default, freestanding, no OS)
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
#   make clean		- cleans the build (this directory only, not the
#                      driver libraries under sw/lib/)
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
HEX2ROM  := ../../scripts/hex2rom.py
IMEM_VHD := ../../rtl/core/tinymcu_imem_bootrom.vhd
LD_FILE	 := ../linker.ld

# Each driver lives in its own directory under sw/lib/ with its own
# Makefile, building a libtinymcu_<name>.a there (see e.g.
# sw/lib/peripherals/gpio/Makefile). This example only needs GPIO,
# Timer, the trap entry point and the CSR helpers the trap handler and
# main.c both use.
LIB_GPIO_DIR  := ../lib/peripherals/gpio
LIB_TIMER_DIR := ../lib/peripherals/timer
LIB_TRAP_DIR  := ../lib/core/trap
LIB_CSR_DIR   := ../lib/core/csr

LIB_GPIO  := $(LIB_GPIO_DIR)/build/libtinymcu_gpio.a
LIB_TIMER := $(LIB_TIMER_DIR)/build/libtinymcu_timer.a
LIB_TRAP  := $(LIB_TRAP_DIR)/build/libtinymcu_trap.a
LIBS      := $(LIB_GPIO) $(LIB_TIMER) $(LIB_TRAP)

# rv32im: base integer ISA plus the M extension (MUL/DIV/REM etc., see
# ../../README.md "Extensions"); no A/F/D/C. Must match what tinymcu_cpu.vhd actually implements
ARCH_FLAGS := -march=$(ARCH)_zicsr -mabi=ilp32

WARN_FLAGS         := -Wall -Wextra
OPT_FLAGS          := -Os -g
FREESTANDING_FLAGS := -ffreestanding -fno-builtin -fno-pic -nostdlib -nostartfiles
LINK_FLAGS         := -nostdlib -static -Wl,--no-relax

CFLAGS  := $(ARCH_FLAGS) $(WARN_FLAGS) $(OPT_FLAGS) \
           -I$(LIB_GPIO_DIR) -I$(LIB_TIMER_DIR) -I$(LIB_TRAP_DIR) -I$(LIB_CSR_DIR) \
           $(FREESTANDING_FLAGS)
LDFLAGS := $(ARCH_FLAGS) -T $(LD_FILE) $(LINK_FLAGS) -Wl,-Map=$(BUILD)/main.map
SRCS := ../crt0.s main.c

.PHONY: all rom clean lib-gpio lib-timer lib-trap

all: $(BUILD)/main.elf $(BUILD)/main.bin $(BUILD)/main.hex $(BUILD)/main.lst

rom: $(BUILD)/main.hex
	$(MAKE) -C ../../rtl disable-ramdisk
	$(PYTHON) $(HEX2ROM) $(BUILD)/main.hex --vhdl-file $(IMEM_VHD)

$(BUILD):
	mkdir -p $(BUILD)

lib-gpio:
	$(MAKE) -C $(LIB_GPIO_DIR) CROSS=$(CROSS) ARCH=$(ARCH)

lib-timer:
	$(MAKE) -C $(LIB_TIMER_DIR) CROSS=$(CROSS) ARCH=$(ARCH)

lib-trap:
	$(MAKE) -C $(LIB_TRAP_DIR) CROSS=$(CROSS) ARCH=$(ARCH)

$(BUILD)/main.elf: $(SRCS) $(LD_FILE) lib-gpio lib-timer lib-trap | $(BUILD)
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ $(SRCS) $(LIBS)

$(BUILD)/main.bin: $(BUILD)/main.elf
	$(OBJCOPY) -O binary $< $@

$(BUILD)/main.hex: $(BUILD)/main.elf
	$(OBJCOPY) -O ihex $< $@

$(BUILD)/main.lst: $(BUILD)/main.elf
	$(OBJDUMP) -d $< > $@

clean:
	rm -rf $(BUILD)
