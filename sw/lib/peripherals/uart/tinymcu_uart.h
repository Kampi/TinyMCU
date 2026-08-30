/* SPDX-License-Identifier: GPL-3.0-or-later */

/**
 * @file tinymcu_uart.h
 * @brief Driver for TinyMCU's UART peripheral.
 *
 * Matches rtl/peripherals/tinymcu_periph_uart.vhd's register map exactly
 * (that file is the authoritative source; keep this in sync with it by
 * hand, there is no generator for the software side of the memory map).
 *
 * There is no hardware baud-rate divider: BAUDRATE holds the number of
 * clk_i cycles per bit directly (clk_i frequency / desired baud rate),
 * computed by the caller, see tinymcu_uart_init()'s parameter and
 * sim/peripherals/tinymcu_tb_uart.vhd's header for how that value is
 * derived.
 */

#ifndef TINYMCU_UART_H
#define TINYMCU_UART_H

/** Byte address of the UART's register block. */
#define TINYMCU_UART_BASE 0x04000200u

/**
 * @brief UART register block.
 *
 * Layout matches rtl/peripherals/tinymcu_periph_uart.vhd word-for-word.
 */
typedef struct {
    volatile unsigned int CONFIG;     /**< Offset 0x00: data bits / stop bits / parity, see tinymcu_periph_uart.vhd's header. */
    volatile unsigned int BAUDRATE;   /**< Offset 0x04: clk_i cycles per bit. */
    volatile unsigned int STATUS;     /**< Offset 0x08: bits 2:0, see TINYMCU_UART_STATUS_*. */
    volatile unsigned int TX_DATA;    /**< Offset 0x0C: write to start a transmission (only accepted while idle). */
    volatile unsigned int RX_DATA;    /**< Offset 0x10: last successfully received byte; read clears STATUS.RX_READY. */
    volatile unsigned int INT_CONFIG; /**< Offset 0x14: bit 0 = RX_READY interrupt enable, see #TINYMCU_UART_INT_RX_READY. */
    volatile unsigned int INT_STATUS; /**< Offset 0x18: bit 0 = RX_READY interrupt flag; write 0 to clear (see tinymcu_uart_irq_clear()). */
} tinymcu_uart_t;

/** UART register block, overlaid at #TINYMCU_UART_BASE. */
#define TINYMCU_UART ((tinymcu_uart_t *)TINYMCU_UART_BASE)

/** @name STATUS bits. */
/**@{*/
/** A transmission is currently in progress. */
#define TINYMCU_UART_STATUS_TX_ACTIVE    (1u << 0)
/** A received byte is waiting in RX_DATA; reading RX_DATA clears this. */
#define TINYMCU_UART_STATUS_RX_READY     (1u << 1)
/** The last received byte failed its parity check (only meaningful
 *  while/after TINYMCU_UART_STATUS_RX_READY was set for that byte). */
#define TINYMCU_UART_STATUS_PARITY_ERROR (1u << 2)
/**@}*/

/** @name CONFIG bits 1:0: data bits per frame. */
/**@{*/
#define TINYMCU_UART_DATABITS_8 (0x0u << 0)
#define TINYMCU_UART_DATABITS_7 (0x1u << 0)
#define TINYMCU_UART_DATABITS_9 (0x2u << 0)
/**@}*/

/** @name CONFIG bits 3:2: stop bits. */
/**@{*/
#define TINYMCU_UART_STOPBITS_1 (0x0u << 2)
#define TINYMCU_UART_STOPBITS_2 (0x1u << 2)
/**@}*/

/** @name CONFIG bits 5:4: parity. */
/**@{*/
#define TINYMCU_UART_PARITY_NONE (0x0u << 4)
#define TINYMCU_UART_PARITY_EVEN (0x1u << 4)
#define TINYMCU_UART_PARITY_ODD  (0x2u << 4)
/**@}*/

/** CONFIG shortcut: 8 data bits, 1 stop bit, no parity. */
#define TINYMCU_UART_CONFIG_8N1 (TINYMCU_UART_DATABITS_8 | TINYMCU_UART_STOPBITS_1 | TINYMCU_UART_PARITY_NONE)

/**
 * @brief INT_CONFIG/INT_STATUS bit 0: the (only) RX_READY interrupt --
 * used both as the enable bit in INT_CONFIG and the flag bit in
 * INT_STATUS.
 */
#define TINYMCU_UART_INT_RX_READY (1u << 0)

/**
 * @brief Configure the UART's framing and baud rate, and start it ready
 * to transmit.
 * @param clks_per_bit Number of clk_i cycles per UART bit (clk_i
 *                      frequency / desired baud rate, rounded to the
 *                      nearest integer by the caller).
 * @param databits One of the TINYMCU_UART_DATABITS_* values above.
 * @param stopbits One of the TINYMCU_UART_STOPBITS_* values above.
 * @param parity   One of the TINYMCU_UART_PARITY_* values above.
 */
void tinymcu_uart_init(unsigned int clks_per_bit, unsigned int databits,
                        unsigned int stopbits, unsigned int parity);

/**
 * @brief Send a single byte, blocking until any transmission already in
 * progress has finished before starting this one.
 * @param c Byte to send.
 */
void tinymcu_uart_putc(char c);

/**
 * @brief Send a NUL-terminated string, one byte at a time via
 * tinymcu_uart_putc().
 * @param s NUL-terminated string to send.
 */
void tinymcu_uart_puts(const char *s);

/**
 * @brief Check whether a received byte is waiting in RX_DATA.
 * @return Nonzero if STATUS.RX_READY is set (a byte is available and
 *         tinymcu_uart_getc() will not block), zero otherwise.
 */
unsigned int tinymcu_uart_rx_ready(void);

/**
 * @brief Check whether the last received byte failed its parity check.
 *
 * Only meaningful for the byte currently indicated by
 * tinymcu_uart_rx_ready() (or the one just read by tinymcu_uart_getc()):
 * the next received byte overwrites this the moment it arrives, whether
 * or not the previous byte was ever read.
 * @return Nonzero if STATUS.PARITY_ERROR is set.
 */
unsigned int tinymcu_uart_rx_parity_error(void);

/**
 * @brief Receive a single byte, blocking until one is available.
 *
 * Reading RX_DATA is what clears STATUS.RX_READY in hardware (see
 * tinymcu_periph_uart.vhd's Rx process). This call itself acknowledges
 * the byte, so check tinymcu_uart_rx_parity_error() before or
 * immediately after calling this if you need to know whether *this*
 * byte's parity was valid, before a following byte can overwrite it.
 * @return The received byte in the low bits (low 8 for the 7/8-bit
 *         TINYMCU_UART_DATABITS_* modes, low 9 for TINYMCU_UART_DATABITS_9).
 */
unsigned int tinymcu_uart_getc(void);

/**
 * @brief Enable the RX_READY interrupt.
 */
void tinymcu_uart_irq_enable(void);

/**
 * @brief Disable the RX_READY interrupt. Does not clear an already-pending
 * flag (see tinymcu_uart_irq_clear()).
 */
void tinymcu_uart_irq_disable(void);

/**
 * @brief Check whether the RX_READY interrupt flag is currently set.
 * @return Nonzero if INT_STATUS bit 0 is set.
 */
unsigned int tinymcu_uart_irq_pending(void);

/**
 * @brief Clear the RX_READY interrupt flag.
 *
 * The flag is tied to STATUS.RX_READY in hardware (see
 * tinymcu_periph_uart.vhd's "Interrupt flags generation" process): while
 * the received byte hasn't been read yet, this clear doesn't stick; the
 * flag re-fires the very next clock cycle. Call tinymcu_uart_getc() (or
 * read RX_DATA directly) first, then this, to clear it for good.
 */
void tinymcu_uart_irq_clear(void);

#endif /* TINYMCU_UART_H */
