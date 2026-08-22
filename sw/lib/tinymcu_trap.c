/* SPDX-License-Identifier: GPL-3.0-or-later */

/**
 * @file tinymcu_trap.c
 * @brief Implementation of TinyMCU's trap setup, see tinymcu_trap.h.
 */

#include "tinymcu_csr.h"
#include "tinymcu_trap.h"

/** Defined in tinymcu_trap.S. */
extern void trap_entry(void);

void tinymcu_trap_init(void) {
    tinymcu_csr_write_mtvec((unsigned int)&trap_entry);
    tinymcu_enable_global_interrupts();
}

void __attribute__((weak)) tinymcu_trap_handler(void) {
    /* No interrupt source enabled by default; override this. */
}
