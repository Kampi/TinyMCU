/* SPDX-License-Identifier: GPL-3.0-or-later */

/**
 * @file tinymcu_csr.h
 * @brief Minimal M-mode CSR access (mstatus/mie/mtvec/mcause/mepc), see
 * rtl/core/tinymcu_cpu_csrfile.vhd for the hardware side.
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
 * @brief mcause bit 31: set for every trap TinyMCU can raise.
 *
 * tinymcu_cpu.vhd's is_trap only ever fires for a pending, enabled
 * interrupt (see its own comment); there is no exception support
 * (illegal instruction, ECALL/EBREAK, misaligned access, ...), so this
 * bit is always set in practice and the low bits below are always one
 * of TINYMCU_MCAUSE_MSI/MTI/MEI, never a WLRL exception code.
 */
#define TINYMCU_MCAUSE_INTERRUPT (1u << 31)

/**
 * @brief mcause's low bits when TINYMCU_MCAUSE_INTERRUPT is set.
 *
 * Numerically identical to the matching TINYMCU_MIE_* bit position
 * (tinymcu_cpu_csrfile.vhd derives mcause straight from
 * rtl/tinymcu_pkg.vhd's IRQ_M*_BIT), but this is a plain code number
 * here, not a shifted mie mask, so keep the two separate.
 */
#define TINYMCU_MCAUSE_MSI 3  /**< Machine software interrupt. */
#define TINYMCU_MCAUSE_MTI 7  /**< Machine timer interrupt. */
#define TINYMCU_MCAUSE_MEI 11 /**< Machine external interrupt. */

/**
 * @brief Install a trap handler's address into mtvec.
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

/**
 * @brief Read mcause: which trap this is, see TINYMCU_MCAUSE_*.
 *
 * Normally only needed from inside tinymcu_trap_handler(), which
 * already gets this passed in as its mcause parameter; call this
 * directly only if reading it somewhere else.
 * @return The current mcause value.
 */
static inline unsigned int tinymcu_csr_read_mcause(void) {
    unsigned int v;
    __asm__ volatile ("csrr %0, mcause" : "=r"(v));
    return v;
}

/**
 * @brief Read mepc: the instruction address execution resumes at on
 * mret (the address it was interrupted at, since TinyMCU has no
 * exceptions to advance past, see TINYMCU_MCAUSE_INTERRUPT).
 *
 * Normally only needed from inside tinymcu_trap_handler(), which
 * already gets this passed in as its mepc parameter; call this
 * directly only if reading it somewhere else.
 * @return The current mepc value.
 */
static inline unsigned int tinymcu_csr_read_mepc(void) {
    unsigned int v;
    __asm__ volatile ("csrr %0, mepc" : "=r"(v));
    return v;
}

#endif /* TINYMCU_CSR_H */
