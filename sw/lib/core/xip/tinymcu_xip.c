/* SPDX-License-Identifier: GPL-3.0-or-later */

/**
 * @file tinymcu_xip.c
 * @brief Implementation of the TinyMCU XIP driver, see tinymcu_xip.h.
 */

#include "tinymcu_xip.h"

void tinymcu_xip_configure(unsigned int cpol, unsigned int cpha,
                            unsigned int lsb_first, unsigned int clkdiv) {
    unsigned int cfg = TINYMCU_XIP->CONFIG;

    cfg &= ~(TINYMCU_XIP_CONFIG_CPOL | TINYMCU_XIP_CONFIG_CPHA |
             TINYMCU_XIP_CONFIG_LSB_FIRST | TINYMCU_XIP_CONFIG_CLKDIV_MASK);

    if (cpol) {
        cfg |= TINYMCU_XIP_CONFIG_CPOL;
    }
    if (cpha) {
        cfg |= TINYMCU_XIP_CONFIG_CPHA;
    }
    if (lsb_first) {
        cfg |= TINYMCU_XIP_CONFIG_LSB_FIRST;
    }
    cfg |= (clkdiv << TINYMCU_XIP_CONFIG_CLKDIV_SHIFT) & TINYMCU_XIP_CONFIG_CLKDIV_MASK;

    TINYMCU_XIP->CONFIG = cfg;
}

unsigned int tinymcu_xip_busy(void) {
    return TINYMCU_XIP->STATUS & TINYMCU_XIP_STATUS_BUSY;
}

void tinymcu_xip_fetch_enable(void) {
    TINYMCU_XIP->CONFIG |= TINYMCU_XIP_CONFIG_ENABLE;
}

void tinymcu_xip_fetch_disable(void) {
    TINYMCU_XIP->CONFIG &= ~TINYMCU_XIP_CONFIG_ENABLE;
}

void tinymcu_xip_cs_assert(void) {
    TINYMCU_XIP->CONFIG |= TINYMCU_XIP_CONFIG_CS_ASSERT;
}

void tinymcu_xip_cs_release(void) {
    TINYMCU_XIP->CONFIG &= ~TINYMCU_XIP_CONFIG_CS_ASSERT;
}

unsigned int tinymcu_xip_transfer_byte(unsigned int tx_byte) {
    TINYMCU_XIP->TX_DATA = tx_byte & 0xFFu;
    while (tinymcu_xip_busy()) {
    }
    return TINYMCU_XIP->RX_DATA;
}
