# TinyMCU - GHDL build & simulation Makefile
#
# Usage:
#   make              - full regression: clean, then run every
#                       target below in sequence (default)
#   make run          - same as above
#   make run-core     - regenerate the ROM from asm.py, then analyze,
#                       elaborate and run the demo-program testbench
#                       (what plain "make run" used to do)
#   make run-irq      - regenerate the ROM from asm_irq.py (IRQ/MRET
#                       round-trip program), then analyze, elaborate and
#                       run tb_irq
#   make run-gpio     - analyze, elaborate and run tb_gpio (standalone
#                       GPIO peripheral test, no tinymcu_cpu/ROM involved)
#   make run-timer    - same, for tb_timer (Timer peripheral)
#   make run-uart     - same, for tb_uart (UART peripheral)
#   make run-mult     - same, for tb_mult (M-extension multiply unit,
#                       standalone -- not through tinymcu_cpu)
#   make run-mult-cpu - regenerate the ROM from asm_mult.py (M-extension
#                       multiply pipeline-integration program), then
#                       analyze, elaborate and run tb_mult_cpu
#   make run-div      - same as run-mult, for tb_div (M-extension divide
#                       unit, standalone -- not through tinymcu_cpu)
#   make run-div-cpu  - same as run-mult-cpu, but for tb_div_cpu
#                       (regenerates the ROM from asm_div.py)
#   make wave         - like run-core, but also dump build/tb_core.ghw
#                       for a waveform viewer (e.g. GTKWave)
#   make analyze      - syntax/semantic check only, no simulation
#   make clean        - remove the build directory
#
# "run-core" always regenerates $(IMEM_VHD)'s (core/tinymcu_imem_bootrom.vhd)
# PROGRAM constant (and sim/tinymcu_tb_core.vhd's checks) from
# scripts/asm.py first, so it always exercises the hand-assembled demo
# program -- it overwrites whatever else (e.g. a compiled
# sw/*/build/main.hex, or "run-irq"'s IRQ test program) was written
# into the ROM by something else. Those targets stay independent of
# this one on purpose; re-run them afterwards if you want the ROM to
# hold that program instead again.
#
# "run" (the aggregate target above) runs through every ROM-regenerating
# target in sequence, so $(IMEM_VHD) ends up holding whichever one ran
# last (run-div-cpu's program, as the targets are currently
# ordered) -- re-run the specific target you want afterwards if that
# matters to you.
#

GHDL   ?= ghdl
PYTHON ?= python3
STD    := --std=08
BUILD  := build
LIB    := tinymcu
TB     := tb_core

RTL_DIR := .
CORE_DIR := $(RTL_DIR)/core
PERIPH_DIR := $(RTL_DIR)/peripherals
SIM_DIR := ../sim
SCRIPTS_DIR := ../scripts

ASM := $(SCRIPTS_DIR)/asm.py
GHDL_ANALYZE := $(SCRIPTS_DIR)/ghdl_analyze.sh
IMEM_VHD := $(CORE_DIR)/tinymcu_imem_bootrom.vhd
IMEM_TB_VHD := $(SIM_DIR)/tinymcu_tb_core.vhd
RTL_SRCS := $(wildcard $(RTL_DIR)/*.vhd $(CORE_DIR)/*.vhd $(PERIPH_DIR)/*.vhd)

# Testbenches are verification scaffolding, not MCU components, so they
# are compiled into the default "work" library instead of "$(LIB)" and
# reference the design under test as tinymcu.<entity>.
SIM_SRCS := $(SIM_DIR)/tinymcu_tb_core.vhd

# "make run-irq": same idea as SIM_SRCS/ASM above, but for the IRQ/MRET
# round-trip test (sim/core/tinymcu_tb_irq.vhd). asm_irq.py has no
# checks-file counterpart to regenerate: tb_irq.vhd's asserts are
# hardwired to its fixed program (see both files' header comments), not
# auto-generated.
IRQ_ASM := $(SCRIPTS_DIR)/asm_irq.py
IRQ_SIM_SRCS := $(SIM_DIR)/core/tinymcu_tb_irq.vhd
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

# Standalone core-component testbench (sim/core/tinymcu_tb_mult.vhd):
# instantiates tinymcu_cpu_mult directly, not tinymcu_cpu, so this
# doesn't touch $(IMEM_VHD) or need an "asm" step either.
SIM_CORE_DIR := $(SIM_DIR)/core
MULT_SIM_SRCS := $(SIM_CORE_DIR)/tinymcu_tb_mult.vhd
MULT_TB       := tb_mult

# "make run-mult-cpu": runs the multiplier through the full CPU
# pipeline (sim/core/tinymcu_tb_mult_cpu.vhd), unlike run-mult
# above which instantiates tinymcu_cpu_mult directly. Same idea as
# IRQ_ASM/IRQ_SIM_SRCS: asm_mult.py has no checks-file counterpart to
# regenerate, the testbench's asserts are hardwired to its fixed
# program (see both files' header comments).
MULT_CPU_ASM      := $(SCRIPTS_DIR)/asm_mult.py
MULT_CPU_SIM_SRCS := $(SIM_CORE_DIR)/tinymcu_tb_mult_cpu.vhd
MULT_CPU_TB       := tb_mult_cpu

# Standalone core-component testbench (sim/core/tinymcu_tb_div.vhd):
# instantiates tinymcu_cpu_div directly, not tinymcu_cpu, so this
# doesn't touch $(IMEM_VHD) or need an "asm" step either.
DIV_SIM_SRCS := $(SIM_CORE_DIR)/tinymcu_tb_div.vhd
DIV_TB       := tb_div

# "make run-div-cpu": runs the divider through the full CPU
# pipeline (sim/core/tinymcu_tb_div_cpu.vhd), unlike run-div above
# which instantiates tinymcu_cpu_div directly. Same idea as
# MULT_CPU_ASM/MULT_CPU_SIM_SRCS: asm_div.py has no checks-file
# counterpart to regenerate, the testbench's asserts are hardwired to
# its fixed program (see both files' header comments).
DIV_CPU_ASM      := $(SCRIPTS_DIR)/asm_div.py
DIV_CPU_SIM_SRCS := $(SIM_CORE_DIR)/tinymcu_tb_div_cpu.vhd
DIV_CPU_TB       := tb_div_cpu

GHDLFLAGS := $(STD) --workdir=$(BUILD) -P$(BUILD)

# --max-stack-alloc (ghdl -r only, mcode rejects it on -a/-e): GHDL's
# mcode backend defaults to a 128 KB limit on elaboration-time objects;
# tinymcu_imem_bootrom.vhd's boot-ROM array (mem_array_t,
# IMEM_ADDR_WIDTH-sized) exceeds that once IMEM_ADDR_WIDTH grows past a
# few KB of words, since GHDL stores each std_ulogic bit as a full byte
# at simulation time (so a 32 KB ROM's word_t array costs 256 KB here,
# not 32 KB) -- purely a simulator limitation, not a real hardware/BRAM
# constraint.
GHDLRUNFLAGS := --max-stack-alloc=1024

.PHONY: all run run-core run-irq run-gpio run-timer run-uart run-mult run-mult-cpu \
        run-div run-div-cpu wave analyze analyze-irq analyze-gpio analyze-timer \
        analyze-uart analyze-mult analyze-mult-cpu analyze-div analyze-div-cpu \
        asm asm-irq asm-mult-cpu asm-div-cpu clean help

all: run

# Full regression: every testbench in this Makefile, one after another.
# Starts from a clean build directory -- switching between the
# differently-regenerated ROM programs (asm.py/asm_irq.py/asm_mult.py/
# asm_div.py) that each of these writes into $(IMEM_VHD) can otherwise
# hit stale GHDL library state ("file X has changed and must be
# reanalysed"). Uses recursive $(MAKE) calls (not prerequisites) so the
# order is guaranteed even under "make -j".
run: clean
	$(MAKE) run-core
	$(MAKE) run-irq
	$(MAKE) run-gpio
	$(MAKE) run-timer
	$(MAKE) run-uart
	$(MAKE) run-mult
	$(MAKE) run-mult-cpu
	$(MAKE) run-div
	$(MAKE) run-div-cpu

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

run-core: elab
	$(GHDL) -r $(GHDLFLAGS) --work=work $(TB) $(GHDLRUNFLAGS)

wave: elab
	$(GHDL) -r $(GHDLFLAGS) --work=work $(TB) $(GHDLRUNFLAGS) --wave=$(BUILD)/$(TB).ghw
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
	$(GHDL) -r $(GHDLFLAGS) --work=work $(IRQ_TB) $(GHDLRUNFLAGS)

analyze-gpio: $(BUILD)
	bash $(GHDL_ANALYZE) $(GHDLFLAGS) --work=$(LIB) -- $(RTL_SRCS)
	$(GHDL) -a $(GHDLFLAGS) --work=work $(GPIO_SIM_SRCS)

elab-gpio: analyze-gpio
	$(GHDL) -e $(GHDLFLAGS) --work=work $(GPIO_TB)

run-gpio: elab-gpio
	$(GHDL) -r $(GHDLFLAGS) --work=work $(GPIO_TB) $(GHDLRUNFLAGS)

analyze-timer: $(BUILD)
	bash $(GHDL_ANALYZE) $(GHDLFLAGS) --work=$(LIB) -- $(RTL_SRCS)
	$(GHDL) -a $(GHDLFLAGS) --work=work $(TIMER_SIM_SRCS)

elab-timer: analyze-timer
	$(GHDL) -e $(GHDLFLAGS) --work=work $(TIMER_TB)

run-timer: elab-timer
	$(GHDL) -r $(GHDLFLAGS) --work=work $(TIMER_TB) $(GHDLRUNFLAGS)

analyze-uart: $(BUILD)
	bash $(GHDL_ANALYZE) $(GHDLFLAGS) --work=$(LIB) -- $(RTL_SRCS)
	$(GHDL) -a $(GHDLFLAGS) --work=work $(UART_SIM_SRCS)

elab-uart: analyze-uart
	$(GHDL) -e $(GHDLFLAGS) --work=work $(UART_TB)

run-uart: elab-uart
	$(GHDL) -r $(GHDLFLAGS) --work=work $(UART_TB) $(GHDLRUNFLAGS)

analyze-mult: $(BUILD)
	bash $(GHDL_ANALYZE) $(GHDLFLAGS) --work=$(LIB) -- $(RTL_SRCS)
	$(GHDL) -a $(GHDLFLAGS) --work=work $(MULT_SIM_SRCS)

elab-mult: analyze-mult
	$(GHDL) -e $(GHDLFLAGS) --work=work $(MULT_TB)

run-mult: elab-mult
	$(GHDL) -r $(GHDLFLAGS) --work=work $(MULT_TB) $(GHDLRUNFLAGS)

# Regenerates $(IMEM_VHD)'s PROGRAM constant from $(MULT_CPU_ASM) (the
# M-extension pipeline-integration program instead of asm.py's demo
# program).
asm-mult-cpu:
	$(PYTHON) $(MULT_CPU_ASM) --vhdl-file $(IMEM_VHD)

analyze-mult-cpu: asm-mult-cpu $(BUILD)
	bash $(GHDL_ANALYZE) $(GHDLFLAGS) --work=$(LIB) -- $(RTL_SRCS)
	$(GHDL) -a $(GHDLFLAGS) --work=work $(MULT_CPU_SIM_SRCS)

elab-mult-cpu: analyze-mult-cpu
	$(GHDL) -e $(GHDLFLAGS) --work=work $(MULT_CPU_TB)

run-mult-cpu: elab-mult-cpu
	$(GHDL) -r $(GHDLFLAGS) --work=work $(MULT_CPU_TB) $(GHDLRUNFLAGS)

analyze-div: $(BUILD)
	bash $(GHDL_ANALYZE) $(GHDLFLAGS) --work=$(LIB) -- $(RTL_SRCS)
	$(GHDL) -a $(GHDLFLAGS) --work=work $(DIV_SIM_SRCS)

elab-div: analyze-div
	$(GHDL) -e $(GHDLFLAGS) --work=work $(DIV_TB)

run-div: elab-div
	$(GHDL) -r $(GHDLFLAGS) --work=work $(DIV_TB) $(GHDLRUNFLAGS)

# Regenerates $(IMEM_VHD)'s PROGRAM constant from $(DIV_CPU_ASM) (the
# M-extension divide pipeline-integration program instead of asm.py's
# demo program).
asm-div-cpu:
	$(PYTHON) $(DIV_CPU_ASM) --vhdl-file $(IMEM_VHD)

analyze-div-cpu: asm-div-cpu $(BUILD)
	bash $(GHDL_ANALYZE) $(GHDLFLAGS) --work=$(LIB) -- $(RTL_SRCS)
	$(GHDL) -a $(GHDLFLAGS) --work=work $(DIV_CPU_SIM_SRCS)

elab-div-cpu: analyze-div-cpu
	$(GHDL) -e $(GHDLFLAGS) --work=work $(DIV_CPU_TB)

run-div-cpu: elab-div-cpu
	$(GHDL) -r $(GHDLFLAGS) --work=work $(DIV_CPU_TB) $(GHDLRUNFLAGS)

clean:
	rm -rf $(BUILD)

help:
	@echo "Targets:"
	@echo "  run        - full regression: clean, then run every target"
	@echo "               below in sequence (default)"
	@echo "  run-core   - regenerate the ROM from asm.py, then analyze,"
	@echo "               elaborate and simulate $(TB) (what plain"
	@echo "               'make run' used to do)"
	@echo "  run-irq    - regenerate the ROM from asm_irq.py, then analyze,"
	@echo "               elaborate and simulate $(IRQ_TB)"
	@echo "  run-gpio   - analyze, elaborate and simulate $(GPIO_TB)"
	@echo "               (standalone, no ROM/tinymcu_cpu involved)"
	@echo "  run-timer  - same, for $(TIMER_TB)"
	@echo "  run-uart   - same, for $(UART_TB)"
	@echo "  run-mult   - same, for $(MULT_TB) (M-extension multiply unit,"
	@echo "               standalone -- not through tinymcu_cpu)"
	@echo "  run-mult-cpu - regenerate the ROM from asm_mult.py, then"
	@echo "               analyze, elaborate and simulate $(MULT_CPU_TB)"
	@echo "               (multiplier through the full CPU pipeline)"
	@echo "  run-div    - same, for $(DIV_TB) (M-extension divide unit,"
	@echo "               standalone -- not through tinymcu_cpu)"
	@echo "  run-div-cpu - regenerate the ROM from asm_div.py, then"
	@echo "               analyze, elaborate and simulate $(DIV_CPU_TB)"
	@echo "               (divider through the full CPU pipeline)"
	@echo "  wave       - like run-core, but also dump $(BUILD)/$(TB).ghw"
	@echo "  analyze    - syntax/semantic check only, no simulation"
	@echo "  asm        - just regenerate the ROM/testbench from asm.py"
	@echo "  asm-irq    - just regenerate the ROM from asm_irq.py"
	@echo "  asm-mult-cpu - just regenerate the ROM from asm_mult.py"
	@echo "  asm-div-cpu - just regenerate the ROM from asm_div.py"
	@echo "  clean      - remove the build directory"
