/* SPDX-License-Identifier: GPL-3.0-or-later */

/**
 * @file tinymcu_trap.h
 * @brief M-mode trap setup and dispatch, see tinymcu_trap.S for the
 * assembly entry stub this installs.
 */

#ifndef TINYMCU_TRAP_H
#define TINYMCU_TRAP_H

/**
 * @brief Install trap_entry (see tinymcu_trap.S) as mtvec and globally
 * enable M-mode interrupts (mstatus.MIE).
 *
 * Call once during startup, after enabling whichever mie bits/peripheral
 * interrupts are actually wanted (see tinymcu_csr.h and each
 * peripheral's INT_CONFIG-style register).
 */
void tinymcu_trap_init(void);

/**
 * @brief Trap dispatch entry point, called from trap_entry (see
 * tinymcu_trap.S) with every caller-saved register already preserved.
 *
 * Weak by default
 */
void tinymcu_trap_handler(void);

#endif /* TINYMCU_TRAP_H */
