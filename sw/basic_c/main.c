/*
 * TinyMCU minimal demo program (RV32I, freestanding).
 *
 * No libc, no syscalls, no interrupts and nothing beyond plain RV32I is
 * implemented by the core (see README.md "Extensions"), and crt0.s does
 * not install a trap handler. In particular: no M extension, so do not
 * use '*', '/' or '%' on int here. GCC would emit calls to libgcc's
 * software multiply/divide routines (__mulsi3/__divsi3/...), which are
 * not linked in by this minimal, -nostdlib build.
 *
 * Computes a value with a real function call (exercises JAL/JALR and
 * the stack set up by crt0.s) and stores it to a fixed RAM address,
 * then loops forever.
 */

volatile const int a = 5;

static int add(int a, int b) {
    return a + b;
}

/* Offset 0x10 into RAM (RAM starts at 0x0200_0000, see linker.ld and
 * tinymcu_addr_decoder.vhd/tinymcu_pkg.vhd's RAM_BASE). Arbitrary,
 * chosen only so the result is easy to find in a memory dump/waveform.
 * TinyMCU has no memory-mapped peripherals yet, so this is plain RAM,
 * not an I/O register. */
static volatile unsigned int *const RESULT = (unsigned int *)0x02000010;

int main(void) {
    int b = 10;

    *RESULT = (unsigned int)add(a, b);

    while (1) {
    }

    return 0;
}
