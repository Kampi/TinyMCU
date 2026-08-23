/* SPDX-License-Identifier: GPL-3.0-or-later */

/**
 * @file tinymcu_csr.h
 * @brief Minimal M-mode CSR access (mstatus/mie/mtvec), see rtl/core/tinymcu_cpu_csrfile.vhd for the hardware side.
 */

#ifndef TINYMCU_CSR_H
#define TINYMCU_CSR_H

/** mstatus.MIE: global M-mode interrupt enable (bit 3). */
#define TINYMCU_MSTATUS_MIE (1u << 3)

/** mie/mip bit positions, see rtl/tinymcu_pkg.vhd's IRQ_M*_BIT constants. */
#define TINYMCU_MIE_MSIE (1u << 3)  /**< Software interrupt enable. */
#define TINYMCU_MIE_MTIE (1u << 7)  /**< Timer interrupt enable. */
#define TINYMCU_MIE_MEIE (1u << 11) /**< External interrupt enable. */

/**
 * @brief Install a trap handler's address into mtvec (Direct mode, the
 * only mode tinymcu_cpu.vhd implements: see README.md "Interrupts".
 * @param addr Address of the trap entry point (see tinymcu_trap.S's
 *             trap_entry); must be 4-byte aligned.
 */
static inline void tinymcu_csr_write_mtvec(unsigned int addr) {
    __asm__ volatile ("csrw mtvec, %0" :: "r"(addr));
}

/**
 * @brief Set one or more bits in mie (enable specific interrupt sources),
 * leaving all other bits untouched.
 * @param mask Bitmask of TINYMCU_MIE_* bits to set.
 */
static inline void tinymcu_csr_set_mie(unsigned int mask) {
    __asm__ volatile ("csrs mie, %0" :: "r"(mask));
}

/**
 * @brief Clear one or more bits in mie (disable specific interrupt
 * sources), leaving all other bits untouched.
 * @param mask Bitmask of TINYMCU_MIE_* bits to clear.
 */
static inline void tinymcu_csr_clear_mie(unsigned int mask) {
    __asm__ volatile ("csrc mie, %0" :: "r"(mask));
}

/**
 * @brief Set mstatus.MIE, globally enabling M-mode interrupts. Has no
 * effect on its own unless the relevant mie bit is also set (see
 * tinymcu_csr_set_mie()).
 */
static inline void tinymcu_enable_global_interrupts(void) {
    __asm__ volatile ("csrs mstatus, %0" :: "r"(TINYMCU_MSTATUS_MIE));
}

/**
 * @brief Clear mstatus.MIE, globally disabling M-mode interrupts.
 */
static inline void tinymcu_disable_global_interrupts(void) {
    __asm__ volatile ("csrc mstatus, %0" :: "r"(TINYMCU_MSTATUS_MIE));
}

#endif /* TINYMCU_CSR_H */
