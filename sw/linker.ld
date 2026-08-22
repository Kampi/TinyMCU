/*
 * TinyMCU minimal linker script (RV32I, freestanding, no OS).
 */

MEMORY
{
    ROM (rx)    : ORIGIN = 0x00000000, LENGTH = 4K
    FLASH (rwx) : ORIGIN = 0x00001000, LENGTH = 0xFFF000
    RAM (rwx)   : ORIGIN = 0x02000000, LENGTH = 1K
}

/* Stack grows down from the top of RAM. */
_stack_top = ORIGIN(RAM) + LENGTH(RAM);

SECTIONS
{
    .text : {
        KEEP(*(.text.start))
        *(.text .text.*)
    } > ROM

    /* .srodata is RISC-V GCC's "small data" counterpart to .rodata (const
     * objects at or below -msmall-data-limit, default 8 bytes) -- without
     * this, such objects fall through as orphan sections instead of
     * landing here. */
    .rodata : {
        *(.rodata .rodata.*)
        *(.srodata .srodata.*)
    } > ROM

    /* Initial values for .data live in ROM (load address); the
     * section itself is linked to run from RAM (run address). crt0.s
     * copies LMA -> VMA at startup -- see _data_lma below.
     *
     * .sdata is .data's small-data counterpart (see .srodata above) --
     * it must be captured here too, or its initializer never ends up
     * inside [_data_start, _data_end) and crt0.s's copy loop skips it,
     * leaving RAM at its power-on value (0) instead of the initializer. */
    .data : {
        _data_start = .;
        *(.data .data.*)
        *(.sdata .sdata.*)
        _data_end = .;
    } > RAM AT> ROM
    _data_lma = LOADADDR(.data);

    .bss (NOLOAD) : {
        _bss_start = .;
        *(.bss .bss.* COMMON)
        *(.sbss .sbss.* .scommon)
        _bss_end = .;
    } > RAM

    /* Referenced by crt0.s; linker relaxation is disabled (see
     * crt0.s/Makefile) so its exact position does not affect
     * correctness, only its existence as a defined symbol matters. */
    __global_pointer$ = MIN(_data_start + 0x800, MAX(_data_end - 0x800, _data_start));

    /DISCARD/ : { *(.comment .eh_frame .riscv.attributes) }
}
