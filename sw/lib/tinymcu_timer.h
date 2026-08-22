/* SPDX-License-Identifier: GPL-3.0-or-later */

/**
 * @file tinymcu_timer.h
 * @brief Driver for TinyMCU's Timer peripheral.
 *
 * Matches rtl/peripherals/tinymcu_periph_timer.vhd's register map exactly
 * (that file is the authoritative source; keep this in sync with it by
 * hand, there is no generator for the software side of the memory map).
 *
 * RV32I only (see README.md "Extensions"): every function here uses only
 * shifts/bitwise ops, never `*`/`/`/`%`, so nothing here needs libgcc.
 *
 * The compare interrupt (see tinymcu_timer_irq_enable()) is edge-
 * triggered on COUNTER == COMPARE: it fires once per crossing, not
 * continuously, and does not auto-reset COUNTER on its own -- reset it
 * yourself (see tinymcu_timer_reset()) in the ISR if you want the match
 * to happen again after another full period, same as when polling
 * COUNTER directly.
 */

#ifndef TINYMCU_TIMER_H
#define TINYMCU_TIMER_H

/** Byte address of the Timer's register block. */
#define TINYMCU_TIMER_BASE 0x04000100u

/**
 * @brief Timer register block.
 *
 * Layout matches rtl/peripherals/tinymcu_periph_timer.vhd word-for-word.
 */
typedef struct {
    volatile unsigned int CONFIG;     /**< Offset 0x00: bits 3:0 = CLKSEL, see TINYMCU_TIMER_CLKSEL_*. */
    volatile unsigned int INT_CONFIG; /**< Offset 0x04: bit 0 = compare interrupt enable. */
    volatile unsigned int INT_STATUS; /**< Offset 0x08: bit 0 = compare interrupt flag, write 0 to clear. */
    volatile unsigned int COUNTER;    /**< Offset 0x0C: free-running counter, ticks at the CLKSEL rate. */
    volatile unsigned int COMPARE;    /**< Offset 0x10: compare target for the compare interrupt. */
} tinymcu_timer_t;

/** Timer register block, overlaid at #TINYMCU_TIMER_BASE. */
#define TINYMCU_TIMER ((tinymcu_timer_t *)TINYMCU_TIMER_BASE)

/** @name CONFIG.CLKSEL values (binary-encoded, not one-hot). */
/**@{*/
#define TINYMCU_TIMER_CLKSEL_OFF     0x0u /**< COUNTER does not tick. */
#define TINYMCU_TIMER_CLKSEL_DIV1    0x1u /**< COUNTER ticks every clk_i cycle. */
#define TINYMCU_TIMER_CLKSEL_DIV2    0x2u /**< COUNTER ticks every clk_i/2 cycles. */
#define TINYMCU_TIMER_CLKSEL_DIV4    0x3u /**< COUNTER ticks every clk_i/4 cycles. */
#define TINYMCU_TIMER_CLKSEL_DIV8    0x4u /**< COUNTER ticks every clk_i/8 cycles. */
#define TINYMCU_TIMER_CLKSEL_DIV64   0x5u /**< COUNTER ticks every clk_i/64 cycles. */
#define TINYMCU_TIMER_CLKSEL_DIV256  0x6u /**< COUNTER ticks every clk_i/256 cycles. */
#define TINYMCU_TIMER_CLKSEL_DIV1024 0x7u /**< COUNTER ticks every clk_i/1024 cycles. */
/**@}*/

/** INT_CONFIG/INT_STATUS bit 0: compare interrupt (enable/flag). */
#define TINYMCU_TIMER_INT_COMPARE (1u << 0)

/**
 * @brief Select COUNTER's clock source/prescaler and start it ticking.
 * @param clksel One of the TINYMCU_TIMER_CLKSEL_* values above.
 */
void tinymcu_timer_set_clksel(unsigned int clksel);

/**
 * @brief Read the free-running counter's current value.
 * @return The COUNTER register's value.
 */
unsigned int tinymcu_timer_read(void);

/**
 * @brief Reset the free-running counter back to 0.
 *
 * Does not affect CONFIG; ticking continues at whatever rate was already
 * selected.
 */
void tinymcu_timer_reset(void);

/**
 * @brief Set the compare target that the compare interrupt (see
 * tinymcu_timer_irq_enable()) fires on.
 * @param value COUNTER value to compare against.
 */
void tinymcu_timer_set_compare(unsigned int value);

/**
 * @brief Enable the compare interrupt (INT_CONFIG bit 0): irq_o goes
 * high the moment COUNTER first equals COMPARE, and mip.MTIP with it
 * (see rtl/core/tinymcu_cpu.vhd). Has no effect on its own without also
 * enabling mie.MTIE and mstatus.MIE (see tinymcu_csr.h/tinymcu_trap.h).
 */
void tinymcu_timer_irq_enable(void);

/**
 * @brief Disable the compare interrupt (INT_CONFIG bit 0). Does not
 * clear an already-pending flag (see tinymcu_timer_irq_clear()).
 */
void tinymcu_timer_irq_disable(void);

/**
 * @brief Check whether the compare interrupt flag is currently set.
 * @return Nonzero if INT_STATUS bit 0 is set (compare match occurred and
 *         has not been cleared yet), zero otherwise.
 */
unsigned int tinymcu_timer_irq_pending(void);

/**
 * @brief Clear the compare interrupt flag (write 0 to INT_STATUS). Must
 * be called from the ISR before returning (MRET), or the interrupt
 * immediately re-fires the moment mstatus.MIE is restored.
 */
void tinymcu_timer_irq_clear(void);

#endif /* TINYMCU_TIMER_H */
