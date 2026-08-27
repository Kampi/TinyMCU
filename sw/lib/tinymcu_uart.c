/* SPDX-License-Identifier: GPL-3.0-or-later */

/**
 * @file tinymcu_uart.c
 * @brief Implementation of the TinyMCU UART driver, see tinymcu_uart.h.
 */

#include "tinymcu_uart.h"

void tinymcu_uart_init(unsigned int clks_per_bit, unsigned int databits,
                        unsigned int stopbits, unsigned int parity) {
    TINYMCU_UART->CONFIG = databits | stopbits | parity;
    TINYMCU_UART->BAUDRATE = clks_per_bit;
}

void tinymcu_uart_putc(char c) {
    while (TINYMCU_UART->STATUS & TINYMCU_UART_STATUS_TX_ACTIVE) {
    }
    TINYMCU_UART->TX_DATA = (unsigned char)c;
}

void tinymcu_uart_puts(const char *s) {
    while (*s != '\0') {
        tinymcu_uart_putc(*s);
        s++;
    }
}

unsigned int tinymcu_uart_rx_ready(void) {
    return TINYMCU_UART->STATUS & TINYMCU_UART_STATUS_RX_READY;
}

unsigned int tinymcu_uart_rx_parity_error(void) {
    return TINYMCU_UART->STATUS & TINYMCU_UART_STATUS_PARITY_ERROR;
}

unsigned int tinymcu_uart_getc(void) {
    while (!tinymcu_uart_rx_ready()) {
    }
    return TINYMCU_UART->RX_DATA;
}

void tinymcu_uart_irq_enable(void) {
    TINYMCU_UART->INT_CONFIG |= TINYMCU_UART_INT_RX_READY;
}

void tinymcu_uart_irq_disable(void) {
    TINYMCU_UART->INT_CONFIG &= ~TINYMCU_UART_INT_RX_READY;
}

unsigned int tinymcu_uart_irq_pending(void) {
    return TINYMCU_UART->INT_STATUS & TINYMCU_UART_INT_RX_READY;
}

void tinymcu_uart_irq_clear(void) {
    TINYMCU_UART->INT_STATUS &= ~TINYMCU_UART_INT_RX_READY;
}
