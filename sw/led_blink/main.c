/*
 * TinyMCU LED chase ("Lauflicht") demo.
 *
 * Walks a single lit LED across 4 GPIO pins (0-3), one step every 100 ms,
 * driven by the Timer peripheral's compare interrupt.
 *
 * Assumes a 16 MHz input clock (clk_i), given as a project constant below
 * rather than read from hardware. TinyMCU has no way to query its own
 * clock frequency. Adjust INPUT_CLOCK_HZ if the actual clock differs.
 */

#include "tinymcu_gpio.h"
#include "tinymcu_timer.h"
#include "tinymcu_csr.h"
#include "tinymcu_trap.h"

#define INPUT_CLOCK_HZ          16000000u
#define LED_BASE_PIN            0u
#define LED_COUNT               4u
#define CLK_TICKS_PER_100MS     (INPUT_CLOCK_HZ / 256u / 10u)

static unsigned int pos = 0u;

void tinymcu_trap_handler(void) {
    tinymcu_timer_irq_clear();
    tinymcu_timer_reset();

    tinymcu_gpio_clear(LED_BASE_PIN + pos);
    pos = (pos + 1u) & (LED_COUNT - 1u);
    tinymcu_gpio_set(LED_BASE_PIN + pos);
}

int main (void) {
    unsigned int pin;

    for (pin = LED_BASE_PIN; pin < LED_BASE_PIN + LED_COUNT; pin++) {
        tinymcu_gpio_set_output(pin);
        tinymcu_gpio_clear(pin);
    }
    tinymcu_gpio_set(LED_BASE_PIN + pos);

    tinymcu_timer_reset();
    tinymcu_timer_set_compare(CLK_TICKS_PER_100MS);
    tinymcu_timer_irq_enable();
    tinymcu_timer_set_clksel(TINYMCU_TIMER_CLKSEL_DIV256);

    tinymcu_csr_set_mie(TINYMCU_MIE_MTIE);
    tinymcu_trap_init();

    while (1) {
    }

    return 0;
}
