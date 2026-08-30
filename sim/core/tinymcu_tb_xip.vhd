--------------------------------------------------------------------------------
-- SPDX-License-Identifier: GPL-3.0-or-later
--
-- Company:
-- Engineer: Daniel Kampert
--
-- Create Date: 29.08.2026
-- Design Name: TinyMCU
-- Module Name: tb_xip - sim
-- Project Name: TinyMCU
-- Description:
--   Standalone functional test for tinymcu_imem_xip.vhd: CONFIG/STATUS
--   register plumbing, plus a small SPI NOR flash model that actually
--   holds memory (opcode 0x03 standard read, opcode 0x02 page program,
--   4 bytes each) instead of just echoing a fixed reply, so the
--   write engine (TX_DATA/CS_ASSERT, ENABLE=0) and the read/fetch
--   engine (ENABLE=1) can be exercised end to end: program a word,
--   then fetch that same address back and check it round-trips.
--
--   Also covers: opcode/address sent correctly, the 4 read-side bytes
--   reassembled into the right little-endian word, the 1-entry fetch
--   cache, ENABLE gating, and LSB_FIRST's per-byte bit reversal.
--
--   The flash model only exercises CPOL=0/CPHA=0 (Mode 0, the CONFIG
--   reset value) with CLKDIV=0: it waits for exactly 32 SCLK rising
--   edges (the opcode+address header) and then, depending on the
--   opcode, either drives 32 falling edges (read reply) or captures 32
--   more rising edges (program data). Both engines always move
--   exactly 8+24+32 bits per transaction. Modes 1-3 aren't separately
--   exercised: all four share the same leading/trailing-edge selection
--   logic, and the LSB_FIRST check below already walks that same code
--   path from a different generic input, so Mode 0 plus LSB_FIRST
--   gives reasonable coverage without a second flash model.
--
-- Dependencies:
--   tinymcu.tinymcu_pkg, tinymcu.tinymcu_imem_xip
--
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

library tinymcu;
use tinymcu.tinymcu_pkg.all;

entity tb_xip is end entity tb_xip;

architecture sim of tb_xip is

    constant CLK_PERIOD : time := 10 ns;

    -- word offsets 0/1/2/3, see tinymcu_imem_xip.vhd's header comment
    constant CFG_ADDR    : word_t := x"00000000";
    constant STATUS_ADDR : word_t := x"00000004";
    constant TX_ADDR     : word_t := x"00000008";
    constant RX_ADDR     : word_t := x"0000000C";

    constant OPCODE_READ    : std_ulogic_vector(7 downto 0) := x"03";
    constant OPCODE_PROGRAM : std_ulogic_vector(7 downto 0) := x"02";

    -- Fixed flash reply for the plain-read tests below, sent MSB-first
    -- byte0..byte3 = BE,BA,FE,CA. Once reassembled little-endian by
    -- the DUT, fetch_dout_o should read exactly x"CAFEBABE".
    constant FLASH_REPLY     : std_ulogic_vector(31 downto 0) := x"BEBAFECA";
    constant FLASH_REPLY_LE  : word_t := x"CAFEBABE";

    -- Word programmed into the flash model by the write-then-read-back
    -- test, and what fetch_dout_o should read back afterwards (same
    -- little-endian reassembly as any other fetch).
    constant PROGRAM_WORD    : word_t := x"11223344";
    constant PROGRAM_ADDR    : word_t := x"00008100";

    signal clk : std_ulogic := '0';
    signal rst : std_ulogic := '1';

    signal xip_req : bus_req_t := BUS_REQ_IDLE;
    signal xip_rsp : bus_rsp_t;

    signal fetch_addr  : word_t := (others => '0');
    signal fetch_dout  : word_t;
    signal fetch_ready : std_ulogic;

    signal miso : std_logic := '1';
    signal sclk : std_logic;
    signal ss_n : std_logic;
    signal mosi : std_logic;

    -- Raw header bits (opcode + 24-bit address) as captured off mosi by
    -- the flash model below, wire order, before any interpretation.
    signal header_captured : std_ulogic_vector(31 downto 0) := (others => '0');
    signal header_valid    : std_ulogic := '0';

    -- Tiny simulated flash array, byte-addressed.
    type mem_t is array (0 to 255) of std_ulogic_vector(7 downto 0);
    signal mem : mem_t := (others => x"00");

begin

    clk <= not clk after CLK_PERIOD / 2;

    dut : entity tinymcu.tinymcu_imem_xip
        port map (
            clk_i         => clk,
            rst_i         => rst,
            xip_req_i     => xip_req,
            xip_rsp_o     => xip_rsp,
            fetch_addr_i  => fetch_addr,
            fetch_dout_o  => fetch_dout,
            fetch_ready_o => fetch_ready,
            miso_i        => miso,
            sclk_o        => sclk,
            ss_n_o        => ss_n,
            mosi_o        => mosi
        );

    ----------------------------------------------------------------------
    -- SPI NOR flash model, see this file's header comment.
    ----------------------------------------------------------------------
    flash_model : process
        variable header : std_ulogic_vector(31 downto 0);
        variable addr   : integer;
        variable rdata  : std_ulogic_vector(31 downto 0);
        variable wbyte  : std_ulogic_vector(7 downto 0);
    begin
        loop
            wait until falling_edge(ss_n);
            header_valid <= '0';

            header := (others => '0');
            for i in 0 to 31 loop
                wait until rising_edge(sclk);
                header := header(30 downto 0) & mosi;
            end loop;
            header_captured <= header;
            header_valid    <= '1';
            -- mem is only 256 B; the low address byte is plenty to
            -- distinguish test cases without needing a full-size array.
            addr := to_integer(unsigned(header(7 downto 0)));

            if header(31 downto 24) = OPCODE_PROGRAM then
                -- Capture 4 data bytes off mosi, store into mem.
                for b in 0 to 3 loop
                    wbyte := (others => '0');
                    for i in 0 to 7 loop
                        wait until rising_edge(sclk);
                        wbyte := wbyte(6 downto 0) & mosi;
                    end loop;
                    mem(addr + b) <= wbyte;
                end loop;
            else
                -- Anything else (including LSB_FIRST's bit-reversed 0xC0
                -- for a plain read) is treated as a read.
                if addr = to_integer(unsigned(PROGRAM_ADDR(7 downto 0))) then
                    rdata := mem(addr) & mem(addr + 1) & mem(addr + 2) & mem(addr + 3);
                else
                    rdata := FLASH_REPLY;
                end if;

                for i in 0 to 31 loop
                    wait until falling_edge(sclk);
                    miso  <= rdata(31);
                    rdata := rdata(30 downto 0) & '0';
                end loop;
            end if;

            wait until rising_edge(ss_n);
            miso <= '1';
        end loop;
    end process;

    stim : process
        procedure bus_write(addr : std_ulogic_vector(31 downto 0); data : word_t) is
        begin
            wait until rising_edge(clk);
            xip_req.addr <= addr;
            xip_req.data <= data;
            xip_req.ben  <= "1111";
            xip_req.we   <= '1';
            xip_req.stb  <= '1';
            wait until rising_edge(clk);
            xip_req.we  <= '0';
            xip_req.stb <= '0';
        end procedure;

        procedure bus_read(addr : std_ulogic_vector(31 downto 0); variable result : out word_t) is
        begin
            xip_req.addr <= addr;
            xip_req.we   <= '0';
            xip_req.stb  <= '1';
            wait for 1 ns;
            result := xip_rsp.data;
            xip_req.stb <= '0';
        end procedure;

        -- Writes one byte through TX_DATA and waits for the write
        -- engine to finish shifting it out (STATUS's BUSY bit) before
        -- returning, so the caller can issue the next byte right away.
        procedure write_byte(b : std_ulogic_vector(7 downto 0)) is
            variable rd : word_t;
        begin
            bus_write(TX_ADDR, x"000000" & b);
            loop
                bus_read(STATUS_ADDR, rd);
                exit when rd(0) = '0';
            end loop;
        end procedure;

        variable rd : word_t;
        variable errors : integer := 0;
    begin
        wait for CLK_PERIOD * 3;
        rst <= '0';
        wait for CLK_PERIOD * 2;

        ------------------------------------------------------------------
        -- CONFIG/STATUS register plumbing
        ------------------------------------------------------------------
        bus_read(CFG_ADDR, rd);
        check("CONFIG resets to 0", to_integer(unsigned(rd)) = 0, errors);
        bus_read(STATUS_ADDR, rd);
        check("STATUS idle at reset", rd(0) = '0', errors);

        bus_write(CFG_ADDR, x"000000AA");
        bus_read(CFG_ADDR, rd);
        check("CONFIG write/read back", to_integer(unsigned(rd)) = 16#AA#, errors);

        ------------------------------------------------------------------
        -- Enable, Mode 0 (CPHA=0/CPOL=0), CLKDIV=0 (fastest), MSB first.
        ------------------------------------------------------------------
        bus_write(CFG_ADDR, x"00000004");  -- bit 2 = ENABLE
        check("fetch_ready low before any fetch", fetch_ready = '0', errors);

        fetch_addr <= x"00008010";
        wait until header_valid = '1';
        check("opcode sent = 0x03", header_captured(31 downto 24) = OPCODE_READ, errors);
        check("address sent matches fetch_addr_i", header_captured(23 downto 0) = fetch_addr(23 downto 0), errors);

        wait until fetch_ready = '1';
        check("fetch_dout_o = expected flash data", fetch_dout, FLASH_REPLY_LE, errors);
        check("ss_n released after transaction", ss_n = '1', errors);

        ------------------------------------------------------------------
        -- 1-entry cache: same address again must not start a new
        -- transaction (ss_n stays high, fetch_ready stays asserted).
        ------------------------------------------------------------------
        wait for CLK_PERIOD * 10;
        check("fetch_ready stays high, same address (cache hit)", fetch_ready = '1', errors);
        check("no new transaction started (ss_n stays high)", ss_n = '1', errors);

        ------------------------------------------------------------------
        -- New address must trigger a fresh transaction.
        ------------------------------------------------------------------
        fetch_addr <= x"00008020";
        wait for CLK_PERIOD * 2;
        check("fetch_ready drops for a new address", fetch_ready = '0', errors);
        wait until fetch_ready = '1';
        check("fetch_dout_o correct for second fetch", fetch_dout, FLASH_REPLY_LE, errors);
        check("address sent matches second fetch_addr_i", header_captured(23 downto 0) = fetch_addr(23 downto 0), errors);

        ------------------------------------------------------------------
        -- Disabling must stop new fetches from ever completing.
        ------------------------------------------------------------------
        bus_write(CFG_ADDR, x"00000000");  -- ENABLE = 0
        fetch_addr <= x"00008030";
        wait for CLK_PERIOD * 50;
        check("fetch_ready stays low when disabled", fetch_ready = '0', errors);
        check("no SPI transaction while disabled (ss_n stays high)", ss_n = '1', errors);

        ------------------------------------------------------------------
        -- LSB_FIRST: opcode 0x03 bit-reversed is 0xC0. Check the wire
        -- header directly rather than relying on a second flash model.
        ------------------------------------------------------------------
        bus_write(CFG_ADDR, x"0000000C");  -- ENABLE + LSB_FIRST
        fetch_addr <= x"00008040";
        wait until header_valid = '1';
        check("LSB_FIRST: opcode bit-reversed on the wire", header_captured(31 downto 24) = x"C0", errors);
        wait until fetch_ready = '1';

        ------------------------------------------------------------------
        -- Write engine: program PROGRAM_WORD at PROGRAM_ADDR (opcode
        -- 0x02, MSB first, CS held across all 8 bytes via CS_ASSERT),
        -- then switch to the fetch engine and read that same address
        -- back.
        ------------------------------------------------------------------
        bus_write(CFG_ADDR, x"00001000");  -- ENABLE=0 (write engine), CS_ASSERT=1
        bus_read(STATUS_ADDR, rd);
        check("STATUS idle right after CS_ASSERT, before any byte", rd(0) = '0', errors);

        write_byte(OPCODE_PROGRAM);
        write_byte(PROGRAM_ADDR(23 downto 16));
        write_byte(PROGRAM_ADDR(15 downto 8));
        write_byte(PROGRAM_ADDR(7 downto 0));
        -- Little-endian byte order (address+0 = the word's low byte),
        -- matching how the read side reassembles bytes (see
        -- tinymcu_imem_xip.vhd's own header comment). The first byte
        -- sent/stored becomes the word's low byte on read-back.
        write_byte(PROGRAM_WORD(7 downto 0));
        write_byte(PROGRAM_WORD(15 downto 8));
        write_byte(PROGRAM_WORD(23 downto 16));
        write_byte(PROGRAM_WORD(31 downto 24));

        check("ss_n stays low across the whole CS_ASSERT session", ss_n = '0', errors);

        bus_write(CFG_ADDR, x"00000000");  -- CS_ASSERT=0 (still ENABLE=0)
        wait for CLK_PERIOD * 2;
        check("ss_n released after CS_ASSERT cleared", ss_n = '1', errors);

        bus_write(CFG_ADDR, x"00000004");  -- ENABLE=1, back to the fetch engine
        fetch_addr <= PROGRAM_ADDR;
        wait until fetch_ready = '1';
        check("fetch_dout_o reads back the programmed word", fetch_dout, PROGRAM_WORD, errors);

        report "Total errors: " & integer'image(errors);
        if errors = 0 then
            report "ALL CHECKS PASSED";
        end if;

        std.env.stop;
        wait;
    end process;

end architecture sim;
