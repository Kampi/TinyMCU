--------------------------------------------------------------------------------
-- SPDX-License-Identifier: GPL-3.0-or-later
--
-- Company:
-- Engineer: Daniel Kampert
--
-- Create Date: 24.08.2026
-- Design Name: TinyMCU
-- Module Name: tb_uart - sim
-- Project Name: TinyMCU
-- Description:
--   Standalone functional test for tinymcu_periph_uart.vhd.
--
-- Dependencies:
--   tinymcu.tinymcu_pkg, tinymcu.tinymcu_periph_uart
--
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

library tinymcu;
use tinymcu.tinymcu_pkg.all;

entity tb_uart is end entity tb_uart;

architecture sim of tb_uart is

    constant CLK_PERIOD : time := 10 ns;

    -- 16 MHz system clock, 9600 baud -> clocks-per-bit = 16_000_000/9600
    constant N : integer := 1667;

    signal clk : std_ulogic := '0';
    signal rst : std_ulogic := '1';
    signal tx  : std_ulogic;
    signal rx  : std_ulogic := '1';
    signal rts : std_ulogic;
    signal cts : std_ulogic := '1';
    signal req : bus_req_t := (addr => (others => '0'), data => (others => '0'), ben => (others => '0'), we => '0', stb => '0');
    signal rsp : bus_rsp_t;

begin

    clk <= not clk after CLK_PERIOD / 2;

    dut : entity tinymcu.tinymcu_periph_uart
        port map (
            clk_i => clk,
            rst_i => rst,
            tx_o => tx,
            rx_i => rx,
            rts_o => rts,
            cts_i => cts,
            uart_req_i => req,
            uart_rsp_o => rsp
        );

    stim : process
        procedure bus_write(addr : std_ulogic_vector(31 downto 0); data : word_t) is
        begin
            wait until rising_edge(clk);
            req.addr <= addr;
            req.data <= data;
            req.ben  <= "1111";
            req.we   <= '1';
            req.stb  <= '1';
            wait until rising_edge(clk);
            req.we  <= '0';
            req.stb <= '0';
        end procedure;

        procedure bus_read(addr : std_ulogic_vector(31 downto 0); variable result : out word_t) is
        begin
            wait until rising_edge(clk);
            req.addr <= addr;
            req.we   <= '0';
            req.stb  <= '1';
            wait for 1 ns;
            result := rsp.data;
            wait until rising_edge(clk);
            req.stb <= '0';
        end procedure;

        variable rd : word_t;
        variable errors : integer := 0;

        -- Waits to the middle of the next N-cycle bit slot, then checks
        -- tx_o against the expected level.
        procedure check_bit(name : string; expected : std_ulogic) is
        begin
            wait for CLK_PERIOD * (N / 2);
            check(name & " (expect " & std_ulogic'image(expected) & ", got " & std_ulogic'image(tx) & ")",
                  tx = expected, errors);
            wait for CLK_PERIOD * (N - N / 2);
        end procedure;

        constant TEST_BYTE : std_ulogic_vector(7 downto 0) := x"A5";  -- 1010_0101

        -- Drives one N-cycle bit slot on rx_i.
        procedure send_bit(v : std_ulogic) is
        begin
            rx <= v;
            wait for CLK_PERIOD * N;
        end procedure;

        -- 8N1-with-parity frame: start(0), 8 data bits LSB-first, parity,
        -- 2 stop bits(1)
        procedure send_byte(data : std_ulogic_vector(7 downto 0); bad_parity : boolean) is
            variable parity_bit : std_ulogic;
        begin
            parity_bit := xor data;  -- even parity
            if bad_parity then
                parity_bit := not parity_bit;
            end if;

            send_bit('0');                       -- start bit
            for i in 0 to 7 loop
                send_bit(data(i));
            end loop;
            send_bit(parity_bit);
            send_bit('1');                       -- stop bit 1
            send_bit('1');                       -- stop bit 2
        end procedure;
    begin
        wait for CLK_PERIOD * 3;
        rst <= '0';
        wait for CLK_PERIOD * 2;

        check("tx_o idles high before any transmission", tx = '1', errors);

        -- CONFIG = 0 (8 data bits, 1 stop bit, no parity -- also the
        -- reset default, written explicitly here for clarity)
        bus_write(x"00000000", x"00000000");
        -- BAUDRATE = 1667 (word offset 1 -> byte 0x04)
        bus_write(x"00000004", std_ulogic_vector(to_unsigned(N, 32)));

        bus_read(x"00000008", rd);  -- STATUS (word offset 2)
        check("TX_ACTIVE low before transmission", rd(0) = '0', errors);

        -- TX_DATA = 0xA5
        bus_write(x"0000000C", x"000000A5");

        wait until rising_edge(clk);
        bus_read(x"00000008", rd);
        check("TX_ACTIVE high right after TX_DATA write", rd(0) = '1', errors);

        -- Start bit
        check_bit("start bit", '0');
        -- 8 data bits, LSB first: 0xA5 = 1010_0101 -> bit0..bit7 = 1,0,1,0,0,1,0,1
        for i in 0 to 7 loop
            check_bit("data bit " & integer'image(i), TEST_BYTE(i));
        end loop;
        -- Stop bit
        check_bit("stop bit", '1');

        wait for CLK_PERIOD * 5;
        bus_read(x"00000008", rd);
        check("TX_ACTIVE low after transmission completes", rd(0) = '0', errors);
        check("tx_o idles high again after transmission", tx = '1', errors);

        -- CONFIG: 8 data bits (bits 1:0 = 00), 2 stop bits (bits 3:2 =
        -- 01 -> 0x4), even parity (bits 5:4 = 01 -> 0x10) = 0x14.
        bus_write(x"00000000", x"00000014");

        bus_read(x"00000008", rd);
        check("RX_READY low before any frame", rd(1) = '0', errors);

        -- Correct-parity byte.
        send_byte(x"A5", false);
        wait for CLK_PERIOD * 2;

        bus_read(x"00000008", rd);
        check("RX_READY set after correct-parity frame", rd(1) = '1', errors);
        check("PARITY_ERROR clear after correct-parity frame", rd(2) = '0', errors);

        bus_read(x"00000010", rd);  -- RX_DATA (word offset 4 = byte 0x10)
        check("RX_DATA = 0xA5", to_integer(unsigned(rd)) = 16#A5#, errors);

        bus_read(x"00000008", rd);
        check("RX_READY cleared by reading RX_DATA", rd(1) = '0', errors);

        -- Bad-parity byte: data must still come through correctly, only
        -- the error flag should fire.
        send_byte(x"3C", true);
        wait for CLK_PERIOD * 2;

        bus_read(x"00000008", rd);
        check("RX_READY set after bad-parity frame", rd(1) = '1', errors);
        check("PARITY_ERROR set after bad-parity frame", rd(2) = '1', errors);

        bus_read(x"00000010", rd);
        check("RX_DATA = 0x3C even with bad parity", to_integer(unsigned(rd)) = 16#3C#, errors);

        report "Total errors: " & integer'image(errors);
        if errors = 0 then
            report "ALL CHECKS PASSED";
        end if;

        std.env.stop;
        wait;
    end process;

end architecture sim;
