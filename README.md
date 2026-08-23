# TinyMCU

## Table of Contents

- [TinyMCU](#tinymcu)
  - [Table of Contents](#table-of-contents)
  - [Directory Layout](#directory-layout)
  - [Required tools](#required-tools)
  - [Extensions](#extensions)
  - [Supported Instructions](#supported-instructions)
  - [Not Supported Instructions](#not-supported-instructions)
  - [Implemented CSRs](#implemented-csrs)
  - [Interrupts](#interrupts)
  - [Register (ABI) Names](#register-abi-names)
  - [Scripts](#scripts)
  - [Maintainer](#maintainer)

## Directory Layout

```
rtl/
├── tinymcu_pkg.vhd     shared types/constants, used by everything below
├── tinymcu_top.vhd     FPGA-facing top level
├── core/               CPU pipeline + memory/bus infrastructure
│   ├── tinymcu_cpu.vhd
│   ├── tinymcu_cpu_alu.vhd
│   ├── tinymcu_cpu_control.vhd
│   ├── tinymcu_cpu_csrfile.vhd
│   ├── tinymcu_cpu_regfile.vhd
│   ├── tinymcu_addr_decoder.vhd
│   ├── tinymcu_imem.vhd,
│   ├── tinymcu_imem_bootrom.vhd
│   ├── tinymcu_sram.vhd
│   └── tinymcu_sram_generic.vhd
└── peripherals/        peripheral bus mux + peripherals
    ├── tinymcu_periph.vhd
    └── tinymcu_periph_gpio.vhd
sim/                    testbenches (see rtl/Makefile's SIM_SRCS/IRQ_SIM_SRCS)
scripts/                see Scripts below
sw/                     C/asm firmware (see sw/*/Makefile)
```

## Required tools

| Tool | Purpose | Install (Debian/Ubuntu) |
|------|---------|--------------------------|
| RISC-V GCC (`riscv64-unknown-elf-gcc`) | Compiles `sw/*` C/asm programs (`sw/*/Makefile`) | `sudo apt install gcc-riscv64-unknown-elf` |
| GHDL, `--std=08` | Analyzes/elaborates/simulates the VHDL testbenches (`rtl/Makefile`) | `sudo apt install ghdl` |
| Python 3 | Runs `scripts/*.py` (see [Scripts](#scripts)) | usually preinstalled |
| GNU Make | Drives `rtl/Makefile` and `sw/*/Makefile` | `sudo apt install make` |
| GTKWave *(optional)* | Views the `.ghw` waveform from `rtl/Makefile`'s `make wave` | `sudo apt install gtkwave` |

## Extensions

| Extension | Status         | Notes |
|-----------|----------------|-------|
| RV32I     | Implemented    | Full base integer ISA except `FENCE`/`ECALL`/`EBREAK`, see below |
| Zicsr     | Partially implemented| All 6 `CSRR*` instructions work against a small, fixed set of CSRs (see [Implemented CSRs](#implemented-csrs)); trap entry/exit (`MRET`) and a single external interrupt line work end-to-end (see [Interrupts](#interrupts)), M-mode only (no other privilege modes) |
| Zifencei  | Not implemented| `FENCE.I` |
| B (Zba, Zbb, Zbc, Zbs)| Partially implemented| Every R-type bit-manipulation op, its `*I` immediate counterpart, and the five `OPC_OPIMM`-only unary ops (`CLZ`/`CTZ`/`CPOP`/`SEXT.B`/`SEXT.H`) work end-to-end, verified through the full pipeline, not just the ALU in isolation (see [Supported Instructions](#supported-instructions)). Those five share one `funct7`+`funct3` pair and are only distinguished by `instr(24 downto 20)`, so `alu_op` (`tinymcu_pkg.vhd`) carries that field too now, as a `subfunc` forced to a sentinel value everywhere else it doesn't apply (so it can't leak into e.g. `ROL`, which happens to share that same `funct7`+`funct3` pair under a different opcode). `ORC.B`/`REV8` are not implemented: their exact encoding wasn't verified with enough confidence to risk a silently wrong implementation. `disassemble()` knows all the implemented B-extension mnemonics, including the five unary ops |
| M, A, F, D, C, ...| Not implemented| No other standard extensions |

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

`rtl/Makefile`'s `make run-irq` exercises the full trap-entry-and-return round trip in simulation (`sim/tinymcu_tb_irq.vhd`); see [Scripts](#scripts).

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
| `asm.py` | Hand-assembled demo/self-test program: writes `rtl/core/tinymcu_imem_bootrom.vhd`'s ROM content and `sim/tinymcu_tb_imem.vhd`'s register checks from a single definition, so they can't drift apart. Run automatically by `rtl/Makefile`'s `make`/`make run`. |
| `asm_irq.py` | Hand-assembled IRQ/`MRET` round-trip test program: writes `rtl/core/tinymcu_imem_bootrom.vhd`. Run automatically by `rtl/Makefile`'s `make run-irq`. |
| `hex2rom.py` | Writes a compiled `sw/*` program's Intel HEX output into the ROM. Run automatically by `sw/*/Makefile`'s `make rom`. |
| `rom2hex.py` | Reverse of `hex2rom.py`: snapshots whatever program is currently embedded in the ROM back out to an Intel HEX file, so it isn't lost when something else overwrites it. |
| `set_mimpid.py` | Stamps a release version into the `mimpid` CSR's hardwired value (`rtl/tinymcu_pkg.vhd`). Meant for a CI/CD release job, see [Implemented CSRs](#implemented-csrs). |
| `ghdl_analyze.sh` | Analyzes a set of VHDL files into a GHDL library without requiring them to be listed in dependency order (multi-pass, retries files whose dependencies weren't analyzed yet). Used internally by `rtl/Makefile`. |
| `lib/rom_writer.py` | Shared module: writes generated content into a VHDL file between a pair of marker comments without disturbing the rest of the file. Used by `asm.py`, `asm_irq.py`, `hex2rom.py`, `rom2hex.py`. |
| `lib/riscv_isa.py` | Shared module: RV32I/Zicsr instruction encoders and opcode/CSR-address constants. Used by `asm.py`, `asm_irq.py`. |

## Maintainer

- [Daniel Kampert](mailto:DanielKampert@kampis-elektroecke.de)
