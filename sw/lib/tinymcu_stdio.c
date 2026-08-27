/* SPDX-License-Identifier: GPL-3.0-or-later */

/**
 * @file tinymcu_stdio.c
 * @brief Picolibc stdout hookup: routes printf()/puts()/putchar() etc. to
 *        tinymcu_uart_putc(). Requires tinymcu_uart_init() to have been
 *        called first (not done here -- same convention as tinymcu_uart.c
 *        itself).
 *
 *        Unlike newlib, picolibc doesn't need a full set of POSIX syscall
 *        stubs (_write/_sbrk/_read/...); a single FILE stream is enough
 *        for unbuffered character output. See README.md's "Required
 *        tools" and sw/printf_demo/Makefile's PICOLIBC_FLAGS for how this
 *        gets linked in.
 */

#include <stdio.h>

#include "tinymcu_uart.h"

static int uart_putc(char c, FILE *file) {
    (void)file;
    tinymcu_uart_putc(c);
    return 0;
}

static FILE __stdout = FDEV_SETUP_STREAM(uart_putc, NULL, NULL, _FDEV_SETUP_WRITE);
FILE *const stdout = &__stdout;
