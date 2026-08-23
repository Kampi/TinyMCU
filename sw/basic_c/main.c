/*
 * TinyMCU minimal demo program.
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

int main (void) {
    int b = 10;

    *RESULT = (unsigned int)add(a, b);

    while (1) {
    }

    return 0;
}
