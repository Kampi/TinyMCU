--------------------------------------------------------------------------------
-- SPDX-License-Identifier: GPL-3.0-or-later
--
-- Company:
-- Engineer: Daniel Kampert
--
-- Create Date: 14.06.2026
-- Design Name: TinyMCU
-- Module Name: tinymcu_periph_uart - tinymcu_periph_uart_rtl
-- Project Name: TinyMCU
-- Description:
--  UART_BASE..UART_END (0x0400_0200..0x0400_02FF)
--
--  Word offset     Name            R/W     Meaning
--  0               CONFIG          RW      Configuration register
--                                              Bit                     Description
--                                              1:0                     Transmission length
--                                                                          00          8-bit
--                                                                          01          7-bit
--                                                                          10          9-bit
--                                                                          11          Unused
--                                              3:2                     Stop bits
--                                                                          00          1
--                                                                          01          2
--                                                                          11          Unused
--                                              5:4                     Parity bits
--                                                                          00          No parity
--                                                                          01          Even parity
--                                                                          10          Odd parity
--                                                                      1   1          Unused
--                                              6                       RTS enable
--                                              7                       CTS enable
--  1               BAUDRATE        RW      Baudrate configuration register.
--  2               STATUS          RW      UART status register
--                                              Bit                     Description
--                                              0                       Transmission active
--                                              1                       Received byte ready (reg_rx_data valid).
--                                                                      Cleared by reading RX_DATA, or overwritten
--                                                                      by the next received byte, whichever first.
--                                              2                       Parity error on the last received byte.
--  3               TX_DATA         W       Write to start a transmission (only accepted while idle).
--  4               RX_DATA         R       Last successfully received byte.
--  5               INT_CONFIG      RW      Interrupt enable register.
--                                              Bit                     Description
--                                              0                       RX_READY interrupt enable.
--                                              31:1                    Unused.
--  6               INT_STATUS      RW      Interrupt status register.
--                                              Bit                     Description
--                                              0                       RX_READY interrupt flag. Tied to STATUS.RX_READY: set every
--                                                                      cycle STATUS.RX_READY = '1' and the interrupt is enabled.
--                                                                      Write to '0' to clear it but this only sticks once
--                                                                      STATUS.RX_READY has gone low too, i.e. read RX_DATA first,
--                                                                      or the flag re-fires the very next cycle.
--                                              31:1                    Unused.
--
-- Dependencies:
--   tinymcu_pkg
--
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library tinymcu;
use tinymcu.tinymcu_pkg.all;

entity tinymcu_periph_uart is
    port (
        -- Global control
        clk_i       : in  std_ulogic;
        rst_i       : in  std_ulogic;

        -- Peripheral Decoder-facing side
        uart_req_i : in  bus_req_t;
        uart_rsp_o : out bus_rsp_t;

        -- Interrupt output
        irq_o       : out std_ulogic;

        -- UART data lines
        tx_o        : out std_ulogic;
        rx_i        : in  std_ulogic;
        rts_o       : out std_ulogic;
        cts_i       : in  std_ulogic
    );
end entity tinymcu_periph_uart;

architecture tinymcu_periph_uart_rtl of tinymcu_periph_uart is

    type UART_Parity_Mode_t is (Parity_None, Parity_Even, Parity_Odd);
    type UART_Tx_State_t is (Tx_Idle, Tx_Start_Bit, Tx_Data_Bits, Tx_Parity_Bit, Tx_Stop_Bits, Tx_Complete);
    type UART_Rx_State_t is (Rx_Idle, Rx_Start_Bit, Rx_Data_Bits, Rx_Parity_Bit, Rx_Stop_Bit, Rx_Complete);

    constant UART_REG_CONFIG        : integer := 0;
    constant UART_REG_BAUDRATE      : integer := 1;
    constant UART_REG_STATUS        : integer := 2;
    constant UART_REG_TX_DATA       : integer := 3;
    constant UART_REG_RX_DATA       : integer := 4;
    constant UART_REG_INT_CONFIG    : integer := 5;
    constant UART_REG_INT_STATUS    : integer := 6;

    constant UART_BIT_TX_ACTIVE     : integer := 0;
    constant UART_BIT_RX_READY      : integer := 1;
    constant UART_BIT_PARITY_ERROR  : integer := 2;
    constant UART_BIT_RTS_ENABLE    : integer := 6;
    constant UART_BIT_CTS_ENABLE    : integer := 7;
    constant UART_BIT_RX_INT_ENABLE : integer := 0;
    constant UART_BIT_RX_INT_FLAG   : integer := 0;

    signal reg_config       : word_t        := (others => '0');
    signal reg_baudrate     : word_t        := (others => '0');
    signal reg_status       : word_t        := (others => '0');
    signal reg_int_config   : word_t        := (others => '0');
    signal reg_int_status   : word_t        := (others => '0');
    signal rdata            : word_t;

    signal status_tx_active   : std_ulogic  := '0';
    signal status_rx_ready    : std_ulogic  := '0';
    signal status_parity_error : std_ulogic := '0';

    signal rx_shift_reg     : std_ulogic_vector(1 downto 0) := (others => '0');
    signal rx_data          : std_ulogic_vector(8 downto 0) := (others => '0');
    signal reg_tx_data      : std_ulogic_vector(8 downto 0);
    signal reg_rx_data      : std_ulogic_vector(8 downto 0) := (others => '0');

    signal word_offset      : integer range 0 to 63;
    signal current_tx_state : UART_Tx_State_t := Tx_Idle;
    signal current_rx_state : UART_Rx_State_t := Rx_Idle;

    -- Decodes CONFIG bits 1:0 into the number of data bits per frame.
    --   databits - CONFIG(1 downto 0), the "Transmission length" field.
    -- Returns: 8, 7 or 9. "11" is unused and also returns 8.
    function databits_reg(databits : std_ulogic_vector(1 downto 0)) return integer is
    begin
        case databits is
            when "00" => return 8;
            when "01" => return 7;
            when "10" => return 9;
            when others => return 8;
        end case;
    end function;

    -- Decodes CONFIG bits 3:2 into the number of stop bits per frame.
    --   stopbits - CONFIG(3 downto 2), the "Stop bits" field.
    -- Returns: 2 for "01", 1 otherwise ("00", "10" and the unused "11").
    function stopbits_reg(stopbits : std_ulogic_vector(1 downto 0)) return integer is
    begin
        case stopbits is
            when "01" => return 2;
            when others => return 1;
        end case;
    end function;

    -- Decodes CONFIG bits 5:4 into the parity mode used for the frame.
    --   parity - CONFIG(5 downto 4), the "Parity bits" field.
    -- Returns: Parity_Even/Parity_Odd, or Parity_None for "00" and the
    -- unused "11" encoding.
    function parity_reg(parity : std_ulogic_vector(1 downto 0)) return UART_Parity_Mode_t is
    begin
        case parity is
            when "01"   => return Parity_Even;
            when "10"   => return Parity_Odd;
            when others => return Parity_None;
        end case;
    end function;

begin

    -- 256 B window, 64 possible word offsets
    word_offset <= to_integer(unsigned(uart_req_i.addr(7 downto 2)));

    ----------------------------------------------------------------------
    -- Register writes
    ----------------------------------------------------------------------
    process (clk_i)
    begin
        if rising_edge(clk_i) then
            if rst_i = '1' then
                reg_config  <= (others => '0');
                reg_baudrate <= (others => '0');
            elsif uart_req_i.stb = '1' and uart_req_i.we = '1' then
                case word_offset is
                    when UART_REG_CONFIG        => reg_config       <= byte_merge(reg_config, uart_req_i.data, uart_req_i.ben);
                    when UART_REG_BAUDRATE      => reg_baudrate     <= byte_merge(reg_baudrate, uart_req_i.data, uart_req_i.ben);
                    when UART_REG_INT_CONFIG    => reg_int_config   <= byte_merge(reg_int_config, uart_req_i.data, uart_req_i.ben);
                    when others                 => null;
                end case;
            end if;
        end if;
    end process;

    ----------------------------------------------------------------------
    -- Register reads
    ----------------------------------------------------------------------
    process (word_offset, reg_config, reg_baudrate, reg_status, reg_rx_data, reg_int_config, reg_int_status)
    begin
        case word_offset is
            when UART_REG_CONFIG        => rdata <= reg_config;
            when UART_REG_BAUDRATE      => rdata <= reg_baudrate;
            when UART_REG_STATUS        => rdata <= reg_status;
            when UART_REG_RX_DATA       => rdata <= std_ulogic_vector(resize(unsigned(reg_rx_data), 32));
            when UART_REG_INT_CONFIG    => rdata <= reg_int_config;
            when UART_REG_INT_STATUS    => rdata <= reg_int_status;
            when others                 => rdata <= (others => '0');
        end case;
    end process;

    uart_rsp_o.data <= rdata;
    uart_rsp_o.ack  <= uart_req_i.stb;
    uart_rsp_o.err  <= '0';

    ----------------------------------------------------------------------
    -- Tx process
    ----------------------------------------------------------------------
    process (clk_i)
        variable num_databits   : integer := 0;
        variable num_stopbits   : integer := 0;
        variable counter        : integer := 0;
        variable baudrate       : integer := 0;
        variable datawidth      : integer := 0;
        variable stopbits       : integer := 0;
        variable parity_mode    : UART_Parity_Mode_t;
    begin
        if rising_edge(clk_i) then
            if rst_i = '1' then
                num_databits := 0;
                baudrate := 0;
                datawidth := 0;
                stopbits := 0;
                parity_mode := Parity_None;

                tx_o <= '1';
                reg_tx_data <= (others => '0');
                status_tx_active <= '0';

                current_tx_state <= Tx_Idle;
            else
                case current_tx_state is
                    when Tx_Idle =>
                        tx_o <= '1';
                        counter := 0;
                        num_databits := 0;
                        num_stopbits := 0;
                        baudrate := to_integer(unsigned(reg_baudrate));
                        datawidth := databits_reg(reg_config(1 downto 0));
                        stopbits := stopbits_reg(reg_config(3 downto 2));
                        parity_mode := parity_reg(reg_config(5 downto 4));

                        if uart_req_i.stb = '1' and uart_req_i.we = '1' and word_offset = UART_REG_TX_DATA and (reg_config(UART_BIT_CTS_ENABLE) = '0' or cts_i = '1') then
                            reg_tx_data <= uart_req_i.data(8 downto 0);

                            current_tx_state <= Tx_Start_Bit;
                        else
                            current_tx_state <= Tx_Idle;
                        end if;

                    when Tx_Start_Bit =>
                        status_tx_active <= '1';
                        tx_o <= '0';

                        if counter < (baudrate - 1) then
                            counter := counter + 1;

                            current_tx_state <= Tx_Start_Bit;
                        else
                            counter := 0;

                            current_tx_state <= Tx_Data_Bits;
                        end if;

                    when Tx_Data_Bits =>
                        tx_o <= reg_tx_data(num_databits);

                        if counter < (baudrate - 1) then
                            counter := counter + 1;

                            current_tx_state <= Tx_Data_Bits;
                        else
                            counter := 0;

                            if num_databits < (datawidth - 1) then
                                num_databits := num_databits + 1;

                                current_tx_state <= Tx_Data_Bits;
                            else
                                num_databits := 0;
                                if parity_mode = Parity_None then
                                    current_tx_state <= Tx_Stop_Bits;
                                else
                                    current_tx_state <= Tx_Parity_Bit;
                                end if;
                            end if;
                        end if;

                    when Tx_Parity_Bit =>
                        if parity_mode = Parity_Even then
                            tx_o <= xor reg_tx_data(datawidth - 1 downto 0);
                        else
                            tx_o <= not (xor reg_tx_data(datawidth - 1 downto 0));
                        end if;

                        if counter < (baudrate - 1) then
                            counter := counter + 1;

                            current_tx_state <= Tx_Parity_Bit;
                        else
                            counter := 0;

                            current_tx_state <= Tx_Stop_Bits;
                        end if;

                    when Tx_Stop_Bits =>
                        tx_o <= '1';

                        if counter < (baudrate - 1) then
                            counter := counter + 1;

                            current_tx_state <= Tx_Stop_Bits;
                        else
                            counter := 0;

                            if num_stopbits < (stopbits - 1) then
                                num_stopbits := num_stopbits + 1;

                                current_tx_state <= Tx_Stop_Bits;
                            else
                                current_tx_state <= Tx_Complete;
                            end if;
                        end if;

                    when Tx_Complete =>
                        status_tx_active <= '0';
                        current_tx_state <= Tx_Idle;

                    when others =>
                        current_tx_state <= Tx_Idle;

                end case;
            end if;
        end if;
    end process;

    ----------------------------------------------------------------------
    -- Rx data synchronization
    ----------------------------------------------------------------------
    process (clk_i)
    begin
        if rising_edge(clk_i) then
            rx_shift_reg(0) <= rx_i;
            rx_shift_reg(1) <= rx_shift_reg(0);
        end if;
    end process;

    ----------------------------------------------------------------------
    -- Rx process
    ----------------------------------------------------------------------
    process (clk_i)
        variable num_databits   : integer := 0;
        variable num_stopbits   : integer := 0;
        variable counter        : integer := 0;
        variable baudrate       : integer := 0;
        variable datawidth      : integer := 0;
        variable stopbits       : integer := 0;
        variable parity_mode    : UART_Parity_Mode_t;
    begin
        if rising_edge(clk_i) then
            if rst_i = '1' then
                num_databits := 0;
                num_stopbits := 0;
                datawidth := 0;
                stopbits := 0;
                baudrate := 0;
                parity_mode := Parity_None;

                rx_data <= (others => '0');
                reg_rx_data <= (others => '0');
                status_rx_ready <= '0';
                status_parity_error <= '0';
                current_rx_state <= Rx_Idle;
            else
                if uart_req_i.stb = '1' and uart_req_i.we = '0' and word_offset = UART_REG_RX_DATA then
                    status_rx_ready <= '0';
                end if;

                case current_rx_state is
                    when Rx_Idle =>
                        counter := 0;
                        num_databits := 0;
                        num_stopbits := 0;
                        baudrate := to_integer(unsigned(reg_baudrate));
                        datawidth := databits_reg(reg_config(1 downto 0));
                        stopbits := stopbits_reg(reg_config(3 downto 2));
                        parity_mode := parity_reg(reg_config(5 downto 4));

                        if rx_shift_reg(1) = '0' then
                            current_rx_state <= Rx_Start_Bit;
                        else
                            current_rx_state <= Rx_Idle;
                        end if;

                    when Rx_Start_Bit =>
                        if counter = (baudrate - 1) / 2 then
                            counter := 0;

                            if rx_shift_reg(1) = '0' then
                                current_rx_state <= Rx_Data_Bits;
                            else
                                current_rx_state <= Rx_Idle;
                            end if;
                        else
                            counter := counter + 1;

                            current_rx_state <= Rx_Start_Bit;
                        end if;

                    when Rx_Data_Bits =>
                        if counter < (baudrate - 1) then
                            counter := counter + 1;

                            current_rx_state <= Rx_Data_Bits;
                        else
                            counter := 0;
                            rx_data(num_databits) <= rx_shift_reg(1);

                            if num_databits < (datawidth - 1) then
                                num_databits := num_databits + 1;

                                current_rx_state <= Rx_Data_Bits;
                            else
                                num_databits := 0;
                                if parity_mode = Parity_None then
                                    current_rx_state <= Rx_Stop_Bit;
                                else
                                    current_rx_state <= Rx_Parity_Bit;
                                end if;
                            end if;
                        end if;

                    when Rx_Parity_Bit =>
                        if counter < (baudrate - 1) then
                            counter := counter + 1;

                            current_rx_state <= Rx_Parity_Bit;
                        else
                            counter := 0;

                            if parity_mode = Parity_Even then
                                status_parity_error <= rx_shift_reg(1) xor (xor rx_data(datawidth - 1 downto 0));
                            else
                                status_parity_error <= rx_shift_reg(1) xor (not (xor rx_data(datawidth - 1 downto 0)));
                            end if;

                            current_rx_state <= Rx_Stop_Bit;
                        end if;

                    when Rx_Stop_Bit =>
                        if counter < (baudrate - 1) then
                            counter := counter + 1;

                            current_rx_state <= Rx_Stop_Bit;
                        else
                            counter := 0;

                            if num_stopbits < (stopbits - 1) then
                                num_stopbits := num_stopbits + 1;

                                current_rx_state <= Rx_Stop_Bit;
                            else
                                reg_rx_data <= rx_data;
                                status_rx_ready <= '1';

                                current_rx_state <= Rx_Complete;
                            end if;
                        end if;

                    when Rx_Complete =>
                        current_rx_state <= Rx_Idle;

                    when others =>
                        current_rx_state <= Rx_Idle;
                end case;
            end if;
        end if;
    end process;

    reg_status <= (UART_BIT_TX_ACTIVE    => status_tx_active,
                   UART_BIT_RX_READY     => status_rx_ready,
                   UART_BIT_PARITY_ERROR => status_parity_error,
                   others                => '0');

    rts_o <= not status_rx_ready when (reg_config(UART_BIT_RTS_ENABLE) = '1') else '1';

    ----------------------------------------------------------------------
    -- Interrupt flags generation
    ----------------------------------------------------------------------
    process (clk_i)
    begin
        if rising_edge(clk_i) then
            if rst_i = '1' then
                reg_int_status  <= (others => '0');
            else
                -- Software clear (write bit to '0')
                if uart_req_i.stb = '1' and uart_req_i.we = '1' and word_offset = UART_REG_INT_STATUS then
                    reg_int_status <= byte_merge(reg_int_status, uart_req_i.data, uart_req_i.ben);
                -- Set the interrupt flags
                else
                    if reg_status(UART_BIT_RX_READY) = '1' and reg_int_config(UART_BIT_RX_INT_ENABLE) = '1' then
                        reg_int_status(UART_BIT_RX_INT_FLAG) <= '1';
                    end if;
                end if;
            end if;
        end if;
    end process;

    irq_o <= '1' when reg_int_status(UART_BIT_RX_INT_FLAG) = '1' else '0';

end architecture tinymcu_periph_uart_rtl;
