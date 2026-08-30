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
 * Weak by default; override this to actually handle anything. mcause
 * and mepc are read once in trap_entry, before any other CSR access
 * can disturb them, and passed in here directly rather than requiring
 * the handler to call tinymcu_csr_read_mcause()/tinymcu_csr_read_mepc()
 * itself.
 * @param mcause Value of mcause at trap entry, see TINYMCU_MCAUSE_* in
 *               tinymcu_csr.h.
 * @param mepc   Value of mepc at trap entry: the address execution was
 *               interrupted at (and resumes at on mret).
 */
void tinymcu_trap_handler(unsigned int mcause, unsigned int mepc);

#endif /* TINYMCU_TRAP_H */
