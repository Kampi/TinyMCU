# TinyMCU - UART driver library build
#
# Usage:
#   make       - build build/libtinymcu_uart.a
#   make clean - clean the build
#
# Requires a RISC-V GCC cross-compiler on PATH. Override CROSS/ARCH the
# same way the example Makefiles under sw/*/ do, e.g.:
#   make CROSS=riscv32-unknown-elf- ARCH=rv32i

CROSS ?= riscv64-unknown-elf-
ARCH  ?= rv32im
CC    := $(CROSS)gcc
AR    := $(CROSS)ar

BUILD := build
LIB   := $(BUILD)/libtinymcu_uart.a

# rv32im: base integer ISA plus the M extension. Must match what
# tinymcu_cpu.vhd actually implements; see sw/led_blink/Makefile's own
# comment on ARCH_FLAGS for the full explanation.
ARCH_FLAGS := -march=$(ARCH)_zicsr -mabi=ilp32

WARN_FLAGS          := -Wall -Wextra
OPT_FLAGS           := -Os -g
FREESTANDING_FLAGS  := -ffreestanding -fno-builtin -fno-pic -nostdlib -nostartfiles

CFLAGS := $(ARCH_FLAGS) $(WARN_FLAGS) $(OPT_FLAGS) $(FREESTANDING_FLAGS)

OBJS := $(BUILD)/tinymcu_uart.o

.PHONY: all clean

all: $(LIB)

$(BUILD):
	mkdir -p $(BUILD)

$(BUILD)/%.o: %.c | $(BUILD)
	$(CC) $(CFLAGS) -c -o $@ $<

$(LIB): $(OBJS)
	$(AR) rcs $@ $(OBJS)

clean:
	rm -rf $(BUILD)
