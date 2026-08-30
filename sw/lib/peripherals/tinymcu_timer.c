/* SPDX-License-Identifier: GPL-3.0-or-later */

/**
 * @file tinymcu_timer.c
 * @brief Implementation of the TinyMCU Timer driver, see tinymcu_timer.h.
 */

#include "tinymcu_timer.h"

void tinymcu_timer_set_clksel(unsigned int clksel) {
    TINYMCU_TIMER->CONFIG = clksel;
}

unsigned int tinymcu_timer_read(void) {
    return TINYMCU_TIMER->COUNTER;
}

void tinymcu_timer_reset(void) {
    TINYMCU_TIMER->COUNTER = 0;
}

void tinymcu_timer_set_compare(unsigned int value) {
    TINYMCU_TIMER->COMPARE = value;
}

void tinymcu_timer_irq_enable(void) {
    TINYMCU_TIMER->INT_CONFIG = TINYMCU_TIMER_INT_COMPARE;
}

void tinymcu_timer_irq_disable(void) {
    TINYMCU_TIMER->INT_CONFIG = 0;
}

unsigned int tinymcu_timer_irq_pending(void) {
    return TINYMCU_TIMER->INT_STATUS & TINYMCU_TIMER_INT_COMPARE;
}

void tinymcu_timer_irq_clear(void) {
    TINYMCU_TIMER->INT_STATUS = 0;
}
