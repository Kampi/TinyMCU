--------------------------------------------------------------------------------
-- SPDX-License-Identifier: GPL-3.0-or-later
--
-- Company:
-- Engineer: Daniel Kampert
--
-- Create Date: 14.06.2026
-- Design Name: TinyMCU
-- Module Name: tinymcu_imem_xip - tinymcu_imem_xip_rtl
-- Project Name: TinyMCU
-- Description:
--  Dedicated SPI master for execute-in-place: its own bus, separate from
--  a general-purpose peripheral SPI (e.g. for a Boot ROM loader that
--  programs the flash).
--
--  Two state machines share one physical bus (sclk_o/ss_n_o/mosi_o/
--  miso_i) and one clock/edge generator, switched by CONFIG's ENABLE
--  bit. ENABLE=1 runs the read (XIP fetch) engine, ENABLE=0 runs the
--  write engine. Only one is ever driving the pins at a time.
--
--  Word offset     Name            R/W     Meaning
--  0               CONFIG          RW      Bit fields below; otherwise general-purpose, reserved for future use.
--                                              Bit                     Description
--                                              0                       CPHA
--                                              1                       CPOL
--                                              2                       Enable the XIP fetch engine and disable the
--                                                                      XIP write engine
--                                              3                       Bit order
--                                                                          0   MSB first
--                                                                          1   LSB first
--                                              11:4                    CLKDIV. SCLK toggles every
--                                                                      (CLKDIV + 1) clk_i cycles, i.e. one
--                                                                      full SCLK period is
--                                                                      2 * (CLKDIV + 1) clk_i cycles
--                                              12                      CS_ASSERT. For write engine only (ENABLE=0):
--                                                                      software sets '1' before the first TX_DATA
--                                                                      byte of a multi-byte command and '0' after
--                                                                      the last, holding ss_n_o low for the whole
--                                                                      sequence in between. A TX_DATA write while
--                                                                      CS_ASSERT is '0' is ignored.
--                                              15:13                   Unused
--  1               STATUS          R           Bit
--                                              0                       '1' while either engine's SPI transaction is in progress
--  2               TX_DATA         W       Write engine only (ENABLE=0). Writing starts one 8-bit transfer.
--                                          The byte sent MSB- or LSB-first per CONFIG's bit-order field.
--  3               RX_DATA         R       Write engine only. The byte shifted in over miso_i during the
--                                          most recently completed write-engine transfer.
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

entity tinymcu_imem_xip is
    port (
        -- Global control
        clk_i           : in std_ulogic;
        rst_i           : in std_ulogic;

        -- Peripheral Decoder-facing side
        xip_req_i       : in  bus_req_t;
        xip_rsp_o       : out bus_rsp_t;

        -- PC-facing side
        fetch_addr_i    : in  word_t;
        fetch_dout_o    : out word_t;
        fetch_ready_o   : out std_ulogic;

        -- SPI pins
        miso_i          : in  std_logic;
        sclk_o          : out std_logic;
        ss_n_o          : out std_logic;
        mosi_o          : out std_logic
    );
end entity tinymcu_imem_xip;

architecture tinymcu_imem_xip_rtl of tinymcu_imem_xip is

    -- 8 opcode + 24 address + 32 data (read engine only)
    constant XIP_TOTAL_BITS     : integer := 64;

    constant XIP_REG_CONFIG     : integer := 0;
    constant XIP_REG_STATUS     : integer := 1;
    constant XIP_TX_DATA        : integer := 2;
    constant XIP_RX_DATA        : integer := 3;

    constant XIP_BIT_CPHA       : integer := 0;
    constant XIP_BIT_CPOL       : integer := 1;
    constant XIP_BIT_ENABLE     : integer := 2;
    constant XIP_BIT_LSB_FIRST  : integer := 3;
    constant XIP_BIT_CS_ASSERT  : integer := 12;

    constant XIP_OPCODE_READ    : std_ulogic_vector(7 downto 0) := x"03";

    type XIP_Read_State_t is (Read_Disabled, Read_Idle, Read_Busy);
    type XIP_Write_State_t is (Write_Disabled, Write_Idle, Write_Busy);

    signal reg_config   : word_t := (others => '0');
    signal reg_tx_data  : std_ulogic_vector(7 downto 0) := (others => '0');
    signal reg_rx_data  : std_ulogic_vector(7 downto 0) := (others => '0');
    signal rdata        : word_t;
    signal word_offset  : integer range 0 to 63;

    signal enable       : std_ulogic;
    signal lsb_first    : std_ulogic;
    signal cs_assert    : std_ulogic;

    -- Shared between both engines
    signal sclk                 : std_ulogic := '0';
    signal sclk_sample_edge     : std_ulogic := '0';
    signal sclk_shift_edge      : std_ulogic := '0';
    signal write_sampled_bit    : std_ulogic;
    signal read_sampled_bit     : std_ulogic;

    signal write_xfer_start     : std_ulogic := '0';
    signal read_xfer_start      : std_ulogic := '0';
    signal mosi_write           : std_ulogic := '0';
    signal ss_n_write           : std_ulogic := '1';
    signal ss_n_read            : std_ulogic := '1';

    signal current_write_state  : XIP_Write_State_t := Write_Disabled;
    signal current_read_state   : XIP_Read_State_t  := Read_Disabled;

    -- Read (XIP fetch) engine
    -- 1-entry fetch cache, see header comment
    signal shift_reg  : std_ulogic_vector(XIP_TOTAL_BITS - 1 downto 0);
    signal last_addr  : word_t;
    signal last_data  : word_t;
    signal last_valid : std_ulogic := '0';

begin

    enable <= reg_config(XIP_BIT_ENABLE);
    lsb_first <= reg_config(XIP_BIT_LSB_FIRST);
    cs_assert <= reg_config(XIP_BIT_CS_ASSERT);

    -- 256 B window, 64 possible word offsets
    word_offset <= to_integer(unsigned(xip_req_i.addr(7 downto 2)));

    ----------------------------------------------------------------------
    -- Register writes (CONFIG only)
    ----------------------------------------------------------------------
    process (clk_i)
    begin
        if rising_edge(clk_i) then
            if rst_i = '1' then
                reg_config <= (others => '0');
            elsif xip_req_i.stb = '1' and xip_req_i.we = '1' then
                case word_offset is
                    when XIP_REG_CONFIG => reg_config <= byte_merge(reg_config, xip_req_i.data, xip_req_i.ben);
                    when others         => null;
                end case;
            end if;
        end if;
    end process;

    ----------------------------------------------------------------------
    -- Register reads
    ----------------------------------------------------------------------
    process (word_offset, reg_config, reg_rx_data, current_read_state, current_write_state)
    begin
        rdata <= (others => '0');
        case word_offset is
            when XIP_REG_CONFIG =>
                rdata <= reg_config;
            when XIP_REG_STATUS =>
                if current_read_state = Read_Busy or current_write_state = Write_Busy then
                    rdata(0) <= '1';
                end if;
            when XIP_RX_DATA =>
                rdata(7 downto 0) <= reg_rx_data;
            when others =>
                null;
        end case;
    end process;

    xip_rsp_o.data  <= rdata;
    xip_rsp_o.ack   <= xip_req_i.stb;
    xip_rsp_o.err   <= '0';

    ----------------------------------------------------------------------
    -- SPI clock and edge generation, shared by both engines.
    ----------------------------------------------------------------------
    process (clk_i)
        variable counter        : integer := 0;
        variable spi_clock      : integer := 0;
        variable leading        : boolean;
        variable new_bit        : std_ulogic;
        variable cpha           : std_ulogic;
        variable cpol           : std_ulogic;
        variable active         : boolean := false;
        variable bits_remaining : integer range 0 to XIP_TOTAL_BITS := 0;
    begin
        if rising_edge(clk_i) then
            cpha := reg_config(XIP_BIT_CPHA);
            cpol := reg_config(XIP_BIT_CPOL);

            sclk_sample_edge <= '0';
            sclk_shift_edge  <= '0';

            if rst_i = '1' then
                counter := 0;
                spi_clock := 0;
                active := false;
                bits_remaining := 0;

                sclk <= '0';
            elsif write_xfer_start = '1' then
                counter := 0;
                active := true;
                bits_remaining := 8;

                sclk <= cpol;
            elsif read_xfer_start = '1' then
                counter := 0;
                active := true;
                bits_remaining := XIP_TOTAL_BITS;

                sclk <= cpol;
            elsif active then
                spi_clock := to_integer(unsigned(reg_config(11 downto 4)));

                if counter < spi_clock then
                    counter := counter + 1;
                else
                    counter := 0;

                    new_bit := not sclk;
                    leading := (new_bit /= cpol);

                    sclk <= new_bit;

                    if (leading and cpha = '0') or ((not leading) and cpha = '1') then
                        sclk_sample_edge <= '1';
                    else
                        sclk_shift_edge <= '1';

                        if bits_remaining = 1 then
                            active := false;
                        else
                            bits_remaining := bits_remaining - 1;
                        end if;
                    end if;
                end if;
            else
                counter := 0;

                sclk <= cpol;
            end if;
        end if;
    end process;

    ----------------------------------------------------------------------
    -- SPI write engine (ENABLE=0)
    ----------------------------------------------------------------------
    process (clk_i)
        variable bit_counter  : integer range 0 to 7 := 0;
        variable tx_lsb_first : std_ulogic := '0';
    begin
        if rising_edge(clk_i) then
            if rst_i = '1' then
                bit_counter := 0;
                tx_lsb_first := '0';

                ss_n_write <= '1';
                mosi_write <= '0';
                write_xfer_start <= '0';

                current_write_state <= Write_Disabled;
            else
                write_xfer_start <= '0';

                case current_write_state is
                    when Write_Disabled =>
                        bit_counter := 0;

                        ss_n_write <= '1';

                        if enable = '0' then
                            current_write_state <= Write_Idle;
                        else
                            current_write_state <= Write_Disabled;
                        end if;

                    when Write_Idle =>
                        ss_n_write <= not cs_assert;

                        if enable = '1' then
                            current_write_state <= Write_Disabled;
                        elsif cs_assert = '1' and xip_req_i.stb = '1' and xip_req_i.we = '1' and word_offset = XIP_TX_DATA then
                            tx_lsb_first := lsb_first;
                            bit_counter := 0;

                            reg_tx_data  <= xip_req_i.data(7 downto 0);

                            if lsb_first = '1' then
                                mosi_write <= xip_req_i.data(0);
                            else
                                mosi_write <= xip_req_i.data(7);
                            end if;

                            write_xfer_start <= '1';

                            current_write_state <= Write_Busy;
                        else
                            current_write_state <= Write_Idle;
                        end if;

                    when Write_Busy =>
                        ss_n_write <= not cs_assert;

                        if sclk_sample_edge = '1' then
                            write_sampled_bit <= miso_i;
                        end if;

                        if sclk_shift_edge = '1' then
                            reg_rx_data(bit_counter) <= write_sampled_bit;

                            if tx_lsb_first = '1' then
                                mosi_write <= reg_tx_data(1);
                                reg_tx_data <= '0' & reg_tx_data(7 downto 1);
                            else
                                mosi_write <= reg_tx_data(6);
                                reg_tx_data <= reg_tx_data(6 downto 0) & '0';
                            end if;

                            if bit_counter = 7 then
                                current_write_state <= Write_Idle;
                            else
                                bit_counter := bit_counter + 1;
                            end if;
                        end if;
                end case;
            end if;
        end if;
    end process;

    ----------------------------------------------------------------------
    -- SPI fetch engine (ENABLE=1)
    ----------------------------------------------------------------------
    process (clk_i)
        variable bit_counter : integer range 0 to XIP_TOTAL_BITS := 0;
        variable new_shift   : std_ulogic_vector(XIP_TOTAL_BITS - 1 downto 0);
        variable req_addr    : word_t;
    begin
        if rising_edge(clk_i) then
            if rst_i = '1' then
                bit_counter := 0;

                ss_n_read <= '1';
                last_valid <= '0';
                read_xfer_start <= '0';

                current_read_state <= Read_Disabled;
            else
                read_xfer_start <= '0';

                case current_read_state is
                    when Read_Disabled =>
                        ss_n_read <= '1';

                        if enable = '1' then
                            current_read_state <= Read_Idle;
                        else
                            current_read_state <= Read_Disabled;
                        end if;

                    when Read_Idle =>
                        if enable = '0' then
                            current_read_state <= Read_Disabled;
                        elsif last_valid = '0' or fetch_addr_i /= last_addr then
                            bit_counter := 0;

                            ss_n_read <= '0';
                            req_addr := fetch_addr_i;

                            if lsb_first = '0' then
                                shift_reg <= XIP_OPCODE_READ & fetch_addr_i(23 downto 0) & x"00000000";
                            else
                                shift_reg <= bit_reverse(XIP_OPCODE_READ) &
                                             bit_reverse(fetch_addr_i(23 downto 16)) &
                                             bit_reverse(fetch_addr_i(15 downto 8)) &
                                             bit_reverse(fetch_addr_i(7 downto 0)) &
                                             x"00000000";
                            end if;

                            read_xfer_start <= '1';

                            current_read_state <= Read_Busy;
                        else
                            ss_n_read <= '1';
                        end if;

                    when Read_Busy =>
                        if sclk_sample_edge = '1' then
                            read_sampled_bit <= miso_i;
                        end if;

                        if sclk_shift_edge = '1' then
                            new_shift := shift_reg(XIP_TOTAL_BITS - 2 downto 0) & read_sampled_bit;
                            shift_reg <= new_shift;

                            if bit_counter = XIP_TOTAL_BITS - 1 then
                                last_valid <= '1';
                                ss_n_read <= '1';
                                last_addr <= req_addr;

                                if lsb_first = '0' then
                                    last_data <= new_shift(7 downto 0) & new_shift(15 downto 8) &
                                                 new_shift(23 downto 16) & new_shift(31 downto 24);
                                else
                                    last_data <= bit_reverse(new_shift(7 downto 0)) & bit_reverse(new_shift(15 downto 8)) &
                                                 bit_reverse(new_shift(23 downto 16)) & bit_reverse(new_shift(31 downto 24));
                                end if;

                                current_read_state <= Read_Idle;
                            else
                                bit_counter := bit_counter + 1;
                            end if;
                        end if;
                end case;
            end if;
        end if;
    end process;

    sclk_o <= sclk;
    mosi_o <= shift_reg(XIP_TOTAL_BITS - 1) when enable = '1' else mosi_write;
    ss_n_o <= ss_n_read when enable = '1' else ss_n_write;

    fetch_ready_o <= '1' when (enable = '1' and last_valid = '1' and fetch_addr_i = last_addr) else '0';
    fetch_dout_o  <= last_data;

end architecture tinymcu_imem_xip_rtl;
