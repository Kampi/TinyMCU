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

void tinymcu_gpio_irq_global_enable(void) {
    TINYMCU_GPIO->CONFIG |= TINYMCU_GPIO_CONFIG_GLOBAL_INT_EN;
}

void tinymcu_gpio_irq_global_disable(void) {
    TINYMCU_GPIO->CONFIG &= ~TINYMCU_GPIO_CONFIG_GLOBAL_INT_EN;
}

void tinymcu_gpio_irq_enable(unsigned int pin) {
    TINYMCU_GPIO->INT_CONFIG |= (1u << pin);
}

void tinymcu_gpio_irq_disable(unsigned int pin) {
    TINYMCU_GPIO->INT_CONFIG &= ~(1u << pin);
}

unsigned int tinymcu_gpio_irq_pending(unsigned int pin) {
    return (TINYMCU_GPIO->INT_STATUS >> pin) & 1u;
}

unsigned int tinymcu_gpio_irq_status(void) {
    return TINYMCU_GPIO->INT_STATUS;
}

void tinymcu_gpio_irq_clear(unsigned int pin) {
    TINYMCU_GPIO->INT_STATUS &= ~(1u << pin);
}

void tinymcu_gpio_irq_clear_all(void) {
    TINYMCU_GPIO->INT_STATUS = 0;
}

void tinymcu_gpio_debounce_set(unsigned int cycles) {
    TINYMCU_GPIO->CONFIG = (TINYMCU_GPIO->CONFIG & ~TINYMCU_GPIO_CONFIG_DEBOUNCE_MASK)
                          | ((cycles << TINYMCU_GPIO_CONFIG_DEBOUNCE_LSB) & TINYMCU_GPIO_CONFIG_DEBOUNCE_MASK);
}

void tinymcu_gpio_debounce_disable(void) {
    tinymcu_gpio_debounce_set(0);
}
