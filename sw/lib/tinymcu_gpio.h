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
 */

#ifndef TINYMCU_GPIO_H
#define TINYMCU_GPIO_H

/** Byte address of the GPIO controller's register block. */
#define TINYMCU_GPIO_BASE 0x04000000u

/**
 * @brief GPIO register block, one bit per pin in every field (except
 * CONFIG, see #TINYMCU_GPIO_CONFIG_GLOBAL_INT_EN).
 *
 * Layout matches rtl/tinymcu_periph_gpio.vhd word-for-word: field order
 * below is field offset order (CONFIG at 0x00, DDR at 0x04, ...), no
 * padding, so this overlays the hardware directly.
 */
typedef struct {
    volatile unsigned int CONFIG;     /**< Offset 0x00: bit 0 = global interrupt enable (#TINYMCU_GPIO_CONFIG_GLOBAL_INT_EN), bits 15:1 = debounce threshold (#TINYMCU_GPIO_CONFIG_DEBOUNCE_MASK); otherwise general-purpose. */
    volatile unsigned int DDR;        /**< Offset 0x04: data direction, 1 = output, 0 = input. */
    volatile unsigned int PULL_SEL;   /**< Offset 0x08: pull select, 1 = pull-up, 0 = pull-down. */
    volatile unsigned int PULL_EN;    /**< Offset 0x0C: pull enable, 1 = pull active. */
    volatile unsigned int OUT;        /**< Offset 0x10: output level, drives DDR = 1 pins only. */
    volatile unsigned int IN;         /**< Offset 0x14: read-only, actual level of every pin. */
    volatile unsigned int INT_CONFIG; /**< Offset 0x18: per-pin interrupt enable, 1 = enabled. */
    volatile unsigned int INT_STATUS; /**< Offset 0x1C: per-pin sticky interrupt flag; write 0 to a bit to clear it. */
} tinymcu_gpio_t;

/** GPIO register block, overlaid at #TINYMCU_GPIO_BASE. */
#define TINYMCU_GPIO ((tinymcu_gpio_t *)TINYMCU_GPIO_BASE)

/**
 * @brief CONFIG bit 0: master interrupt enable, gates every pin's own
 * #tinymcu_gpio_irq_enable regardless of its INT_CONFIG bit. CONFIG is
 * otherwise general-purpose (see rtl/tinymcu_periph_gpio.vhd's header),
 * so only ever touch this one bit with |=/&=, never assign CONFIG
 * outright.
 */
#define TINYMCU_GPIO_CONFIG_GLOBAL_INT_EN (1u << 0)

/**
 * @brief CONFIG bits 15:1: debounce threshold field, in clock cycles (0
 * = disabled). Position/width match tinymcu_periph_gpio.vhd's
 * DEBOUNCE_WIDTH generic default (15) -- if that generic is ever
 * overridden at synthesis time, these three must be updated to match.
 */
#define TINYMCU_GPIO_CONFIG_DEBOUNCE_LSB   1u
#define TINYMCU_GPIO_CONFIG_DEBOUNCE_WIDTH 15u
#define TINYMCU_GPIO_CONFIG_DEBOUNCE_MASK \
    (((1u << TINYMCU_GPIO_CONFIG_DEBOUNCE_WIDTH) - 1u) << TINYMCU_GPIO_CONFIG_DEBOUNCE_LSB)

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

/**
 * @brief Set CONFIG's master interrupt enable. Has no effect on its own
 * unless the relevant pin is also enabled (see tinymcu_gpio_irq_enable()).
 */
void tinymcu_gpio_irq_global_enable(void);

/**
 * @brief Clear CONFIG's master interrupt enable, suppressing every
 * pin's interrupt regardless of its own INT_CONFIG bit.
 */
void tinymcu_gpio_irq_global_disable(void);

/**
 * @brief Enable a pin's interrupt (INT_CONFIG bit), firing on either
 * edge. Has no effect on its own without also calling
 * tinymcu_gpio_irq_global_enable() and enabling the peripheral's IRQ
 * line in the CPU (see tinymcu_csr.h/tinymcu_trap.h).
 * @param pin Pin number, 0-31.
 */
void tinymcu_gpio_irq_enable(unsigned int pin);

/**
 * @brief Disable a pin's interrupt (INT_CONFIG bit). Does not clear an
 * already-pending flag (see tinymcu_gpio_irq_clear()).
 * @param pin Pin number, 0-31.
 */
void tinymcu_gpio_irq_disable(unsigned int pin);

/**
 * @brief Check whether a specific pin's interrupt flag is currently set.
 * @param pin Pin number, 0-31.
 * @return Nonzero if INT_STATUS bit @p pin is set (an edge occurred and
 *         has not been cleared yet), zero otherwise.
 */
unsigned int tinymcu_gpio_irq_pending(unsigned int pin);

/**
 * @brief Read every pin's interrupt flag at once, e.g. to find out which
 * pin(s) fired from inside an ISR without polling each one individually.
 * @return The 32-bit INT_STATUS register, bit i = pin i's flag.
 */
unsigned int tinymcu_gpio_irq_status(void);

/**
 * @brief Clear a single pin's interrupt flag (read-modify-write of
 * INT_STATUS, leaving every other pin's flag untouched). Must be called
 * from the ISR before returning (MRET), or the interrupt immediately
 * re-fires the moment mstatus.MIE is restored.
 * @param pin Pin number, 0-31.
 */
void tinymcu_gpio_irq_clear(unsigned int pin);

/**
 * @brief Clear every pin's interrupt flag at once (INT_STATUS = 0).
 */
void tinymcu_gpio_irq_clear_all(void);

/**
 * @brief Set the global debounce threshold: a pin's edge only reaches
 * the interrupt logic once the raw pad has held the new level for this
 * many consecutive clock cycles. Read-modify-write, leaves CONFIG's
 * other bits (in particular #TINYMCU_GPIO_CONFIG_GLOBAL_INT_EN)
 * untouched. Applies to every pin at once -- there's no per-pin setting.
 * @param cycles Debounce threshold in clock cycles, 0 disables filtering
 *               (values above what
 *               #TINYMCU_GPIO_CONFIG_DEBOUNCE_WIDTH bits can hold are
 *               truncated).
 */
void tinymcu_gpio_debounce_set(unsigned int cycles);

/**
 * @brief Disable the debounce filter (threshold = 0). Every pin's raw
 * level then reaches the interrupt logic immediately, same as before
 * the filter existed.
 */
void tinymcu_gpio_debounce_disable(void);

#endif /* TINYMCU_GPIO_H */
