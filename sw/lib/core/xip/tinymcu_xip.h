/* SPDX-License-Identifier: GPL-3.0-or-later */

/**
 * @file tinymcu_xip.h
 * @brief Driver for TinyMCU's XIP (execute-in-place) SPI flash controller.
 *
 * Matches rtl/core/tinymcu_imem_xip.vhd's register map exactly (that file
 * is the authoritative source; keep this in sync with it by hand, there
 * is no generator for the software side of the memory map).
 *
 * The controller has two mutually exclusive engines, switched by
 * CONFIG's ENABLE bit and never both active at once:
 *  - ENABLE=1: the XIP fetch engine. Once enabled, the CPU can execute
 *    code directly out of an external SPI NOR flash mapped at
 *    XIP_FLASH_BASE..XIP_FLASH_END (see tinymcu_pkg.vhd). There is no
 *    further software interaction with this engine after enabling it;
 *    the hardware issues one 0x03 (READ) command per cache miss on its
 *    own. This driver's job is just getting the clock mode/divider and
 *    ENABLE bit configured correctly before the CPU ever jumps into
 *    that window.
 *  - ENABLE=0: the write engine, a generic byte-at-a-time SPI master
 *    for whatever setup the flash needs before XIP can be turned on
 *    (Write Enable, Page Program, etc; this controller doesn't know
 *    or care about SPI NOR opcodes, it just shifts bytes). Software
 *    holds CS_ASSERT for the whole multi-byte command, sending each
 *    byte through tinymcu_xip_transfer_byte().
 *
 * Both engines share CPHA/CPOL/LSB_FIRST/CLKDIV; set those once via
 * tinymcu_xip_configure() before touching either ENABLE or CS_ASSERT.
 * Switching ENABLE while the CPU is executing out of the flash window
 * would cut off the instruction stream it's currently running from, so
 * only ever call tinymcu_xip_fetch_enable()/tinymcu_xip_fetch_disable()
 * while running from Boot ROM or RAM, never from flash itself.
 */

#ifndef TINYMCU_XIP_H
#define TINYMCU_XIP_H

/** Byte address of the XIP controller's own register block (CONFIG/STATUS/TX_DATA/RX_DATA). */
#define TINYMCU_XIP_BASE 0x04000300u

/**
 * @brief XIP controller register block.
 *
 * Layout matches rtl/core/tinymcu_imem_xip.vhd word-for-word.
 */
typedef struct {
    volatile unsigned int CONFIG;  /**< Offset 0x00: clock mode, ENABLE, CS_ASSERT, see TINYMCU_XIP_CONFIG_*. */
    volatile unsigned int STATUS;  /**< Offset 0x04: bit 0, see #TINYMCU_XIP_STATUS_BUSY. */
    volatile unsigned int TX_DATA; /**< Offset 0x08: write engine only. Write to start one 8-bit transfer. */
    volatile unsigned int RX_DATA; /**< Offset 0x0C: write engine only. Byte shifted in during the most recent transfer. */
} tinymcu_xip_t;

/** XIP controller register block, overlaid at #TINYMCU_XIP_BASE. */
#define TINYMCU_XIP ((tinymcu_xip_t *)TINYMCU_XIP_BASE)

/** @name CONFIG bits. */
/**@{*/
#define TINYMCU_XIP_CONFIG_CPHA            (1u << 0)
#define TINYMCU_XIP_CONFIG_CPOL            (1u << 1)
/** 1 = fetch engine active (XIP), 0 = write engine active. */
#define TINYMCU_XIP_CONFIG_ENABLE          (1u << 2)
#define TINYMCU_XIP_CONFIG_LSB_FIRST       (1u << 3)
#define TINYMCU_XIP_CONFIG_CLKDIV_SHIFT    4
#define TINYMCU_XIP_CONFIG_CLKDIV_MASK     (0xFFu << TINYMCU_XIP_CONFIG_CLKDIV_SHIFT)
/** Write engine only: hold across a multi-byte command's TX_DATA writes. */
#define TINYMCU_XIP_CONFIG_CS_ASSERT       (1u << 12)
/**@}*/

/** STATUS bit 0: either engine's SPI transaction is currently in progress. */
#define TINYMCU_XIP_STATUS_BUSY (1u << 0)

/**
 * @brief Set the SPI clock mode and divider shared by both engines.
 *
 * Leaves ENABLE and CS_ASSERT untouched; call this before
 * tinymcu_xip_fetch_enable() or the first tinymcu_xip_cs_assert(),
 * not while either engine is mid-transfer.
 * @param cpol      Nonzero for CPOL=1 (SCLK idles high).
 * @param cpha      Nonzero for CPHA=1 (sample on the trailing edge).
 * @param lsb_first Nonzero to shift LSB first instead of MSB first.
 * @param clkdiv    SCLK toggles every (clkdiv + 1) clk_i cycles (0-255).
 */
void tinymcu_xip_configure(unsigned int cpol, unsigned int cpha,
                            unsigned int lsb_first, unsigned int clkdiv);

/**
 * @brief Check whether either engine's SPI transaction is currently in
 * progress.
 * @return Nonzero if STATUS.BUSY is set.
 */
unsigned int tinymcu_xip_busy(void);

/**
 * @brief Enable the XIP fetch engine (CONFIG.ENABLE=1), disabling the
 * write engine.
 *
 * Only call this while executing from Boot ROM or RAM: once enabled,
 * jumping into XIP_FLASH_BASE..XIP_FLASH_END (tinymcu_pkg.vhd) starts
 * fetching instructions from the external flash automatically; there
 * is nothing further to do in software.
 */
void tinymcu_xip_fetch_enable(void);

/**
 * @brief Disable the XIP fetch engine (CONFIG.ENABLE=0), enabling the
 * write engine so tinymcu_xip_cs_assert()/tinymcu_xip_transfer_byte()
 * can be used to talk to the flash directly.
 *
 * Never call this while the CPU is executing out of the flash window;
 * it cuts off the instruction stream currently being fetched from
 * there.
 */
void tinymcu_xip_fetch_disable(void);

/**
 * @brief Assert chip-select (write engine only), starting a multi-byte
 * command session.
 *
 * Call this before the first tinymcu_xip_transfer_byte() of a command;
 * ss_n_o stays low across every transfer_byte() call until
 * tinymcu_xip_cs_release().
 */
void tinymcu_xip_cs_assert(void);

/**
 * @brief Release chip-select (write engine only), ending the current
 * command session.
 */
void tinymcu_xip_cs_release(void);

/**
 * @brief Shift one byte out over MOSI and return whatever came back on
 * MISO during that same transfer (write engine only).
 *
 * Blocks until the transfer completes. tinymcu_xip_cs_assert() must
 * already have been called; a transfer attempted while CS_ASSERT is
 * clear is silently ignored by the hardware (see
 * rtl/core/tinymcu_imem_xip.vhd's CONFIG bit 12 comment).
 * @param tx_byte Byte to send, MSB- or LSB-first per tinymcu_xip_configure().
 * @return The byte simultaneously shifted in over MISO.
 */
unsigned int tinymcu_xip_transfer_byte(unsigned int tx_byte);

#endif /* TINYMCU_XIP_H */
