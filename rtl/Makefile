# TinyMCU - build & simulation Makefile
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
#                       standalone and not through tinymcu_cpu)
#   make run-mult-cpu - regenerate the ROM from asm_mult.py (M-extension
#                       multiply pipeline-integration program), then
#                       analyze, elaborate and run tb_mult_cpu
#   make run-div      - same as run-mult, for tb_div (M-extension divide
#                       unit, standalone and not through tinymcu_cpu)
#   make run-div-cpu  - same as run-mult-cpu, but for tb_div_cpu
#                       (regenerates the ROM from asm_div.py)
#   make run-xip-cpu  - regenerate the ROM from asm_xip.py (Boot ROM
#                       program that configures the XIP controller and
#                       jumps into its flash window), then analyze,
#                       elaborate and run tb_xip_cpu. See "make sim
#                       SIM_TB=xip" for the standalone controller test,
#                       not through tinymcu_cpu.
#   make wave         - like run-core, but also dump build/tb_core.ghw
#                       for a waveform viewer (e.g. GTKWave)
#   make sim SIM_TB=<name> - simulate any testbench by name, no dedicated
#                       target needed (e.g. SIM_TB=cpm_neo runs
#                       sim/cpm-neo/tinymcu_tb_cpm_neo.vhd's tb_cpm_neo).
#                       Unlike the targets above, never touches
#                       $(IMEM_VHD)/RAMDISK_ENABLE. It just simulates
#                       whatever ROM/RAM content is already baked in.
#   make analyze      - syntax/semantic check only, no simulation
#   make clean        - remove the build directory
#   make cpm-neo      - build sw/cpm-neo/ (CP/M Neo) for the tinymcu
#                       platform and bake both its bootloader and its
#                       disk image into this RTL, everything needed to
#                       get it actually booting on real hardware in one
#                       command (see the "sw/cpm-neo/ integration"
#                       comment further down for the full picture)
#   make cpm-neo-rom     - just the bootloader half of cpm-neo
#   make cpm-neo-ramdisk - just the disk-image half of cpm-neo
#   make set-generics    - just patch RAM_ADDR_WIDTH/RAMDISK_ADDR_WIDTH/
#                       RAMDISK_ENABLE (=true) into rtl/core/tinymcu_cpu.vhd
#                       and the Vivado top level, without building anything
#   make disable-ramdisk - set RAMDISK_ENABLE=false (RAMDISK_ADDR_WIDTH
#                       stays at its real value, see that generic's
#                       comment) and clear any stale cpm-neo disk content;
#                       runs automatically before every asm* target, so
#                       plain "make"/"make run" always does this already
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
SIM_SCRIPTS_DIR := $(SCRIPTS_DIR)/sim

ASM := $(SIM_SCRIPTS_DIR)/asm.py
GHDL_ANALYZE := $(SCRIPTS_DIR)/ghdl_analyze.sh
IMEM_VHD := $(CORE_DIR)/tinymcu_imem_bootrom.vhd
IMEM_TB_VHD := $(SIM_DIR)/tinymcu_tb_core.vhd
RTL_SRCS := $(wildcard $(RTL_DIR)/*.vhd $(CORE_DIR)/*.vhd $(PERIPH_DIR)/*.vhd)
OBJCOPY  ?= riscv64-unknown-elf-objcopy
CPU_VHD  := $(CORE_DIR)/tinymcu_cpu.vhd
TOP_VHD  := ../integration/TinyMCU.srcs/sources_1/imports/rtl/tinymcu_top.vhd
SRAM_VHD := $(CORE_DIR)/tinymcu_sram_generic.vhd
RAMDISK2ROM := $(SCRIPTS_DIR)/cpm_neo_ramdisk2rom.py
HEX2ROM     := $(SCRIPTS_DIR)/hex2rom.py

CPM_NEO_DIR      := ../sw/cpm-neo
CPM_NEO_BUILD    := $(CPM_NEO_DIR)/sysgen/build
CPM_NEO_BOOT_ELF := $(CPM_NEO_BUILD)/core/int/bootloader.elf
CPM_NEO_BOOT_HEX := $(CPM_NEO_BUILD)/bootloader.hex
CPM_NEO_DISK_IMG := $(CPM_NEO_BUILD)/disk.img

RAM_ADDR_WIDTH     ?= 14
RAMDISK_ADDR_WIDTH ?= 15
CPM_NEO_PLATFORM   ?= tinymcu
CPM_NEO_ARCH       ?= tinymcu-riscv32

SRAM_BYTES        := $(shell echo $$(( (1 << $(RAM_ADDR_WIDTH)) * 4 )))
RAMDISK_BYTES     := $(shell echo $$(( (1 << $(RAMDISK_ADDR_WIDTH)) * 4 )))
CPM_NEO_MEM_SIZE  := $(shell echo $$(( $(SRAM_BYTES) / 1024 )))K
CPM_NEO_DISK_SIZE := $(shell echo $$(( $(RAMDISK_BYTES) / 1024 )))K
RAMDISK_MAX_WORDS := $(shell echo $$(( $(RAMDISK_BYTES) / 4 )))

# Testbenches are verification scaffolding, not MCU components, so they
# are compiled into the default "work" library instead of "$(LIB)" and
# reference the design under test as tinymcu.<entity>.
SIM_SRCS := $(SIM_DIR)/tinymcu_tb_core.vhd

# "make run-irq": same idea as SIM_SRCS/ASM above, but for the IRQ/MRET
# round-trip test (sim/core/tinymcu_tb_irq.vhd). asm_irq.py has no
# checks-file counterpart to regenerate: tb_irq.vhd's asserts are
# hardwired to its fixed program (see both files' header comments), not
# auto-generated.
IRQ_ASM := $(SIM_SCRIPTS_DIR)/asm_irq.py
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
MULT_CPU_ASM      := $(SIM_SCRIPTS_DIR)/asm_mult.py
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
DIV_CPU_ASM      := $(SIM_SCRIPTS_DIR)/asm_div.py
DIV_CPU_SIM_SRCS := $(SIM_CORE_DIR)/tinymcu_tb_div_cpu.vhd
DIV_CPU_TB       := tb_div_cpu

# "make run-xip-cpu": runs the XIP controller through the full CPU
# pipeline (sim/core/tinymcu_tb_xip_cpu.vhd), unlike the standalone
# tb_xip (sim SIM_TB=xip) which drives tinymcu_imem_xip directly. Same
# idea as MULT_CPU_ASM/DIV_CPU_ASM: asm_xip.py has no checks-file
# counterpart to regenerate, the testbench's asserts (and its own
# simulated flash content) are hardwired to this exact Boot ROM program
# (see both files' header comments).
XIP_CPU_ASM      := $(SIM_SCRIPTS_DIR)/asm_xip.py
XIP_CPU_SIM_SRCS := $(SIM_CORE_DIR)/tinymcu_tb_xip_cpu.vhd
XIP_CPU_TB       := tb_xip_cpu

# "make sim SIM_TB=<name>" argument, e.g. SIM_TB=cpm_neo -> finds
# sim/cpm-neo/tinymcu_tb_cpm_neo.vhd by TinyMCU's tinymcu_tb_<name>.vhd
# naming convention (every existing testbench already follows it,
# wherever under $(SIM_DIR) it lives) and simulates its tb_<name> entity.
# A separate variable from $(TB) above -- that one is fixed to tb_core
# for the classic run-core/elab/wave pipeline, which always regenerates
# $(IMEM_VHD) from asm.py first; this generic target never touches
# $(IMEM_VHD), it just simulates whatever ROM/RAM content already exists.
SIM_TB ?=
SIM_GENERIC_FILE := $(shell find $(SIM_DIR) -name "tinymcu_tb_$(SIM_TB).vhd" 2>/dev/null | head -1)

GHDLFLAGS := $(STD) --workdir=$(BUILD) -P$(BUILD)

# --max-stack-alloc (ghdl -r only, mcode rejects it on -a/-e): GHDL's
# mcode backend defaults to a 128 KB limit on elaboration-time objects;
# tinymcu_imem_bootrom.vhd's boot-ROM array (mem_array_t,
# IMEM_ADDR_WIDTH-sized) exceeds that once IMEM_ADDR_WIDTH grows past a
# few KB of words, since GHDL stores each std_ulogic bit as a full byte
# at simulation time (so a 32 KB ROM's word_t array costs 256 KB here,
# not 32 KB).
GHDLRUNFLAGS := --max-stack-alloc=1024

.PHONY: all run run-core run-irq run-gpio run-timer run-uart run-mult run-mult-cpu \
        run-div run-div-cpu run-xip-cpu wave analyze analyze-irq analyze-gpio analyze-timer \
        analyze-uart analyze-mult analyze-mult-cpu analyze-div analyze-div-cpu analyze-xip-cpu \
        asm asm-irq asm-mult-cpu asm-div-cpu asm-xip-cpu clean help sim \
        set-generics disable-ramdisk cpm-neo cpm-neo-disk cpm-neo-rom cpm-neo-ramdisk

all: run

# Full regression: every testbench in this Makefile, one after another.
# Starts from a clean build directory. Switching between the
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
	$(MAKE) run-xip-cpu

# Patches RAM_ADDR_WIDTH's, RAMDISK_ADDR_WIDTH's and RAMDISK_ENABLE's
# generic defaults in both VHDL files that declare them (RAMDISK_ENABLE
# is set to true here. tinymcu_cpu.vhd's u_addr_decoder/u_ramdisk
# generate blocks gate on it, see tinymcu_addr_decoder.vhd's comment on
# its own RAMDISK_ENABLE generic). Only ever touches the value itself --
# everything else in either file (formatting, other generics, comments)
# is left untouched. A generic default change here needs a Vivado
# re-synthesis to actually take effect on hardware; GHDL simulation picks
# it up on its next analyze.
set-generics:
	sed -i -E \
		-e 's/(RAM_ADDR_WIDTH[[:space:]]*:[[:space:]]*integer[[:space:]]*:=[[:space:]]*)[0-9]+/\1$(RAM_ADDR_WIDTH)/' \
		-e 's/(RAMDISK_ADDR_WIDTH[[:space:]]*:[[:space:]]*integer[[:space:]]*:=[[:space:]]*)[0-9]+/\1$(RAMDISK_ADDR_WIDTH)/' \
		-e 's/(RAMDISK_ENABLE[[:space:]]*:[[:space:]]*boolean[[:space:]]*:=[[:space:]]*)(true|false)/\1true/' \
		$(CPU_VHD)
	sed -i -E \
		-e 's/(RAM_ADDR_WIDTH[[:space:]]*:[[:space:]]*integer[[:space:]]*:=[[:space:]]*)[0-9]+/\1$(RAM_ADDR_WIDTH)/' \
		-e 's/(RAMDISK_ADDR_WIDTH[[:space:]]*:[[:space:]]*integer[[:space:]]*:=[[:space:]]*)[0-9]+/\1$(RAMDISK_ADDR_WIDTH)/' \
		-e 's/(RAMDISK_ENABLE[[:space:]]*:[[:space:]]*boolean[[:space:]]*:=[[:space:]]*)(true|false)/\1true/' \
		$(TOP_VHD)

# Classic (non-cpm-neo) builds shouldn't carry the RAM disk's u_ramdisk
# SRAM block/BRAM around. Set RAMDISK_ENABLE=false (RAMDISK_ADDR_WIDTH
# itself stays at its real value, see that generic's comment above) and
# clear any stale sw/cpm-neo/ disk content a previous "make cpm-neo" run
# left behind. Every ROM-regenerating target below (asm/asm-irq/
# asm-mult-cpu/asm-div-cpu) runs this first, so it's covered by plain
# "make"/"make run" without doing anything special.
disable-ramdisk:
	sed -i -E \
		's/(RAMDISK_ENABLE[[:space:]]*:[[:space:]]*boolean[[:space:]]*:=[[:space:]]*)(true|false)/\1false/' \
		$(CPU_VHD) $(TOP_VHD)
	cd $(SCRIPTS_DIR) && $(PYTHON) -c "from lib.rom_writer import clear_disk; clear_disk()"

# Delegates the actual sysgen build + "sysgen new" invocation to
# $(CPM_NEO_DIR)/Makefile (its own, separate build concern), passing down
# the sizes/platform derived above so the two Makefiles can't drift apart.
# This Makefile is still the only place RAM_ADDR_WIDTH/
# RAMDISK_ADDR_WIDTH themselves live.
cpm-neo-disk: set-generics
	$(MAKE) -C $(CPM_NEO_DIR) disk \
		DISK_SIZE=$(CPM_NEO_DISK_SIZE) MEM_SIZE=$(CPM_NEO_MEM_SIZE) \
		PLATFORM=$(CPM_NEO_PLATFORM) ARCH=$(CPM_NEO_ARCH)

# Bakes the bootloader into $(IMEM_VHD)
cpm-neo-rom: cpm-neo-disk
	$(OBJCOPY) -O ihex --only-section=.boot $(CPM_NEO_BOOT_ELF) $(CPM_NEO_BOOT_HEX)
	$(PYTHON) $(HEX2ROM) $(CPM_NEO_BOOT_HEX) --vhdl-file $(IMEM_VHD)

# Bakes disk.img into $(SRAM_VHD)'s DISK constant
cpm-neo-ramdisk: cpm-neo-disk
	$(PYTHON) $(RAMDISK2ROM) $(CPM_NEO_DISK_IMG) --vhdl-file $(SRAM_VHD) --max-words=$(RAMDISK_MAX_WORDS)

# Everything needed to get CP/M Neo actually booting on real hardware in
# one command: set-generics, build the disk, bake both the bootloader and
# the disk image into the RTL.
cpm-neo: cpm-neo-rom cpm-neo-ramdisk

$(BUILD):
	mkdir -p $(BUILD)

# Regenerates $(IMEM_VHD)'s PROGRAM constant and $(IMEM_TB_VHD)'s checks
# from the single program definition in $(ASM). Always runs (no
# timestamp-based skip): it's fast, and skipping it on stale timestamps
# risks silently testing an out-of-date ROM. disable-ramdisk: see that
# target's comment.
asm: disable-ramdisk
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
asm-irq: disable-ramdisk
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
asm-mult-cpu: disable-ramdisk
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
asm-div-cpu: disable-ramdisk
	$(PYTHON) $(DIV_CPU_ASM) --vhdl-file $(IMEM_VHD)

analyze-div-cpu: asm-div-cpu $(BUILD)
	bash $(GHDL_ANALYZE) $(GHDLFLAGS) --work=$(LIB) -- $(RTL_SRCS)
	$(GHDL) -a $(GHDLFLAGS) --work=work $(DIV_CPU_SIM_SRCS)

elab-div-cpu: analyze-div-cpu
	$(GHDL) -e $(GHDLFLAGS) --work=work $(DIV_CPU_TB)

run-div-cpu: elab-div-cpu
	$(GHDL) -r $(GHDLFLAGS) --work=work $(DIV_CPU_TB) $(GHDLRUNFLAGS)

# Regenerates $(IMEM_VHD)'s PROGRAM constant from $(XIP_CPU_ASM) (the
# Boot ROM program that configures tinymcu_imem_xip.vhd and jumps into
# its flash window, instead of asm.py's demo program).
asm-xip-cpu: disable-ramdisk
	$(PYTHON) $(XIP_CPU_ASM) --vhdl-file $(IMEM_VHD)

analyze-xip-cpu: asm-xip-cpu $(BUILD)
	bash $(GHDL_ANALYZE) $(GHDLFLAGS) --work=$(LIB) -- $(RTL_SRCS)
	$(GHDL) -a $(GHDLFLAGS) --work=work $(XIP_CPU_SIM_SRCS)

elab-xip-cpu: analyze-xip-cpu
	$(GHDL) -e $(GHDLFLAGS) --work=work $(XIP_CPU_TB)

run-xip-cpu: elab-xip-cpu
	$(GHDL) -r $(GHDLFLAGS) --work=work $(XIP_CPU_TB) $(GHDLRUNFLAGS)

# Simulates any testbench by name, without needing a dedicated target
# per testbench like the ones above. Does NOT regenerate $(IMEM_VHD) or
# touch RAMDISK_ENABLE -- it simulates whatever ROM/RAM content is
# already baked in (e.g. "make sim SIM_TB=cpm_neo" needs "make cpm-neo"
# to have run first).
sim: $(BUILD)
	@if [ -z "$(SIM_TB)" ]; then \
		echo "Usage: make sim SIM_TB=<name>  (e.g. make sim SIM_TB=cpm_neo for sim/cpm-neo/tinymcu_tb_cpm_neo.vhd's tb_cpm_neo)" >&2; \
		exit 1; \
	fi
	@if [ -z "$(SIM_GENERIC_FILE)" ]; then \
		echo "No testbench found matching tinymcu_tb_$(SIM_TB).vhd under $(SIM_DIR)" >&2; \
		exit 1; \
	fi
	bash $(GHDL_ANALYZE) $(GHDLFLAGS) --work=$(LIB) -- $(RTL_SRCS)
	$(GHDL) -a $(GHDLFLAGS) --work=work $(SIM_GENERIC_FILE)
	$(GHDL) -e $(GHDLFLAGS) --work=work tb_$(SIM_TB)
	$(GHDL) -r $(GHDLFLAGS) --work=work tb_$(SIM_TB) $(GHDLRUNFLAGS)

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
	@echo "  run-xip-cpu - regenerate the ROM from asm_xip.py, then"
	@echo "               analyze, elaborate and simulate $(XIP_CPU_TB)"
	@echo "               (XIP controller through the full CPU pipeline;"
	@echo "               'sim SIM_TB=xip' tests the standalone controller)"
	@echo "  wave       - like run-core, but also dump $(BUILD)/$(TB).ghw"
	@echo "  sim SIM_TB=<name> - simulate any testbench by name, e.g."
	@echo "               SIM_TB=cpm_neo for tb_cpm_neo -- doesn't touch"
	@echo "               $(IMEM_VHD)/RAMDISK_ENABLE"
	@echo "  analyze    - syntax/semantic check only, no simulation"
	@echo "  asm        - just regenerate the ROM/testbench from asm.py"
	@echo "  asm-irq    - just regenerate the ROM from asm_irq.py"
	@echo "  asm-mult-cpu - just regenerate the ROM from asm_mult.py"
	@echo "  asm-div-cpu - just regenerate the ROM from asm_div.py"
	@echo "  asm-xip-cpu - just regenerate the ROM from asm_xip.py"
	@echo "  cpm-neo    - build sw/cpm-neo/ for the tinymcu platform and bake"
	@echo "               both its bootloader and disk image into the RTL"
	@echo "               (see the sw/cpm-neo/ integration comment above)"
	@echo "  cpm-neo-rom     - just the bootloader half of cpm-neo"
	@echo "  cpm-neo-ramdisk - just the disk-image half of cpm-neo"
	@echo "  set-generics    - just patch RAM_ADDR_WIDTH/RAMDISK_ADDR_WIDTH/"
	@echo "               RAMDISK_ENABLE (=true)"
	@echo "  disable-ramdisk - set RAMDISK_ENABLE=false; runs automatically"
	@echo "               before every asm* target"
	@echo "  clean      - remove the build directory"
