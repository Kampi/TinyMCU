# SPDX-License-Identifier: GPL-3.0-or-later

# Minimal M-mode trap entry stub, installed into mtvec by
# tinymcu_trap_init() (see tinymcu_trap.h/.c).

    .section .text
    .global trap_entry
    .align 2

trap_entry:
    addi sp, sp, -64
    sw ra,   0(sp)
    sw t0,   4(sp)
    sw t1,   8(sp)
    sw t2,  12(sp)
    sw t3,  16(sp)
    sw t4,  20(sp)
    sw t5,  24(sp)
    sw t6,  28(sp)
    sw a0,  32(sp)
    sw a1,  36(sp)
    sw a2,  40(sp)
    sw a3,  44(sp)
    sw a4,  48(sp)
    sw a5,  52(sp)
    sw a6,  56(sp)
    sw a7,  60(sp)

    # mcause/mepc read here, before tinymcu_trap_handler can run any
    # other code that might disturb them, and passed in as its two
    # arguments (a0/a1). The caller's own a0/a1 are already saved above
    # and get restored from the stack below regardless, so overwriting
    # them here for the call is safe.
    csrr a0, mcause
    csrr a1, mepc
    call tinymcu_trap_handler

    lw ra,   0(sp)
    lw t0,   4(sp)
    lw t1,   8(sp)
    lw t2,  12(sp)
    lw t3,  16(sp)
    lw t4,  20(sp)
    lw t5,  24(sp)
    lw t6,  28(sp)
    lw a0,  32(sp)
    lw a1,  36(sp)
    lw a2,  40(sp)
    lw a3,  44(sp)
    lw a4,  48(sp)
    lw a5,  52(sp)
    lw a6,  56(sp)
    lw a7,  60(sp)
    addi sp, sp, 64

    mret

    .size trap_entry, . - trap_entry
