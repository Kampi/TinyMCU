# TinyMCU - GHDL build & simulation Makefile
#
# Usage:
#   make            - regenerate the ROM from asm.py, then analyze,
#                      elaborate and run the testbench (default)
#   make run        - same as above
#   make run-irq    - regenerate the ROM from asm_irq.py (IRQ/MRET
#                      round-trip program), then analyze, elaborate and
#                      run tb_irq
#   make run-gpio   - analyze, elaborate and run tb_gpio (standalone
#                      GPIO peripheral test, no tinymcu_cpu/ROM involved)
#   make run-timer  - same, for tb_timer (Timer peripheral)
#   make run-uart   - same, for tb_uart (UART peripheral)
#   make wave       - like run, but also dump build/tb_cpu.ghw for a
#                      waveform viewer (e.g. GTKWave)
#   make analyze    - syntax/semantic check only, no simulation
#   make clean      - remove the build directory
#
# "run" always regenerates $(IMEM_VHD)'s (core/tinymcu_imem_bootrom.vhd)
# PROGRAM constant (and sim/tinymcu_tb_imem.vhd's checks) from
# scripts/asm.py first, so
# this Makefile always exercises the hand-assembled demo program -- it
# overwrites whatever else (e.g. a compiled sw/*/build/main.hex, or
# "run-irq"'s IRQ test program) was written into the ROM by something
# else. Those targets stay independent of this one on purpose; re-run
# them afterwards if you want the ROM to hold that program instead again.
#
# Directory layout: tinymcu_pkg.vhd (shared package) and tinymcu_top.vhd
# (FPGA-facing top level) live directly here; core/ holds the CPU
# pipeline plus its memory/bus infrastructure (addr_decoder, imem*,
# sram*), peripherals/ holds the peripheral bus mux and peripherals
# (periph, periph_gpio). RTL_SRCS below picks up all three locations;
# order doesn't matter, ghdl_analyze.sh resolves the dependency order.

GHDL   ?= ghdl
PYTHON ?= python3
STD    := --std=08
BUILD  := build
LIB    := tinymcu
TB     := tb_cpu

RTL_DIR := .
CORE_DIR := $(RTL_DIR)/core
PERIPH_DIR := $(RTL_DIR)/peripherals
SIM_DIR := ../sim
SCRIPTS_DIR := ../scripts

ASM := $(SCRIPTS_DIR)/asm.py
GHDL_ANALYZE := $(SCRIPTS_DIR)/ghdl_analyze.sh
IMEM_VHD := $(CORE_DIR)/tinymcu_imem_bootrom.vhd
IMEM_TB_VHD := $(SIM_DIR)/tinymcu_tb_imem.vhd
RTL_SRCS := $(wildcard $(RTL_DIR)/*.vhd $(CORE_DIR)/*.vhd $(PERIPH_DIR)/*.vhd)

# Testbenches are verification scaffolding, not MCU components, so they
# are compiled into the default "work" library instead of "$(LIB)" and
# reference the design under test as tinymcu.<entity>.
#
# tinymcu_tb_imem.vhd checks the hand-assembled demo program that "asm"
# (below) (re)writes into $(IMEM_VHD) -- see scripts/asm.py's header for
# how the two stay in sync. tinymcu_tb_software.vhd instead checks
# whatever program sw/*/Makefile's "rom" target last wrote into the ROM
# (see its own header comment); switch to it by hand
# (SIM_SRCS := $(SIM_DIR)/tinymcu_tb_software.vhd) if that's what you want
# to simulate -- but note that plain "make run" will overwrite the ROM
# with asm.py's program again regardless, since "asm" always runs first.
SIM_SRCS := $(SIM_DIR)/tinymcu_tb_imem.vhd

# "make run-irq": same idea as SIM_SRCS/ASM above, but for the IRQ/MRET
# round-trip test (sim/tinymcu_tb_irq.vhd). asm_irq.py has no checks-file
# counterpart to regenerate: tb_irq.vhd's asserts are hardwired to its
# fixed program (see both files' header comments), not auto-generated.
IRQ_ASM := $(SCRIPTS_DIR)/asm_irq.py
IRQ_SIM_SRCS := $(SIM_DIR)/tinymcu_tb_irq.vhd
IRQ_TB := tb_irq

# Standalone peripheral testbenches (sim/peripherals/tinymcu_tb_gpio.vhd/
# tb_timer.vhd/tb_uart.vhd): each instantiates its peripheral directly,
# not tinymcu_cpu, so none of these touch $(IMEM_VHD) or need an "asm"
# step.
SIM_PERIPH_DIR := $(SIM_DIR)/peripherals
GPIO_SIM_SRCS  := $(SIM_PERIPH_DIR)/tinymcu_tb_gpio.vhd
GPIO_TB        := tb_gpio
TIMER_SIM_SRCS := $(SIM_PERIPH_DIR)/tinymcu_tb_timer.vhd
TIMER_TB       := tb_timer
UART_SIM_SRCS  := $(SIM_PERIPH_DIR)/tinymcu_tb_uart.vhd
UART_TB        := tb_uart

GHDLFLAGS := $(STD) --workdir=$(BUILD) -P$(BUILD)

.PHONY: all run run-irq run-gpio run-timer run-uart wave analyze analyze-irq \
        analyze-gpio analyze-timer analyze-uart asm asm-irq clean help

all: run

$(BUILD):
	mkdir -p $(BUILD)

# Regenerates $(IMEM_VHD)'s PROGRAM constant and $(IMEM_TB_VHD)'s checks
# from the single program definition in $(ASM). Always runs (no
# timestamp-based skip): it's fast, and skipping it on stale timestamps
# risks silently testing an out-of-date ROM.
asm:
	$(PYTHON) $(ASM) --vhdl-file $(IMEM_VHD) --tb-file $(IMEM_TB_VHD)

analyze: asm $(BUILD)
	bash $(GHDL_ANALYZE) $(GHDLFLAGS) --work=$(LIB) -- $(RTL_SRCS)
	$(GHDL) -a $(GHDLFLAGS) --work=work $(SIM_SRCS)

elab: analyze
	$(GHDL) -e $(GHDLFLAGS) --work=work $(TB)

run: elab
	$(GHDL) -r $(GHDLFLAGS) --work=work $(TB)

wave: elab
	$(GHDL) -r $(GHDLFLAGS) --work=work $(TB) --wave=$(BUILD)/$(TB).ghw
	@echo "Waveform written to $(BUILD)/$(TB).ghw"

# Regenerates $(IMEM_VHD)'s PROGRAM constant from $(IRQ_ASM) (the
# IRQ/MRET round-trip program instead of asm.py's demo program).
asm-irq:
	$(PYTHON) $(IRQ_ASM) --vhdl-file $(IMEM_VHD)

analyze-irq: asm-irq $(BUILD)
	bash $(GHDL_ANALYZE) $(GHDLFLAGS) --work=$(LIB) -- $(RTL_SRCS)
	$(GHDL) -a $(GHDLFLAGS) --work=work $(IRQ_SIM_SRCS)

elab-irq: analyze-irq
	$(GHDL) -e $(GHDLFLAGS) --work=work $(IRQ_TB)

run-irq: elab-irq
	$(GHDL) -r $(GHDLFLAGS) --work=work $(IRQ_TB)

analyze-gpio: $(BUILD)
	bash $(GHDL_ANALYZE) $(GHDLFLAGS) --work=$(LIB) -- $(RTL_SRCS)
	$(GHDL) -a $(GHDLFLAGS) --work=work $(GPIO_SIM_SRCS)

elab-gpio: analyze-gpio
	$(GHDL) -e $(GHDLFLAGS) --work=work $(GPIO_TB)

run-gpio: elab-gpio
	$(GHDL) -r $(GHDLFLAGS) --work=work $(GPIO_TB)

analyze-timer: $(BUILD)
	bash $(GHDL_ANALYZE) $(GHDLFLAGS) --work=$(LIB) -- $(RTL_SRCS)
	$(GHDL) -a $(GHDLFLAGS) --work=work $(TIMER_SIM_SRCS)

elab-timer: analyze-timer
	$(GHDL) -e $(GHDLFLAGS) --work=work $(TIMER_TB)

run-timer: elab-timer
	$(GHDL) -r $(GHDLFLAGS) --work=work $(TIMER_TB)

analyze-uart: $(BUILD)
	bash $(GHDL_ANALYZE) $(GHDLFLAGS) --work=$(LIB) -- $(RTL_SRCS)
	$(GHDL) -a $(GHDLFLAGS) --work=work $(UART_SIM_SRCS)

elab-uart: analyze-uart
	$(GHDL) -e $(GHDLFLAGS) --work=work $(UART_TB)

run-uart: elab-uart
	$(GHDL) -r $(GHDLFLAGS) --work=work $(UART_TB)

clean:
	rm -rf $(BUILD)

help:
	@echo "Targets:"
	@echo "  run        - regenerate the ROM from asm.py, then analyze,"
	@echo "               elaborate and simulate $(TB) (default)"
	@echo "  run-irq    - regenerate the ROM from asm_irq.py, then analyze,"
	@echo "               elaborate and simulate $(IRQ_TB)"
	@echo "  run-gpio   - analyze, elaborate and simulate $(GPIO_TB)"
	@echo "               (standalone, no ROM/tinymcu_cpu involved)"
	@echo "  run-timer  - same, for $(TIMER_TB)"
	@echo "  run-uart   - same, for $(UART_TB)"
	@echo "  wave       - like run, but also dump $(BUILD)/$(TB).ghw"
	@echo "  analyze    - syntax/semantic check only, no simulation"
	@echo "  asm        - just regenerate the ROM/testbench from asm.py"
	@echo "  asm-irq    - just regenerate the ROM from asm_irq.py"
	@echo "  clean      - remove the build directory"
