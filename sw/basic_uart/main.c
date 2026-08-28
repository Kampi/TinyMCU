/*
 * TinyMCU UART "Hello World" demo.
 *
 * Sends "Hello World" over UART once a second, timed by polling the
 * Timer peripheral's free-running COUNTER register against a target
 * tick count (same polling approach as the original sw/led_blink demo,
 * no interrupts needed for something this simple).
 *
 * Assumes a 16 MHz input clock (clk_i), given as a project constant
 * below rather than read from hardware. TinyMCU has no way to query its
 * own clock frequency. Adjust INPUT_CLOCK_HZ if the actual clock
 * differs.
 */

#include "tinymcu_timer.h"
#include "tinymcu_uart.h"

#define INPUT_CLOCK_HZ          16000000u
#define UART_BAUD               9600u
#define UART_CLKS_PER_BIT       ((INPUT_CLOCK_HZ + UART_BAUD / 2u) / UART_BAUD)
#define CLK_TICKS_PER_SECOND    (INPUT_CLOCK_HZ / 1024u)

int main (void) {
    tinymcu_uart_init(UART_CLKS_PER_BIT, TINYMCU_UART_DATABITS_8,
                      TINYMCU_UART_STOPBITS_1, TINYMCU_UART_PARITY_NONE);

    tinymcu_timer_reset();
    tinymcu_timer_set_clksel(TINYMCU_TIMER_CLKSEL_DIV1024);

    while (1) {
        while (tinymcu_timer_read() < CLK_TICKS_PER_SECOND) {
        }
        tinymcu_timer_reset();

        tinymcu_uart_puts("Hello World\r\n");
    }

    return 0;
}
