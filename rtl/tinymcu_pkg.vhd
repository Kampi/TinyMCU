--------------------------------------------------------------------------------
-- SPDX-License-Identifier: GPL-3.0-or-later
--
-- Company:
-- Engineer: Daniel Kampert
--
-- Create Date: 14.06.2026
-- Design Name: TinyMCU
-- Module Name: tinymcu_pkg
-- Project Name: TinyMCU
-- Description:
--   Shared types, memory-map constants, opcode/ALU-op/CSR-op/interrupt-
--   bit encodings, and helper functions (bit manipulation, simulation-
--   only disassembly) for the TinyMCU core.
--
-- Dependencies:
--   none
--
-- Additional Comments:
--
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package tinymcu_pkg is

    subtype word_t is std_ulogic_vector(31 downto 0);

    type reg_array_t is array (0 to 31) of word_t;
    type mem_array_t is array (natural range <>) of word_t;

    type bus_req_t is record
        addr    : word_t;                           -- Byte address
        data    : word_t;                           -- Write data
        ben     : std_ulogic_vector(3 downto 0);    -- Byte enable
        we      : std_ulogic;                       -- '1' = write, '0' = read
        stb     : std_ulogic;                       -- '1' = valid access this cycle
    end record;

    type bus_rsp_t is record
        data    : word_t;                           -- Read data, valid when ack = '1'
        ack     : std_ulogic;                       -- '1' = access completed this cycle
        err     : std_ulogic;                       -- '1' = when a generic error occurs
    end record;

    -- CSR default values
    constant MVENDORID : std_ulogic_vector(31 downto 0) := (others => '0');
    constant MARCHID   : std_ulogic_vector(31 downto 0) := (others => '0');

    -- TINYMCU_MIMPID_BEGIN (auto-generated, do not edit by hand)
    constant MIMPID : std_ulogic_vector(31 downto 0) := x"00000000";
    -- TINYMCU_MIMPID_END

    constant ROM_BASE           : word_t := x"00000000";
    constant ROM_END            : word_t := x"00001000";
    constant FLASH_BASE         : word_t := x"00001000";
    constant FLASH_END          : word_t := x"01000000";
    constant RAM_BASE           : word_t := x"02000000";
    constant RAM_END            : word_t := x"03000000";
    constant PERIPHERALS_BASE   : word_t := x"04000000";
    constant PERIPHERALS_END    : word_t := x"05000000";

    -- tinymcu_periph.vhd's peripheral sub-ranges, within the
    -- PERIPHERALS_BASE..PERIPHERALS_END window above.
    constant GPIO_BASE      : word_t := x"04000000";
    constant GPIO_END       : word_t := x"040000FF";
    constant TIMER_BASE     : word_t := x"04000100";
    constant TIMER_END      : word_t := x"040001FF";

    -- Opcodes (instr(6 downto 0))
    constant OPC_OP32       : std_ulogic_vector(6 downto 0) := "0111011";       -- 32-bit operations. Not implemented.
    constant OPC_OP         : std_ulogic_vector(6 downto 0) := "0110011";       -- R-type ALU
    constant OPC_OPIMM      : std_ulogic_vector(6 downto 0) := "0010011";       -- I-type ALU
    constant OPC_LUI        : std_ulogic_vector(6 downto 0) := "0110111";       -- U-type
    constant OPC_BRANCH     : std_ulogic_vector(6 downto 0) := "1100011";       -- B-type
    constant OPC_JAL        : std_ulogic_vector(6 downto 0) := "1101111";       -- J-type
    constant OPC_JALR       : std_ulogic_vector(6 downto 0) := "1100111";       -- I-type
    constant OPC_LOAD       : std_ulogic_vector(6 downto 0) := "0000011";       -- I-type (LW)
    constant OPC_STORE      : std_ulogic_vector(6 downto 0) := "0100011";       -- S-type (SW)
    constant OPC_AUIPC      : std_ulogic_vector(6 downto 0) := "0010111";       -- U-type
    constant OPC_SYSTEM     : std_ulogic_vector(6 downto 0) := "1110011";       -- I-type (CSR*, ECALL/EBREAK/MRET/WFI)

    -- SYSTEM funct3: selects the CSR operation.
    -- funct3 = "000" is not a CSR access at all
    constant CSR_RW  : std_ulogic_vector(2 downto 0) := "001";                  -- rd = csr; csr = rs1
    constant CSR_RS  : std_ulogic_vector(2 downto 0) := "010";                  -- rd = csr; csr = csr or rs1
    constant CSR_RC  : std_ulogic_vector(2 downto 0) := "011";                  -- rd = csr; csr = csr and not rs1
    constant CSR_RWI : std_ulogic_vector(2 downto 0) := "101";                  -- like CSR_RW, but a 5-bit zero-extended immediate instead of rs1
    constant CSR_RSI : std_ulogic_vector(2 downto 0) := "110";                  -- like CSR_RS, but a 5-bit zero-extended immediate instead of rs1
    constant CSR_RCI : std_ulogic_vector(2 downto 0) := "111";                  -- like CSR_RC, but a 5-bit zero-extended immediate instead of rs1

    -- Standard M-mode interrupt bit positions, shared by mstatus (the
    -- MIE bit only lives at bit 3, there's no per-source enable there;
    -- MSIE/MTIE/MEIE instead live in mie), mie, and mip. Used by
    -- tinymcu_cpu.vhd's is_trap and tinymcu_cpu_csrfile.vhd's mip_live
    -- so both stay in sync on where each source's bit actually is.
    constant IRQ_MSI_BIT : integer := 3;                                        -- Software interrupt
    constant IRQ_MTI_BIT : integer := 7;                                        -- Timer interrupt
    constant IRQ_MEI_BIT : integer := 11;                                       -- External interrupt

    -- ALU operations.
    --
    -- Format: funct7(6 downto 0) & funct3(2 downto 0) & subfunc(4 downto 0)
    --
    -- funct7/funct3 are the R-type instruction's own fields (see tinymcu_cpu_control.vhd's
    -- "ALU operand and operation selection").
    --
    -- subfunc is instr(24 downto 20) (the rs2 position) only when opcode=OPC_OPIMM,
    -- funct3="001", funct7="0110000" -- the one funct7/funct3 pair RV32B reuses for five
    -- different unary ops (CLZ/CTZ/CPOP/SEXT.B/SEXT.H below), only distinguished by that
    -- field, not by any real rs2 register.
    --
    -- Everywhere else, subfunc is forced to the sentinel "11111", including ROL, which happens
    -- to share that same funct7/funct3 pair under OPC_OP, where instr(24 downto 20) IS a genuine
    -- rs2 register number and must NOT affect alu_op (or "rol x1,x2,x3" and "rol x1,x2,x4" would
    -- wrongly decode as different operations). "11111" is safe as the sentinel since none of the
    -- five real subfunc values below ever reach that high.
    constant ALU_ADD    : std_ulogic_vector(14 downto 0) := "0000000" & "000" & "11111";  -- funct7 0000000, funct3 000; result = op_a + op_b (two's complement)
    constant ALU_SLL    : std_ulogic_vector(14 downto 0) := "0000000" & "001" & "11111";  -- funct7 0000000, funct3 001; result = op_a << op_b(4 downto 0)               (logical left shift)
    constant ALU_SLT    : std_ulogic_vector(14 downto 0) := "0000000" & "010" & "11111";  -- funct7 0000000, funct3 010; result = 1 if op_a < op_b (signed)   else 0     (set-less-than)
    constant ALU_SLTU   : std_ulogic_vector(14 downto 0) := "0000000" & "011" & "11111";  -- funct7 0000000, funct3 011; result = 1 if op_a < op_b (unsigned) else 0     (set-less-than unsigned)
    constant ALU_XOR    : std_ulogic_vector(14 downto 0) := "0000000" & "100" & "11111";  -- funct7 0000000, funct3 100; result = op_a xor op_b                          (bitwise XOR)
    constant ALU_SRL    : std_ulogic_vector(14 downto 0) := "0000000" & "101" & "11111";  -- funct7 0000000, funct3 101; result = op_a >> op_b(4 downto 0)  (unsigned)   (logical right shift, zero-fill)
    constant ALU_OR     : std_ulogic_vector(14 downto 0) := "0000000" & "110" & "11111";  -- funct7 0000000, funct3 110; result = op_a or op_b                           (bitwise OR)
    constant ALU_AND    : std_ulogic_vector(14 downto 0) := "0000000" & "111" & "11111";  -- funct7 0000000, funct3 111; result = op_a and op_b                          (bitwise AND)
    constant ALU_SUB    : std_ulogic_vector(14 downto 0) := "0100000" & "000" & "11111";  -- funct7 0100000, funct3 000; result = op_a - op_b (two's complement)
    constant ALU_SRA    : std_ulogic_vector(14 downto 0) := "0100000" & "101" & "11111";  -- funct7 0100000, funct3 101; result = op_a >> op_b(4 downto 0)  (signed)  (arithmetic right shift, sign-fill)
    constant ALU_ANDN   : std_ulogic_vector(14 downto 0) := "0100000" & "111" & "11111";  -- funct7 0100000, funct3 111; result = op_a and not op_b
    constant ALU_BCLR   : std_ulogic_vector(14 downto 0) := "0100100" & "001" & "11111";  -- funct7 0100100, funct3 001; result = op_a and not (1 << op_b(4 downto 0))            (Zbs BCLR/BCLRI)
    constant ALU_SH1ADD : std_ulogic_vector(14 downto 0) := "0010000" & "010" & "11111";  -- funct7 0010000, funct3 010; result = (op_a << 1) + op_b                             (Zba)
    constant ALU_SH2ADD : std_ulogic_vector(14 downto 0) := "0010000" & "100" & "11111";  -- funct7 0010000, funct3 100; result = (op_a << 2) + op_b                             (Zba)
    constant ALU_SH3ADD : std_ulogic_vector(14 downto 0) := "0010000" & "110" & "11111";  -- funct7 0010000, funct3 110; result = (op_a << 3) + op_b                             (Zba)
    constant ALU_ORN    : std_ulogic_vector(14 downto 0) := "0100000" & "110" & "11111";  -- funct7 0100000, funct3 110; result = op_a or not op_b                               (Zbb)
    constant ALU_XNOR   : std_ulogic_vector(14 downto 0) := "0100000" & "100" & "11111";  -- funct7 0100000, funct3 100; result = op_a xnor op_b                                 (Zbb)
    constant ALU_MIN    : std_ulogic_vector(14 downto 0) := "0000101" & "100" & "11111";  -- funct7 0000101, funct3 100; result = min(op_a, op_b)             (signed)          (Zbb)
    constant ALU_MINU   : std_ulogic_vector(14 downto 0) := "0000101" & "101" & "11111";  -- funct7 0000101, funct3 101; result = min(op_a, op_b)             (unsigned)        (Zbb)
    constant ALU_MAX    : std_ulogic_vector(14 downto 0) := "0000101" & "110" & "11111";  -- funct7 0000101, funct3 110; result = max(op_a, op_b)             (signed)          (Zbb)
    constant ALU_MAXU   : std_ulogic_vector(14 downto 0) := "0000101" & "111" & "11111";  -- funct7 0000101, funct3 111; result = max(op_a, op_b)             (unsigned)        (Zbb)
    constant ALU_ROL    : std_ulogic_vector(14 downto 0) := "0110000" & "001" & "11111";  -- funct7 0110000, funct3 001; result = op_a rotated left  by op_b(4 downto 0)        (Zbb; OPC_OP, subfunc forced to the sentinel, see comment above)
    constant ALU_ROR    : std_ulogic_vector(14 downto 0) := "0110000" & "101" & "11111";  -- funct7 0110000, funct3 101; result = op_a rotated right by op_b(4 downto 0)        (Zbb; also RORI)
    constant ALU_CLMUL  : std_ulogic_vector(14 downto 0) := "0000101" & "001" & "11111";  -- funct7 0000101, funct3 001; result = carry-less product of op_a, op_b (low half)   (Zbc)
    constant ALU_CLMULR : std_ulogic_vector(14 downto 0) := "0000101" & "010" & "11111";  -- funct7 0000101, funct3 010; result = carry-less product, bit-reversed             (Zbc)
    constant ALU_CLMULH : std_ulogic_vector(14 downto 0) := "0000101" & "011" & "11111";  -- funct7 0000101, funct3 011; result = carry-less product of op_a, op_b (high half)  (Zbc)
    constant ALU_BSET   : std_ulogic_vector(14 downto 0) := "0010100" & "001" & "11111";  -- funct7 0010100, funct3 001; result = op_a or (1 << op_b(4 downto 0))               (Zbs; also BSETI)
    constant ALU_BINV   : std_ulogic_vector(14 downto 0) := "0110100" & "001" & "11111";  -- funct7 0110100, funct3 001; result = op_a xor (1 << op_b(4 downto 0))              (Zbs; also BINVI)
    constant ALU_BEXT   : std_ulogic_vector(14 downto 0) := "0100100" & "101" & "11111";  -- funct7 0100100, funct3 101; result = (op_a >> op_b(4 downto 0)) and 1              (Zbs; also BEXTI)

    -- OPC_OPIMM, funct3 001, funct7 0110000: five unary ops distinguished
    -- only by subfunc = instr(24 downto 20) (see the comment above). All
    -- ignore op_b entirely (there's no rs2 register here at all).
    constant ALU_CLZ    : std_ulogic_vector(14 downto 0) := "0110000" & "001" & "00000";  -- result = number of leading zero bits in op_a (32 if op_a = 0)                      (Zbb)
    constant ALU_CTZ    : std_ulogic_vector(14 downto 0) := "0110000" & "001" & "00001";  -- result = number of trailing zero bits in op_a (32 if op_a = 0)                     (Zbb)
    constant ALU_CPOP   : std_ulogic_vector(14 downto 0) := "0110000" & "001" & "00010";  -- result = number of set bits in op_a                                               (Zbb)
    constant ALU_SEXTB  : std_ulogic_vector(14 downto 0) := "0110000" & "001" & "00100";  -- result = op_a(7 downto 0), sign-extended to 32 bits                               (Zbb)
    constant ALU_SEXTH  : std_ulogic_vector(14 downto 0) := "0110000" & "001" & "00101";  -- result = op_a(15 downto 0), sign-extended to 32 bits                              (Zbb)

    constant ALU_PASSB  : std_ulogic_vector(14 downto 0) := "111111111111111";  -- sentinel, not a real funct7/funct3/subfunc combination; only for LUI; result = op_b (unmodified passthrough)
                                                                                -- (any other, unassigned code defaults to result = 0 via the "when others" branch in tinymcu_cpu_alu.vhd)

    -- Selection of the first ALU operand
    constant CONST_ALU_SELECT_REG   : std_ulogic := '0';                        -- rs1
    constant CONST_ALU_SELECT_PC    : std_ulogic := '1';                        -- Program counter

    -- Selection of the second ALU operand
    constant OPB_REG    : std_ulogic_vector(2 downto 0) := "000";               -- rs2
    constant OPB_IMM_I  : std_ulogic_vector(2 downto 0) := "001";               -- Immediate from I-group
    constant OPB_IMM_S  : std_ulogic_vector(2 downto 0) := "010";               -- Immediate from S-group
    constant OPB_IMM_U  : std_ulogic_vector(2 downto 0) := "011";               -- Immediate from U-group
    constant OPB_CONST4 : std_ulogic_vector(2 downto 0) := "100";               -- For jump / branch instructions

    -- Canonical NOP: ADDI x0, x0, 0
    constant NOP_INSTR : word_t := x"00000013";

    constant BUS_REQ_IDLE : bus_req_t := (
        addr => (others => '0'),
        data => (others => '0'),
        ben  => (others => '0'),
        we   => '0',
        stb  => '0'
    );

    constant BUS_RSP_IDLE : bus_rsp_t := (
        data => (others => '0'),
        ack  => '0',
        err => '0'
    );

    -- Sign-extends v out to width bits, replicating v's sign bit into all the new upper bits.
    --   v     - the value to extend; its highest-indexed bit is treated as the sign bit,
    --           regardless of v's own index range.
    --   width - the result's width in bits (must be >= v'length).
    -- Returns: v, sign-extended to width bits.
    -- Used throughout tinymcu_cpu_control.vhd for the I/S/B/J immediates and by
    -- tinymcu_cpu_alu.vhd's SEXT.B/SEXT.H (Zbb), which just sext() a narrower slice of op_a.
    function sext(v : std_ulogic_vector; width : integer) return std_ulogic_vector;

    -- Per-byte write-enable merge: for each byte lane i where ben(i) = '1', takes that byte
    -- from new_v, otherwise keeps old_v's byte.
    --   old_v, new_v - the two values being merged; not tied to word_t or a fixed 4-lane ben,
    --                  may be any width that's a whole multiple of 8 bits.
    --   ben          - one bit per byte lane, i.e. exactly old_v'length/8 bits wide.
    -- Returns: old_v with the ben-selected byte lanes replaced by new_v's, same width as
    -- old_v/new_v.
    -- e.g. tinymcu_periph_gpio.vhd's 32-bit registers via a 4-bit ben, but just as usable for a
    -- narrower or wider register elsewhere.
    function byte_merge(old_v, new_v : std_ulogic_vector; ben : std_ulogic_vector) return std_ulogic_vector;

    -- Simulation-only helper: Used by tinymcu_cpu.vhd's optional trace generate block and by
    -- the testbenches' check()/report messages.
    --   v - the word to format as an 8-digit uppercase hex string.
    -- Returns: v as an 8-character uppercase hex string, no "0x" prefix (callers that want one
    -- prepend it themselves, e.g. to_hex(...) is usually written "0x" & to_hex(v) at the call
    -- site).
    -- Hand-rolled instead of to_hstring(): XSIM's IEEE library does not reliably expose the
    -- VHDL-2008 std_ulogic_vector overload of to_hstring (std_logic_1164); it resolves to a
    -- bit_vector overload instead and rejects word_t.
    function to_hex(v : word_t) return string;

    -- Simulation-only helper: Decodes one instruction word into a RV32I (plus the implemented
    -- RV32B subset) mnemonic with ABI register names (matches objdump's default style, so it's
    -- directly comparable against a sw/*/build/main.lst).
    --   pc    - the instruction's own address; needed (not just instr) to print absolute
    --           branch/jump targets instead of raw offsets.
    --   instr - the raw 32-bit instruction word to decode.
    -- Returns: the decoded mnemonic and operands as one string (ABI register names,
    -- column-padded to line up like objdump's output), or ".word 0x<instr>" for anything not
    -- decoded (see below).
    -- Only covers what tinymcu_cpu_control.vhd/tinymcu_cpu_alu.vhd actually implement (see
    -- README.md "Extensions": no CSR/FENCE/ECALL/EBREAK, no ORC.B/REV8); anything else, and any
    -- opcode this core doesn't implement, falls back to ".word 0x...".
    function disassemble(pc : word_t; instr : word_t) return string;

end package tinymcu_pkg;

package body tinymcu_pkg is

    function sext(v : std_ulogic_vector; width : integer) return std_ulogic_vector is
        -- Normalize v to a 0-based range first: GHDL (mcode, 1.0.0) mis-indexes
        -- v(v'high) when v is bound to a multi-slice concatenation actual
        -- (e.g. instr(31 downto 25) & instr(11 downto 7)) passed directly to
        -- this unconstrained formal; it silently reads the wrong bit. Taking
        -- a normalized copy first avoids the bug.
        variable vn     : std_ulogic_vector(v'length - 1 downto 0) := v;
        variable result : std_ulogic_vector(width - 1 downto 0) := (others => vn(vn'high));
    begin
        result(vn'length - 1 downto 0) := vn;
        return result;
    end function;

    function byte_merge(old_v, new_v : std_ulogic_vector; ben : std_ulogic_vector) return std_ulogic_vector is
        -- Normalize to 0-based ranges first, same reasoning as sext() above.
        variable ov     : std_ulogic_vector(old_v'length - 1 downto 0) := old_v;
        variable nv     : std_ulogic_vector(new_v'length - 1 downto 0) := new_v;
        variable bv     : std_ulogic_vector(ben'length - 1 downto 0) := ben;
        variable result : std_ulogic_vector(old_v'length - 1 downto 0);
    begin
        for i in 0 to bv'length - 1 loop
            if bv(i) = '1' then
                result((i * 8) + 7 downto i * 8) := nv((i * 8) + 7 downto i * 8);
            else
                result((i * 8) + 7 downto i * 8) := ov((i * 8) + 7 downto i * 8);
            end if;
        end loop;
        return result;
    end function;

    function to_hex(v : word_t) return string is
        constant hex_chars : string(1 to 16) := "0123456789ABCDEF";
        variable result : string(1 to 8);
    begin
        for i in 0 to 7 loop
            result(i + 1) := hex_chars(to_integer(unsigned(v(31 - i * 4 downto 28 - i * 4))) + 1);
        end loop;
        return result;
    end function;

    function disassemble(pc : word_t; instr : word_t) return string is
        -- Maps a 5-bit register number to its ABI name (see README.md's "Register (ABI) Names"),
        -- for disassemble()'s operand formatting.
        --   r - the register number (instr's rd/rs1/rs2 field).
        -- Returns: the register's ABI name, e.g. "zero", "ra", "t0".
        function reg_name(r : std_ulogic_vector(4 downto 0)) return string is
        begin
            case r is
                when "00000" => return "zero";
                when "00001" => return "ra";
                when "00010" => return "sp";
                when "00011" => return "gp";
                when "00100" => return "tp";
                when "00101" => return "t0";
                when "00110" => return "t1";
                when "00111" => return "t2";
                when "01000" => return "s0";
                when "01001" => return "s1";
                when "01010" => return "a0";
                when "01011" => return "a1";
                when "01100" => return "a2";
                when "01101" => return "a3";
                when "01110" => return "a4";
                when "01111" => return "a5";
                when "10000" => return "a6";
                when "10001" => return "a7";
                when "10010" => return "s2";
                when "10011" => return "s3";
                when "10100" => return "s4";
                when "10101" => return "s5";
                when "10110" => return "s6";
                when "10111" => return "s7";
                when "11000" => return "s8";
                when "11001" => return "s9";
                when "11010" => return "s10";
                when "11011" => return "s11";
                when "11100" => return "t3";
                when "11101" => return "t4";
                when "11110" => return "t5";
                when others  => return "t6";
            end case;
        end function;

        -- Formats a word as a signed decimal string, for disassemble()'s immediate operand
        -- formatting (objdump prints RV32I immediates in decimal, not hex).
        --   v - the word to format, interpreted as two's-complement signed.
        -- Returns: v's value as a signed decimal string, e.g. "-5", "42".
        function to_dec(v : word_t) return string is
        begin
            return integer'image(to_integer(signed(v)));
        end function;

        variable opcode : std_ulogic_vector(6 downto 0) := instr(6 downto 0);
        variable rd     : std_ulogic_vector(4 downto 0) := instr(11 downto 7);
        variable rs1    : std_ulogic_vector(4 downto 0) := instr(19 downto 15);
        variable rs2    : std_ulogic_vector(4 downto 0) := instr(24 downto 20);
        variable funct3 : std_ulogic_vector(2 downto 0) := instr(14 downto 12);
        variable funct7 : std_ulogic_vector(6 downto 0) := instr(31 downto 25);

        variable imm_i : word_t := sext(instr(31 downto 20), 32);
        variable imm_s : word_t := sext(instr(31 downto 25) & instr(11 downto 7), 32);
        variable imm_b : word_t := sext(instr(31) & instr(7) & instr(30 downto 25) & instr(11 downto 8) & '0', 32);
        variable imm_j : word_t := sext(instr(31) & instr(19 downto 12) & instr(20) & instr(30 downto 21) & '0', 32);
        variable shamt : word_t := std_ulogic_vector(resize(unsigned(instr(24 downto 20)), 32));

        variable target : word_t;

    begin
        if instr = NOP_INSTR then
            return "nop";
        end if;

        case opcode is
            -- Both OPC_OP and OPC_OPIMM check the full funct7 (not just
            -- bit 5, as base RV32I alone would need) to also recognize
            -- the RV32B ops that reuse a base funct3 with a different
            -- funct7 -- see tinymcu_pkg.vhd's ALU_* constants, which use
            -- the exact same funct7/funct3 pairs. instr(24 downto 20) is
            -- NOT decoded here (e.g. CLZ vs. CTZ vs. CPOP), since those
            -- aren't implemented (see README.md's "Extensions"); they
            -- still fall through to ".word 0x...".
            when OPC_OP =>
                case funct3 is
                    when "000" =>
                        if funct7 = "0100000" then
                            return "sub    " & reg_name(rd) & "," & reg_name(rs1) & "," & reg_name(rs2);
                        else
                            return "add    " & reg_name(rd) & "," & reg_name(rs1) & "," & reg_name(rs2);
                        end if;
                    when "001" =>
                        case funct7 is
                            when "0110000" => return "rol    " & reg_name(rd) & "," & reg_name(rs1) & "," & reg_name(rs2);
                            when "0010100" => return "bset   " & reg_name(rd) & "," & reg_name(rs1) & "," & reg_name(rs2);
                            when "0110100" => return "binv   " & reg_name(rd) & "," & reg_name(rs1) & "," & reg_name(rs2);
                            when "0100100" => return "bclr   " & reg_name(rd) & "," & reg_name(rs1) & "," & reg_name(rs2);
                            when "0000101" => return "clmul  " & reg_name(rd) & "," & reg_name(rs1) & "," & reg_name(rs2);
                            when others    => return "sll    " & reg_name(rd) & "," & reg_name(rs1) & "," & reg_name(rs2);
                        end case;
                    when "010" =>
                        case funct7 is
                            when "0010000" => return "sh1add " & reg_name(rd) & "," & reg_name(rs1) & "," & reg_name(rs2);
                            when "0000101" => return "clmulr " & reg_name(rd) & "," & reg_name(rs1) & "," & reg_name(rs2);
                            when others    => return "slt    " & reg_name(rd) & "," & reg_name(rs1) & "," & reg_name(rs2);
                        end case;
                    when "011" =>
                        if funct7 = "0000101" then
                            return "clmulh " & reg_name(rd) & "," & reg_name(rs1) & "," & reg_name(rs2);
                        else
                            return "sltu   " & reg_name(rd) & "," & reg_name(rs1) & "," & reg_name(rs2);
                        end if;
                    when "100" =>
                        case funct7 is
                            when "0100000" => return "xnor   " & reg_name(rd) & "," & reg_name(rs1) & "," & reg_name(rs2);
                            when "0000101" => return "min    " & reg_name(rd) & "," & reg_name(rs1) & "," & reg_name(rs2);
                            when "0010000" => return "sh2add " & reg_name(rd) & "," & reg_name(rs1) & "," & reg_name(rs2);
                            when others    => return "xor    " & reg_name(rd) & "," & reg_name(rs1) & "," & reg_name(rs2);
                        end case;
                    when "101" =>
                        case funct7 is
                            when "0100000" => return "sra    " & reg_name(rd) & "," & reg_name(rs1) & "," & reg_name(rs2);
                            when "0110000" => return "ror    " & reg_name(rd) & "," & reg_name(rs1) & "," & reg_name(rs2);
                            when "0000101" => return "minu   " & reg_name(rd) & "," & reg_name(rs1) & "," & reg_name(rs2);
                            when "0100100" => return "bext   " & reg_name(rd) & "," & reg_name(rs1) & "," & reg_name(rs2);
                            when others    => return "srl    " & reg_name(rd) & "," & reg_name(rs1) & "," & reg_name(rs2);
                        end case;
                    when "110" =>
                        case funct7 is
                            when "0100000" => return "orn    " & reg_name(rd) & "," & reg_name(rs1) & "," & reg_name(rs2);
                            when "0000101" => return "max    " & reg_name(rd) & "," & reg_name(rs1) & "," & reg_name(rs2);
                            when "0010000" => return "sh3add " & reg_name(rd) & "," & reg_name(rs1) & "," & reg_name(rs2);
                            when others    => return "or     " & reg_name(rd) & "," & reg_name(rs1) & "," & reg_name(rs2);
                        end case;
                    when others =>  -- "111"
                        case funct7 is
                            when "0100000" => return "andn   " & reg_name(rd) & "," & reg_name(rs1) & "," & reg_name(rs2);
                            when "0000101" => return "maxu   " & reg_name(rd) & "," & reg_name(rs1) & "," & reg_name(rs2);
                            when others    => return "and    " & reg_name(rd) & "," & reg_name(rs1) & "," & reg_name(rs2);
                        end case;
                end case;

            when OPC_OPIMM =>
                case funct3 is
                    when "000" => return "addi   " & reg_name(rd) & "," & reg_name(rs1) & "," & to_dec(imm_i);
                    when "010" => return "slti   " & reg_name(rd) & "," & reg_name(rs1) & "," & to_dec(imm_i);
                    when "011" => return "sltiu  " & reg_name(rd) & "," & reg_name(rs1) & "," & to_dec(imm_i);
                    when "100" => return "xori   " & reg_name(rd) & "," & reg_name(rs1) & "," & to_dec(imm_i);
                    when "110" => return "ori    " & reg_name(rd) & "," & reg_name(rs1) & "," & to_dec(imm_i);
                    when "111" => return "andi   " & reg_name(rd) & "," & reg_name(rs1) & "," & to_dec(imm_i);
                    when "001" =>
                        case funct7 is
                            when "0010100" => return "bseti  " & reg_name(rd) & "," & reg_name(rs1) & "," & to_dec(shamt);
                            when "0110100" => return "binvi  " & reg_name(rd) & "," & reg_name(rs1) & "," & to_dec(shamt);
                            when "0100100" => return "bclri  " & reg_name(rd) & "," & reg_name(rs1) & "," & to_dec(shamt);
                            -- funct7 0110000 here is the five CLZ/CTZ/CPOP/
                            -- SEXT.B/SEXT.H unary ops (not RORI, which is
                            -- funct3 101, same funct7 -- see the "others"
                            -- branch below), disambiguated by rs2/instr
                            -- (24 downto 20), same as ALU_CLZ etc.'s subfunc.
                            when "0110000" =>
                                case rs2 is
                                    when "00000" => return "clz    " & reg_name(rd) & "," & reg_name(rs1);
                                    when "00001" => return "ctz    " & reg_name(rd) & "," & reg_name(rs1);
                                    when "00010" => return "cpop   " & reg_name(rd) & "," & reg_name(rs1);
                                    when "00100" => return "sext.b " & reg_name(rd) & "," & reg_name(rs1);
                                    when "00101" => return "sext.h " & reg_name(rd) & "," & reg_name(rs1);
                                    when others  => return ".word 0x" & to_hex(instr);
                                end case;
                            when others    => return "slli   " & reg_name(rd) & "," & reg_name(rs1) & "," & to_dec(shamt);
                        end case;
                    when others =>  -- "101"
                        case funct7 is
                            when "0100000" => return "srai   " & reg_name(rd) & "," & reg_name(rs1) & "," & to_dec(shamt);
                            when "0110000" => return "rori   " & reg_name(rd) & "," & reg_name(rs1) & "," & to_dec(shamt);
                            when "0100100" => return "bexti  " & reg_name(rd) & "," & reg_name(rs1) & "," & to_dec(shamt);
                            when others    => return "srli   " & reg_name(rd) & "," & reg_name(rs1) & "," & to_dec(shamt);
                        end case;
                end case;

            when OPC_LOAD =>
                case funct3 is
                    when "000" => return "lb    " & reg_name(rd) & "," & to_dec(imm_i) & "(" & reg_name(rs1) & ")";
                    when "001" => return "lh    " & reg_name(rd) & "," & to_dec(imm_i) & "(" & reg_name(rs1) & ")";
                    when "010" => return "lw    " & reg_name(rd) & "," & to_dec(imm_i) & "(" & reg_name(rs1) & ")";
                    when "100" => return "lbu   " & reg_name(rd) & "," & to_dec(imm_i) & "(" & reg_name(rs1) & ")";
                    when others => return "lhu   " & reg_name(rd) & "," & to_dec(imm_i) & "(" & reg_name(rs1) & ")";
                end case;

            when OPC_STORE =>
                case funct3 is
                    when "000" => return "sb    " & reg_name(rs2) & "," & to_dec(imm_s) & "(" & reg_name(rs1) & ")";
                    when "001" => return "sh    " & reg_name(rs2) & "," & to_dec(imm_s) & "(" & reg_name(rs1) & ")";
                    when others => return "sw    " & reg_name(rs2) & "," & to_dec(imm_s) & "(" & reg_name(rs1) & ")";
                end case;

            when OPC_BRANCH =>
                target := std_ulogic_vector(unsigned(pc) + unsigned(imm_b));
                case funct3 is
                    when "000" => return "beq   " & reg_name(rs1) & "," & reg_name(rs2) & ",0x" & to_hex(target);
                    when "001" => return "bne   " & reg_name(rs1) & "," & reg_name(rs2) & ",0x" & to_hex(target);
                    when "100" => return "blt   " & reg_name(rs1) & "," & reg_name(rs2) & ",0x" & to_hex(target);
                    when "101" => return "bge   " & reg_name(rs1) & "," & reg_name(rs2) & ",0x" & to_hex(target);
                    when "110" => return "bltu  " & reg_name(rs1) & "," & reg_name(rs2) & ",0x" & to_hex(target);
                    when others => return "bgeu  " & reg_name(rs1) & "," & reg_name(rs2) & ",0x" & to_hex(target);
                end case;

            when OPC_LUI =>
                return "lui   " & reg_name(rd) & ",0x" & to_hex(instr(31 downto 12) & x"000");

            when OPC_AUIPC =>
                return "auipc " & reg_name(rd) & ",0x" & to_hex(instr(31 downto 12) & x"000");

            when OPC_JAL =>
                target := std_ulogic_vector(unsigned(pc) + unsigned(imm_j));
                return "jal   " & reg_name(rd) & ",0x" & to_hex(target);

            when OPC_JALR =>
                return "jalr  " & reg_name(rd) & "," & reg_name(rs1) & "," & to_dec(imm_i);

            when others =>
                return ".word 0x" & to_hex(instr);
        end case;
    end function;

end package body tinymcu_pkg;
