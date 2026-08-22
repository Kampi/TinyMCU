# TinyMCU minimal startup code (RV32I, freestanding, no OS/exit).

    .section .text.start
    .global _start

_start:
    .option push
    .option norelax

    la   gp, __global_pointer$
    .option pop

    la   sp, _stack_top

    # Zero-initialize .bss
    la   t0, _bss_start
    la   t1, _bss_end
1:  bge  t0, t1, 2f
    sw   zero, 0(t0)
    addi t0, t0, 4
    j    1b
2:

    la   t0, _data_lma
    la   t1, _data_start
    la   t2, _data_end
3:  bge  t1, t2, 4f
    lw   t3, 0(t0)
    sw   t3, 0(t1)
    addi t0, t0, 4
    addi t1, t1, 4
    j    3b
4:

    call main

    # main() must not return on bare metal -- halt.
5:  j    5b

    .size _start, . - _start
