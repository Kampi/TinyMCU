--------------------------------------------------------------------------------
-- SPDX-License-Identifier: GPL-3.0-or-later
--
-- Company:
-- Engineer: Daniel Kampert
--
-- Create Date: 14.06.2026
-- Design Name: TinyMCU
-- Module Name: tinymcu_cpu_alu - tinymcu_cpu_alu_rtl
-- Project Name: TinyMCU
-- Description:
--   ALU for the CPU core.
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

entity tinymcu_cpu_alu is
    port (
        op_a   : in  word_t;
        op_b   : in  word_t;
        alu_op : in  std_ulogic_vector(14 downto 0);
        result : out word_t
    );
end entity tinymcu_cpu_alu;

architecture tinymcu_cpu_alu_rtl of tinymcu_cpu_alu is

    signal shamt : integer range 0 to 31;

    -- Carry-less (XOR/polynomial, GF(2)) multiplication, full 64-bit product; CLMUL/CLMULH/
    -- CLMULR each take a different 32-bit slice of this same result (see their case branches
    -- below), so it's one shared function instead of the same loop three times over.
    --   a, b - the two 32-bit operands (op_a/op_b); order matters only in that a's bits select
    --          which shifted copies of b get XORed in, not for the result itself (carry-less
    --          multiplication is commutative, same as ordinary multiplication).
    -- Returns: the full 64-bit carry-less product of a and b.
    function clmul_full(a, b : std_ulogic_vector) return std_ulogic_vector is
        variable prod : std_ulogic_vector(63 downto 0) := (others => '0');
    begin
        for i in 0 to 31 loop
            if a(i) = '1' then
                prod := prod xor std_ulogic_vector(shift_left(resize(unsigned(b), 64), i));
            end if;
        end loop;
        return prod;
    end function;

    -- CLZ/CTZ/CPOP (see ALU_CLZ/ALU_CTZ/ALU_CPOP): none of these have a ready-made numeric_std
    -- function, so a small loop each. All three take the same single parameter:
    --   v - the value to count/scan (always op_a for these, since CLZ/CTZ/CPOP are unary, op_b
    --       is unused).

    -- Counts leading zero bits, scanning from v's highest-indexed bit down towards v's
    -- lowest-indexed bit.
    -- Returns: the number of zero bits before the first '1' bit; v'length (not v'length - 1) if
    -- v is entirely zero.
    function count_leading_zeros(v : std_ulogic_vector) return integer is
    begin
        for i in v'high downto v'low loop
            if v(i) = '1' then
                return v'high - i;
            end if;
        end loop;
        return v'length;
    end function;

    -- Counts trailing zero bits, scanning from v's lowest-indexed bit up towards v's
    -- highest-indexed bit.
    -- Returns: the number of zero bits before the first '1' bit; v'length if v is entirely zero.
    function count_trailing_zeros(v : std_ulogic_vector) return integer is
    begin
        for i in v'low to v'high loop
            if v(i) = '1' then
                return i - v'low;
            end if;
        end loop;
        return v'length;
    end function;

    -- Counts how many bits of v are set, regardless of position or v's own index range.
    -- Returns: the number of '1' bits in v, from 0 to v'length.
    function popcount(v : std_ulogic_vector) return integer is
        variable cnt : integer := 0;
    begin
        for i in v'range loop
            if v(i) = '1' then
                cnt := cnt + 1;
            end if;
        end loop;
        return cnt;
    end function;

begin

    shamt <= to_integer(unsigned(op_b(4 downto 0)));

    process (op_a, op_b, alu_op, shamt)
        variable a_s, b_s : signed(31 downto 0);
        variable a_u, b_u : unsigned(31 downto 0);
    begin
        a_s := signed(op_a);
        b_s := signed(op_b);
        a_u := unsigned(op_a);
        b_u := unsigned(op_b);

        case alu_op is
            when ALU_ADD    => result <= std_ulogic_vector(a_s + b_s);
            when ALU_SUB    => result <= std_ulogic_vector(a_s - b_s);
            when ALU_SLL    => result <= std_ulogic_vector(shift_left(a_u, shamt));
            when ALU_SRL    => result <= std_ulogic_vector(shift_right(a_u, shamt));
            when ALU_SRA    => result <= std_ulogic_vector(shift_right(a_s, shamt));
            when ALU_AND    => result <= op_a and op_b;
            when ALU_OR     => result <= op_a or op_b;
            when ALU_XOR    => result <= op_a xor op_b;
            when ALU_ANDN   => result <= op_a and not op_b;
            when ALU_BCLR   => result <= op_a and not std_ulogic_vector(shift_left(to_unsigned(1, 32), shamt));
            when ALU_SH1ADD => result <= std_ulogic_vector(b_u + shift_left(a_u, 1));
            when ALU_SH2ADD => result <= std_ulogic_vector(b_u + shift_left(a_u, 2));
            when ALU_SH3ADD => result <= std_ulogic_vector(b_u + shift_left(a_u, 3));
            when ALU_ORN    => result <= op_a or not op_b;
            when ALU_XNOR   => result <= not (op_a xor op_b);
            when ALU_MIN    => result <= op_a when (a_s < b_s) else op_b;
            when ALU_MINU   => result <= op_a when (a_u < b_u) else op_b;
            when ALU_MAX    => result <= op_a when (a_s > b_s) else op_b;
            when ALU_MAXU   => result <= op_a when (a_u > b_u) else op_b;
            when ALU_ROL    => result <= std_ulogic_vector(shift_left(a_u, shamt)) or std_ulogic_vector(shift_right(a_u, 32 - shamt));
            when ALU_ROR    => result <= std_ulogic_vector(shift_right(a_u, shamt)) or std_ulogic_vector(shift_left(a_u, 32 - shamt));
            when ALU_CLMUL  => result <= clmul_full(op_a, op_b)(31 downto 0);
            when ALU_CLMULH => result <= clmul_full(op_a, op_b)(63 downto 32);
            when ALU_CLMULR => result <= clmul_full(op_a, op_b)(62 downto 31);
            when ALU_BSET   => result <= op_a or std_ulogic_vector(shift_left(to_unsigned(1, 32), shamt));
            when ALU_BINV   => result <= op_a xor std_ulogic_vector(shift_left(to_unsigned(1, 32), shamt));
            when ALU_BEXT   => result <= (0 => op_a(shamt), others => '0');
            when ALU_CLZ    => result <= std_ulogic_vector(to_unsigned(count_leading_zeros(op_a), 32));
            when ALU_CTZ    => result <= std_ulogic_vector(to_unsigned(count_trailing_zeros(op_a), 32));
            when ALU_CPOP   => result <= std_ulogic_vector(to_unsigned(popcount(op_a), 32));
            when ALU_SEXTB  => result <= sext(op_a(7 downto 0), 32);
            when ALU_SEXTH  => result <= sext(op_a(15 downto 0), 32);
            when ALU_SLT    =>
                if a_s < b_s then
                    result <= (0 => '1', others => '0');
                else
                    result <= (others => '0');
                end if;
            when ALU_SLTU   =>
                if a_u < b_u then
                    result <= (0 => '1', others => '0');
                else
                    result <= (others => '0');
                end if;
            when ALU_PASSB  => result <= op_b;
            when others     => result <= (others => '0');
        end case;
    end process;

end architecture tinymcu_cpu_alu_rtl;
