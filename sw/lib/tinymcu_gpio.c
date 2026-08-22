/* SPDX-License-Identifier: GPL-3.0-or-later */

/**
 * @file tinymcu_gpio.c
 * @brief Implementation of the TinyMCU GPIO driver, see tinymcu_gpio.h.
 */

#include "tinymcu_gpio.h"

void tinymcu_gpio_set_output(unsigned int pin) {
    TINYMCU_GPIO->DDR |= (1u << pin);
}

void tinymcu_gpio_set_input(unsigned int pin) {
    TINYMCU_GPIO->DDR &= ~(1u << pin);
}

void tinymcu_gpio_pull_up(unsigned int pin) {
    TINYMCU_GPIO->PULL_SEL |= (1u << pin);
    TINYMCU_GPIO->PULL_EN |= (1u << pin);
}

void tinymcu_gpio_pull_down(unsigned int pin) {
    TINYMCU_GPIO->PULL_SEL &= ~(1u << pin);
    TINYMCU_GPIO->PULL_EN |= (1u << pin);
}

void tinymcu_gpio_pull_disable(unsigned int pin) {
    TINYMCU_GPIO->PULL_EN &= ~(1u << pin);
}

void tinymcu_gpio_set(unsigned int pin) {
    TINYMCU_GPIO->OUT |= (1u << pin);
}

void tinymcu_gpio_clear(unsigned int pin) {
    TINYMCU_GPIO->OUT &= ~(1u << pin);
}

void tinymcu_gpio_toggle(unsigned int pin) {
    TINYMCU_GPIO->OUT ^= (1u << pin);
}

void tinymcu_gpio_write(unsigned int pin, unsigned int level) {
    if (level) {
        tinymcu_gpio_set(pin);
    } else {
        tinymcu_gpio_clear(pin);
    }
}

unsigned int tinymcu_gpio_get(unsigned int pin) {
    return (TINYMCU_GPIO->IN >> pin) & 1u;
}

unsigned int tinymcu_gpio_read_port(void) {
    return TINYMCU_GPIO->IN;
}
