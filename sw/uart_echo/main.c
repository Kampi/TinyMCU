/*
 * TinyMCU UART echo demo.
 *
 * Reads a byte from the UART and immediately sends it back.
 *
 * Assumes a 16 MHz input clock (clk_i), given as a project constant
 * below rather than read from hardware. TinyMCU has no way to query its
 * own clock frequency. Adjust INPUT_CLOCK_HZ if the actual clock
 * differs.
 */

#include "tinymcu_uart.h"

#define INPUT_CLOCK_HZ    16000000u
#define UART_BAUD         9600u
#define UART_CLKS_PER_BIT ((INPUT_CLOCK_HZ + UART_BAUD / 2u) / UART_BAUD)

int main (void) {
    tinymcu_uart_init(UART_CLKS_PER_BIT, TINYMCU_UART_DATABITS_8,
                       TINYMCU_UART_STOPBITS_1, TINYMCU_UART_PARITY_NONE);

    while (1) {
        unsigned int c = tinymcu_uart_getc();
        tinymcu_uart_putc((char)c);
    }

    return 0;
}
