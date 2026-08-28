# TinyMCU

[![Documentation](https://img.shields.io/badge/Documentation-HTML-007ec6?longCache=true&style=flat&logo=asciidoctor&colorA=555555)](docs/index.html)

## Table of Contents

- [TinyMCU](#tinymcu)
  - [Table of Contents](#table-of-contents)
  - [Directory Layout](#directory-layout)
  - [Required tools](#required-tools)
  - [RISC-V Toolchain (from source)](#risc-v-toolchain-from-source)
  - [CP/M Neo](#cpm-neo)
    - [Getting the source](#getting-the-source)
    - [Memory layout](#memory-layout)
    - [Building](#building)
  - [Extensions](#extensions)
  - [Supported Instructions](#supported-instructions)
  - [Not Supported Instructions](#not-supported-instructions)
  - [Implemented CSRs](#implemented-csrs)
  - [Interrupts](#interrupts)
  - [Register (ABI) Names](#register-abi-names)
  - [Scripts](#scripts)
  - [Ressources](#ressources)
  - [Maintainer](#maintainer)

## Directory Layout

```
rtl/
├── Makefile            single Makefile for everything below: classic GHDL
│                       regression (make/make run), any testbench by name
│                       (make sim SIM_TB=<name>), and CP/M Neo (make cpm-neo)
├── tinymcu_pkg.vhd     shared types/constants, used by everything below
├── core/               CPU pipeline + memory/bus infrastructure
│   ├── tinymcu_cpu.vhd
│   ├── tinymcu_cpu_alu.vhd
│   ├── tinymcu_cpu_control.vhd
│   ├── tinymcu_cpu_csrfile.vhd
│   ├── tinymcu_cpu_div.vhd
│   ├── tinymcu_cpu_mult.vhd
│   ├── tinymcu_cpu_regfile.vhd
│   ├── tinymcu_addr_decoder.vhd
│   ├── tinymcu_imem.vhd,
│   ├── tinymcu_imem_bootrom.vhd
│   ├── tinymcu_sram.vhd        -- also tinymcu_ram_subsystem, see CP/M Neo below
│   └── tinymcu_sram_generic.vhd
└── peripherals/        peripheral bus mux + peripherals
    ├── tinymcu_periph.vhd
    ├── tinymcu_periph_gpio.vhd
    ├── tinymcu_periph_timer.vhd
    └── tinymcu_periph_uart.vhd
integration/            Vivado project (TinyMCU.srcs/.../tinymcu_top.vhd is the
                        FPGA-facing top level -- Vivado's project layout keeps
                        it here, not under rtl/)
sim/                    testbenches (see rtl/Makefile's SIM_SRCS/IRQ_SIM_SRCS/...,
                        or "make sim SIM_TB=<name>" for any of them by name)
├── core/               tinymcu_cpu-level and standalone core-component testbenches
├── peripherals/        standalone peripheral testbenches
└── cpm-neo/            boots the real sw/cpm-neo/ image in simulation
scripts/                see Scripts below
sw/                     C/asm firmware (see sw/*/Makefile)
└── cpm-neo/            CP/M Neo, see CP/M Neo below
patches/                sw/cpm-neo/'s TinyMCU port, see CP/M Neo's
                        "Getting the source" below
```

## Required tools

| Tool | Purpose | Install (Debian/Ubuntu) |
|------|---------|--------------------------|
| RISC-V GCC (`riscv64-unknown-elf-gcc`) | Compiles `sw/*` C/asm programs (`sw/*/Makefile`) and CP/M Neo (`sw/cpm-neo/`, see [CP/M Neo](#cpm-neo)) | Build from source, see [RISC-V Toolchain (from source)](#risc-v-toolchain-from-source) |
| GHDL, `--std=08` | Analyzes/elaborates/simulates the VHDL testbenches (`rtl/Makefile`) | `sudo apt install ghdl` |
| Python 3 | Runs `scripts/*.py` (see [Scripts](#scripts)) | usually preinstalled |
| GNU Make | Drives `rtl/Makefile` and `sw/*/Makefile` | `sudo apt install make` |
| GTKWave *(optional)* | Views the `.ghw` waveform from `rtl/Makefile`'s `make wave` | `sudo apt install gtkwave` |
| Picolibc | Used by `sw/printf_demo` only; a plain prebuilt library, independent of which GCC built it | `sudo apt install picolibc-riscv64-unknown-elf` |

## RISC-V Toolchain (from source)

```sh
# Remove the old packages and install build dependencies (one-time, needs sudo)
sudo apt remove -y gcc-riscv64-unknown-elf binutils-riscv64-unknown-elf
sudo apt install -y curl libmpc-dev libmpfr-dev libgmp-dev gperf \
    patchutils libexpat-dev ninja-build cmake libglib2.0-dev
sudo mkdir -p /opt/riscv && sudo chown "$USER":"$USER" /opt/riscv

# Build binutils + GCC + newlib (~15-30 min on a modern multi-core machine)
git clone --depth 1 https://github.com/riscv-collab/riscv-gnu-toolchain.git
cd riscv-gnu-toolchain
git submodule update --init --depth 1 binutils gcc newlib
./configure --prefix=/opt/riscv --with-multilib-generator="rv32im-ilp32--"
make -j"$(nproc)"
```

Add the new toolchain to `PATH` (e.g. in `~/.bashrc`):

```sh
export PATH="/opt/riscv/bin:$PATH"
```

`riscv64-unknown-elf-gcc`/`-ld`/... resolve to the new build afterwards. Every `sw/*/Makefile` and `sw/cpm-neo/Makefile` keep working unchanged, since they only override `CROSS`/`ARCH`, never a hardcoded compiler path.

## CP/M Neo

[CP/M Neo](https://github.com/Mazin-O3/cpm-neo) is vendored as a git submodule at `sw/cpm-neo/`, ported to run on TinyMCU as a new hardware platform (`platform/tinymcu/`). See `sw/cpm-neo/docs/` for CP/M Neo's own documentation (BIOS interface, syscalls, disk format, ...); this section covers only the TinyMCU-specific integration on top of it.

| Path | Purpose |
|------|---------|
| `sw/cpm-neo/platform/tinymcu/bios.c` | The 7-function BIOS layer: UART console (polled, not interrupt-driven), Timer-based `bios_time()`, RAM-disk-backed `bios_read`/`bios_write` |
| `sw/cpm-neo/platform/tinymcu/mmio.h` | TinyMCU's real peripheral addresses (`rtl/tinymcu_pkg.vhd`), replacing vemu's flat, `__io_base`-relative memory model |
| `sw/cpm-neo/platform/tinymcu/platform_base.h` | `PLATFORM_RAM_BASE = 0x02000000`, picked up automatically by `core/kernel/kernel_abi.h`'s `TPA_LOAD_ADDR` and `sdk/linker/linker_sdk.ld`'s `__tpa_base` -- both are otherwise written for a platform whose RAM starts at address 0 (e.g. vemu) |
| `sw/cpm-neo/arch/tinymcu-riscv32/` | `config.sh` (`rv32im`/`ilp32`, identical to `arch/riscv32`), `boot.S` (unchanged), `linker_boot.ld` (places the bootloader in TinyMCU's real ROM/RAM instead of vemu's flat 0-based model) |
| `sw/cpm-neo/core/kernel/linker_kernel.ld` | Patched (this file is shared across every platform, not selectable per-platform) so the kernel/TPA are placed at TinyMCU's real `RAM_BASE` instead of address 0 |
| `sw/cpm-neo/Makefile` | Builds `sysgen` and runs `sysgen new` with the disk/mem sizes it's given -- has no opinion of its own about TinyMCU's memory layout, see `rtl/Makefile` below |

### Getting the source

`sw/cpm-neo/` is a git submodule pointing at [Mazin-O3/cpm-neo](https://github.com/Mazin-O3/cpm-neo); the TinyMCU port is a single commit ("Add support for TinyMCU") on top of it, kept only in this local checkout -- **not** pushed to that (third-party) remote. `git submodule update --init` alone therefore can't fetch it on a fresh clone: the submodule's recorded commit simply isn't reachable from its configured `origin`.

Instead, the port is kept as a patch, `patches/0001-Add-support-for-TinyMCU.patch`, applied on top of a plain clone of upstream CP/M Neo:

```sh
git clone https://github.com/Mazin-O3/cpm-neo.git sw/cpm-neo
cd sw/cpm-neo
git am ../../patches/0001-Add-support-for-TinyMCU.patch
```

This reproduces the exact same ported state from a clean upstream checkout -- no push access to the upstream repo needed, and the patch file makes exactly what TinyMCU-specific changes were made explicit and reviewable in one place, rather than buried in a submodule pointer.

If `sw/cpm-neo/`'s TinyMCU port changes further, regenerate the patch from the submodule's own history (`be0851c` is upstream's last commit before the TinyMCU one; substitute the current commit for `HEAD` if it's no longer the tip):

```sh
cd sw/cpm-neo
git format-patch -1 HEAD -o ../../patches/
```

### Memory layout

Unlike a typical CP/M Neo platform (one combined RAM region for kernel/TPA + disk), TinyMCU keeps them as two independent SRAM blocks, each its own power of two, decoded at its own top-byte window (`rtl/core/tinymcu_addr_decoder.vhd`) -- see `docs/memory.html` for the full address map:

- **Kernel/TPA RAM** `RAM_BASE` = `0x02000000`, 64 KB (`RAM_ADDR_WIDTH=14`, `rtl/core/tinymcu_cpu.vhd`). Always present.
- **RAM disk** its own window at `0x03000000`, 128 KB (`RAMDISK_ADDR_WIDTH=15`), 256 x 512 B sectors (`platform/tinymcu/bios.c`'s `TINYMCU_RAMDISK_BASE`/`TINYMCU_RAMDISK_SECTORS`). Only exists in hardware when `RAMDISK_ENABLE` (`rtl/core/tinymcu_cpu.vhd`) is `true`, when `false`, there is no SRAM array/BRAM for it at all, and its address window reads as unmapped, same as any other unassigned address. Classic (non-CP/M-Neo) builds run with it disabled (`rtl/Makefile`'s `disable-ramdisk`, automatic before every `sw/*`-style test program build).

When enabled, the RAM disk is ordinary general-purpose memory, usable for data *and code* exactly like RAM -- not a special "disk" region at the hardware level. `sw/cpm-neo/`'s BIOS is what gives it disk semantics in software (`bios_read`/`bios_write` treating it as 512 B sectors) and nothing stops other code from running directly out of it. TinyMCU's instruction fetch (`rtl/core/tinymcu_imem.vhd`) only reaches the RAM disk (and the kernel/TPA RAM) when `RAMDISK_ENABLE` is `true` and when `false`, the CPU can only ever execute out of the Boot ROM.

Both blocks are volatile: they start empty on every reset, since TinyMCU has no real storage peripheral yet (no SPI/SD/flash controller in `rtl/peripherals/`). Getting an actual kernel/disk image's bytes into that window on real hardware (there's no runtime loading mechanism, only what's baked into the bitstream) is `rtl/Makefile`'s job.

### Building

```sh
cd rtl
make cpm-neo
```

Requires the from-source toolchain above. Afterwards, a real Vivado synthesis/implementation run picks up the new generic values and baked ROM/RAM content (GHDL simulation picks it up on its next analyze). To try it without hardware first: `make sim SIM_TB=cpm_neo` boots the exact same baked-in image in GHDL simulation (`sim/cpm-neo/tinymcu_tb_cpm_neo.vhd`), with `tinymcu_cpu.vhd`'s `TRACE_ENABLE` on for a full per-cycle PC/disassembly trace.

`make cpm-neo-rom`/`make cpm-neo-ramdisk` build just the bootloader/disk half respectively; `make disable-ramdisk` (run automatically before every classic `sw/*`-style testbench target) sets `RAMDISK_ENABLE=false` and clears any stale disk content, so a previous `make cpm-neo` run never lingers into an unrelated build by accident.

## Extensions

| Extension | Status         | Notes |
|-----------|----------------|-------|
| RV32I     | Implemented    | Full base integer ISA except `FENCE`/`ECALL`/`EBREAK`, see below |
| Zicsr     | Partially implemented| All 6 `CSRR*` instructions work against a small, fixed set of CSRs (see [Implemented CSRs](#implemented-csrs)); trap entry/exit (`MRET`) and a single external interrupt line work end-to-end (see [Interrupts](#interrupts)), M-mode only (no other privilege modes) |
| Zifencei  | Not implemented| `FENCE.I` |
| B (Zba, Zbb, Zbc, Zbs)| Partially implemented| Every R-type bit-manipulation op, its `*I` immediate counterpart, and the five `OPC_OPIMM`-only unary ops (`CLZ`/`CTZ`/`CPOP`/`SEXT.B`/`SEXT.H`) work end-to-end, verified through the full pipeline, not just the ALU in isolation (see [Supported Instructions](#supported-instructions)). Those five share one `funct7`+`funct3` pair and are only distinguished by `instr(24 downto 20)`, so `alu_op` (`tinymcu_pkg.vhd`) carries that field too now, as a `subfunc` forced to a sentinel value everywhere else it doesn't apply (so it can't leak into e.g. `ROL`, which happens to share that same `funct7`+`funct3` pair under a different opcode). `ORC.B`/`REV8` are not implemented: their exact encoding wasn't verified with enough confidence to risk a silently wrong implementation. `disassemble()` knows all the implemented B-extension mnemonics, including the five unary ops |
| M         | Implemented    | All 8 instructions (`MUL` `MULH` `MULHSU` `MULHU` `DIV` `DIVU` `REM` `REMU`), verified through the full pipeline, not just the units in isolation (see [Supported Instructions](#supported-instructions)). Multiply (`tinymcu_cpu_mult.vhd`) and divide (`tinymcu_cpu_div.vhd`) are separate multi-cycle units, sitting alongside the ALU rather than inside it: a shift-add multiplier and a restoring shift-subtract divider, each taking 32 cycles and stalling the pipeline for their duration (`stall`/`dispatched` in `tinymcu_cpu.vhd`). The divider also implements the RISC-V-mandated division-by-zero and signed-overflow (`(-2^31)/(-1)`) special cases in hardware, without trapping, per spec |
| A, F, D, C, ...| Not implemented| No other standard extensions |

## Supported Instructions

TinyMCU implements the full RV32I base integer instruction set, with the
exception of the system/synchronization instructions listed below.

| Category      | Instructions |
|----------------|--------------|
| ALU reg-reg    | `ADD` `SUB` `AND` `OR` `XOR` `SLL` `SRL` `SRA` `SLT` `SLTU` |
| ALU reg-imm    | `ADDI` `ANDI` `ORI` `XORI` `SLLI` `SRLI` `SRAI` `SLTI` `SLTIU` |
| Upper immediate| `LUI` `AUIPC` |
| Jump           | `JAL` `JALR` |
| Branch         | `BEQ` `BNE` `BLT` `BGE` `BLTU` `BGEU` |
| Load           | `LB` `LH` `LW` `LBU` `LHU` |
| Store          | `SB` `SH` `SW` |
| CSR            | `CSRRW` `CSRRS` `CSRRC` `CSRRWI` `CSRRSI` `CSRRCI` (see [Implemented CSRs](#implemented-csrs) for which CSR addresses actually do anything) |
| Trap return    | `MRET` (see [Interrupts](#interrupts)) |
| Bit manipulation (B) | `SH1ADD` `SH2ADD` `SH3ADD` `ANDN` `ORN` `XNOR` `MIN` `MINU` `MAX` `MAXU` `ROL` `ROR` `RORI` `CLMUL` `CLMULR` `CLMULH` `BCLR` `BCLRI` `BSET` `BSETI` `BINV` `BINVI` `BEXT` `BEXTI` `CLZ` `CTZ` `CPOP` `SEXT.B` `SEXT.H` |
| Multiply/Divide (M) | `MUL` `MULH` `MULHSU` `MULHU` `DIV` `DIVU` `REM` `REMU` |

## Not Supported Instructions

| Category       | Instructions |
|-----------------|--------------|
| System           | `ECALL` `EBREAK` `WFI` |
| Memory ordering  | `FENCE` |
| Bit manipulation (B) | `ORC.B` `REV8` -- not implemented, encoding not verified with enough confidence (see [Extensions](#extensions)). Also N/A on RV32 regardless: `ADD.UW`/`SH1ADD.UW`/`SH2ADD.UW`/`SH3ADD.UW`/`SLLI.UW` (Zba), RV64-only, encoded on the OP-32 opcode which doesn't exist on RV32 at all |

## Implemented CSRs

`tinymcu_cpu_csrfile.vhd` implements the minimal M-mode register set needed for trap handling. Any other CSR address reads as 0 and silently ignores writes, same as an unmapped address elsewhere on the bus.

| CSR        | Address | Notes |
|------------|---------|-------|
| `mstatus`  | `0x300` | Global/previous interrupt-enable bits (`MIE`/`MPIE`) |
| `mie`      | `0x304` | Per-source interrupt enable |
| `mtvec`    | `0x305` | Trap handler base address |
| `mscratch` | `0x340` | Scratch register for the trap handler prologue |
| `mepc`     | `0x341` | Trap return address, restored to the PC by `MRET` |
| `mcause`   | `0x342` | Trap cause, set by hardware on trap entry |
| `mtval`    | `0x343` | Trap-specific info (not populated by hardware yet) |
| `mip`      | `0x344` | Pending interrupts; the `MEIP`/`MTIP`/`MSIP` bits live-overlay the CPU's IRQ input lines (see [Interrupts](#interrupts)) on every read, the rest is plain software-writable storage |
| `mvendorid`| `0xF11` | Read-only, hardwired to 0 (means "not implemented" per spec) |
| `marchid`  | `0xF12` | Read-only, hardwired to 0 |
| `mimpid`   | `0xF13` | Read-only; 0 on an unreleased/dev build, otherwise the release version (see below) |

`mimpid`'s value comes from `rtl/tinymcu_pkg.vhd`'s `MIMPID` constant, which `scripts/set_mimpid.py` sets from a release version string (e.g. `1.4.2`, packed as MAJOR in bits 31:24, MINOR in bits 23:16, PATCH in bits 15:0). Meant to be run by a CI/CD release job, not by hand:

```sh
scripts/set_mimpid.py 1.4.2          # from an explicit argument
RELEASE_VERSION=1.4.2 scripts/set_mimpid.py   # or from the environment
```

The checked-in default is 0, meaning "no release version stamped" (a dev/unreleased build), same meaning as `mvendorid`/`marchid`'s 0.

## Interrupts

TinyMCU implements the standard RV32 M-mode trap mechanism (`tinymcu_cpu.vhd` and `tinymcu_cpu_csrfile.vhd`):

- On a pending, enabled interrupt (`mstatus.MIE = 1` and the matching `mie`/`mip` bit both set), the pipeline redirects to `mtvec`, saves the interrupted PC into `mepc`, encodes the source into `mcause` (bit 31 = 1, low bits = the standard cause code: 3 software / 7 timer / 11 external), and saves/clears `mstatus.MIE` via `MPIE`.
- `MRET` restores `mstatus.MIE` from `MPIE` and redirects the PC back to `mepc`.
- Priority when multiple sources are pending at once: external > software > timer.

Of the three standard M-mode sources, only the external one is wired to an actual input pin so far: `ext_irq_i` (`tinymcu_top`/`tinymcu_cpu`) directly drives `mip.MEIP`. `timer_irq_i`/`software_irq_i` exist as ports on `tinymcu_cpu_csrfile.vhd` but are hardwired to `'0'` in `tinymcu_cpu.vhd` until a timer/software-interrupt peripheral exists.

`rtl/Makefile`'s `make run-irq` exercises the full trap-entry-and-return round trip in simulation (`sim/core/tinymcu_tb_irq.vhd`); see [Scripts](#scripts).

## Register (ABI) Names

Standard RISC-V calling-convention names for `x0`-`x31`, as used by the GCC toolchain (`objdump` output, register names in generated assembly) and by `tinymcu_pkg.vhd`'s `disassemble()` trace function.

| Register | ABI name | Meaning |
|----------|----------|---------|
| `x0`  | `zero`    | Hardwired to 0 |
| `x1`  | `ra`      | Return address |
| `x2`  | `sp`      | Stack pointer |
| `x3`  | `gp`      | Global pointer |
| `x4`  | `tp`      | Thread pointer |
| `x5`-`x7`   | `t0`-`t2`   | Temporaries |
| `x8`  | `s0`/`fp` | Saved register / frame pointer |
| `x9`  | `s1`      | Saved register |
| `x10`-`x11` | `a0`-`a1`   | Function arguments / return values |
| `x12`-`x17` | `a2`-`a7`   | Function arguments |
| `x18`-`x27` | `s2`-`s11`  | Saved registers |
| `x28`-`x31` | `t3`-`t6`   | Temporaries |

Purely a software convention (the ABI, followed by the GCC toolchain in `sw/*`); `tinymcu_cpu_regfile.vhd` itself treats all 32 registers identically except `x0`, which is hardwired to 0 in hardware.

## Scripts

CLI tools live directly under `scripts/` (`--help` for each one's full option list); shared modules (not meant to be run directly) live in `scripts/lib/`.

| Script | Purpose |
|--------|---------|
| `asm.py` | Hand-assembled demo/self-test program: writes `rtl/core/tinymcu_imem_bootrom.vhd`'s ROM content and `sim/tinymcu_tb_core.vhd`'s register checks from a single definition, so they can't drift apart. Run automatically by `rtl/Makefile`'s `make`/`make run`. |
| `asm_irq.py` | Hand-assembled IRQ/`MRET` round-trip test program: writes `rtl/core/tinymcu_imem_bootrom.vhd`. Run automatically by `rtl/Makefile`'s `make run-irq`. |
| `asm_mult.py` | Hand-assembled M-extension multiply pipeline-integration test program: writes `rtl/core/tinymcu_imem_bootrom.vhd`. Run automatically by `rtl/Makefile`'s `make run-mult-pipeline`. |
| `asm_div.py` | Same idea as `asm_mult.py`, for the divider. Run automatically by `rtl/Makefile`'s `make run-div-pipeline`. |
| `hex2rom.py` | Writes a compiled `sw/*` program's Intel HEX output into the ROM. Run automatically by `sw/*/Makefile`'s `make rom`. Also clears any stale CP/M Neo disk content (see `cpm_neo_ramdisk2rom.py` below), so it never lingers into an unrelated ROM bake by accident. |
| `cpm_neo_ramdisk2rom.py` | Bakes a CP/M Neo disk image into `tinymcu_sram_generic.vhd`'s `DISK` constant -- same idea as `hex2rom.py`, but for the RAM disk instead of the Boot ROM. Run automatically by `rtl/Makefile`'s `make cpm-neo`/`make cpm-neo-ramdisk`, see [CP/M Neo](#cpm-neo). |
| `rom2hex.py` | Reverse of `hex2rom.py`: snapshots whatever program is currently embedded in the ROM back out to an Intel HEX file, so it isn't lost when something else overwrites it. |
| `set_mimpid.py` | Stamps a release version into the `mimpid` CSR's hardwired value (`rtl/tinymcu_pkg.vhd`). Meant for a CI/CD release job, see [Implemented CSRs](#implemented-csrs). |
| `ghdl_analyze.sh` | Analyzes a set of VHDL files into a GHDL library without requiring them to be listed in dependency order (multi-pass, retries files whose dependencies weren't analyzed yet). Used internally by `rtl/Makefile`. |
| `lib/rom_writer.py` | Shared module: writes generated content into a VHDL file between a pair of marker comments without disturbing the rest of the file. Used by `asm.py`, `asm_irq.py`, `asm_mult.py`, `asm_div.py`, `hex2rom.py`, `rom2hex.py`. |
| `lib/riscv_isa.py` | Shared module: RV32I/Zicsr/M-extension instruction encoders and opcode/CSR-address constants. Used by `asm.py`, `asm_irq.py`, `asm_mult.py`, `asm_div.py`. |

## Ressources

- [Instructions](https://www.cs.cornell.edu/courses/cs3410/2026sp/rsrc/riscv-ref.htmle)

## Maintainer

- [Daniel Kampert](mailto:DanielKampert@kampis-elektroecke.de)
