/* SPDX-License-Identifier: GPL-3.0-or-later */

/**
 * @file tinymcu_gpio.h
 * @brief Driver for TinyMCU's GPIO peripheral.
 *
 * Matches rtl/tinymcu_periph_gpio.vhd's register map exactly (that file
 * is the authoritative source; keep this in sync with it by hand, there
 * is no generator for the software side of the memory map). One 32-bit
 * GPIO port, pin @p i controlled bit-for-bit by the same bit position in
 * every register below.
 *
 * RV32I only (see README.md "Extensions"): every function here uses
 * only shifts/bitwise ops (SLL/SRL, native RV32I instructions), never
 * `*`/`/`/`%`, so nothing here needs libgcc.
 */

#ifndef TINYMCU_GPIO_H
#define TINYMCU_GPIO_H

/** Byte address of the GPIO controller's register block. */
#define TINYMCU_GPIO_BASE 0x04000000u

/**
 * @brief GPIO register block, one bit per pin in every field.
 *
 * Layout matches rtl/tinymcu_periph_gpio.vhd word-for-word: field order
 * below is field offset order (CONFIG at 0x00, DDR at 0x04, ...), no
 * padding, so this overlays the hardware directly.
 */
typedef struct {
    volatile unsigned int CONFIG;   /**< Offset 0x00: general-purpose, no defined bits yet. */
    volatile unsigned int DDR;      /**< Offset 0x04: data direction, 1 = output, 0 = input. */
    volatile unsigned int PULL_SEL; /**< Offset 0x08: pull select, 1 = pull-up, 0 = pull-down. */
    volatile unsigned int PULL_EN;  /**< Offset 0x0C: pull enable, 1 = pull active. */
    volatile unsigned int OUT;      /**< Offset 0x10: output level, drives DDR = 1 pins only. */
    volatile unsigned int IN;       /**< Offset 0x14: read-only, actual level of every pin. */
} tinymcu_gpio_t;

/** GPIO register block, overlaid at #TINYMCU_GPIO_BASE. */
#define TINYMCU_GPIO ((tinymcu_gpio_t *)TINYMCU_GPIO_BASE)

/**
 * @brief Configure a pin as an output.
 * @param pin Pin number, 0-31.
 */
void tinymcu_gpio_set_output(unsigned int pin);

/**
 * @brief Configure a pin as an input.
 * @param pin Pin number, 0-31.
 */
void tinymcu_gpio_set_input(unsigned int pin);

/**
 * @brief Enable a pin's pull-up resistor.
 * @param pin Pin number, 0-31. Only meaningful while the pin is an input.
 */
void tinymcu_gpio_pull_up(unsigned int pin);

/**
 * @brief Enable a pin's pull-down resistor.
 * @param pin Pin number, 0-31. Only meaningful while the pin is an input.
 */
void tinymcu_gpio_pull_down(unsigned int pin);

/**
 * @brief Disable a pin's pull resistor (leave it floating).
 * @param pin Pin number, 0-31.
 */
void tinymcu_gpio_pull_disable(unsigned int pin);

/**
 * @brief Drive a pin high.
 * @param pin Pin number, 0-31. Has no effect unless configured as an output.
 */
void tinymcu_gpio_set(unsigned int pin);

/**
 * @brief Drive a pin low.
 * @param pin Pin number, 0-31. Has no effect unless configured as an output.
 */
void tinymcu_gpio_clear(unsigned int pin);

/**
 * @brief Invert a pin's current output level.
 * @param pin Pin number, 0-31. Has no effect unless configured as an output.
 */
void tinymcu_gpio_toggle(unsigned int pin);

/**
 * @brief Drive a pin to a specific level.
 * @param pin   Pin number, 0-31.
 * @param level Non-zero to drive high, zero to drive low.
 */
void tinymcu_gpio_write(unsigned int pin, unsigned int level);

/**
 * @brief Read a single pin's actual level.
 * @param pin Pin number, 0-31.
 * @return 1 if the pin is currently high, 0 if low.
 *
 * Reads IN, not OUT: reflects the pin's actual level regardless of
 * direction (see rtl/tinymcu_periph_gpio.vhd's header).
 */
unsigned int tinymcu_gpio_get(unsigned int pin);

/**
 * @brief Read every pin's actual level at once.
 * @return The 32-bit input register, bit i = pin i's level.
 */
unsigned int tinymcu_gpio_read_port(void);

#endif /* TINYMCU_GPIO_H */
