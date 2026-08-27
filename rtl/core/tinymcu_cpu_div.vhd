--------------------------------------------------------------------------------
-- SPDX-License-Identifier: GPL-3.0-or-later
--
-- Company:
-- Engineer: Daniel Kampert
--
-- Create Date: 14.06.2026
-- Design Name: TinyMCU
-- Module Name: tinymcu_cpu_div - tinymcu_cpu_div_rtl
-- Project Name: TinyMCU
-- Description:
--   Shift-Subtract divider unit for the TinyMCU.
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

entity tinymcu_cpu_div is
    port (
        -- Global control
        clk_i       : in  std_logic;
        rst_i       : in  std_logic;

        -- Data input
        op_a_i      : in  word_t;
        op_b_i      : in  word_t;

        -- Result
        quotient_o  : out word_t;
        remainder_o : out word_t;

        -- Status and control
        start_i     : in  std_ulogic;
        busy_o      : out std_ulogic;
        valid_o     : out std_ulogic;
        funct3_i    : in  std_ulogic_vector(2 downto 0)
    );
end entity tinymcu_cpu_div;

architecture tinymcu_cpu_div_rtl of tinymcu_cpu_div is

    type Div_State_t is (Idle, Check, Calc);

    signal start            : std_ulogic;
    signal neg_result       : std_ulogic;
    signal neg_remainder    : std_ulogic;

    signal dividend         : word_t;
    signal divisor          : word_t; 
    signal quotient         : std_ulogic_vector((op_a_i'length - 1) downto 0);
    signal rem_work         : unsigned(op_a_i'length downto 0);

    signal quotient_corr    : std_ulogic_vector((op_a_i'length - 1) downto 0);
    signal remainder_corr   : std_ulogic_vector((op_a_i'length - 1) downto 0);

    signal current_state    : Div_State_t := Idle;

begin

    process(clk_i)
        variable cycles         : integer range 0 to op_a_i'length;
        variable sign_a         : std_ulogic;
        variable sign_b         : std_ulogic;
        variable trial          : unsigned(op_a_i'length downto 0);
        variable divisor_ext    : unsigned(op_a_i'length downto 0);
    begin
        if rising_edge(clk_i) then
            if rst_i = '1' then
                cycles := 0;

                dividend <= (others => '0');
                divisor <= (others => '0');
                quotient <= (others => '0');
                rem_work <= (others => '0');
                neg_result <= '0';
                neg_remainder <= '0';
                start <= '0';
                current_state <= Idle;
            else
                case current_state is
                    when Idle =>
                        cycles := 0;

                        start <= start_i;

                        if start_i = '1' and start = '0' then
                            -- Grab the sign from op_a and op_b when DIV or REM
                            sign_a := op_a_i(op_a_i'length - 1) when (funct3_i = "100" or funct3_i = "110") else '0';
                            sign_b := op_b_i(op_b_i'length - 1) when (funct3_i = "100" or funct3_i = "110") else '0';

                            -- The quotient is negative when the signs differ
                            neg_result <= sign_a xor sign_b;

                            -- The remainder always follows the dividend's sign
                            neg_remainder <= sign_a;

                            -- Save op_a and op_b as magnitudes
                            --  Twos complement when negative value
                            --  Regular value when positive
                            dividend <= std_ulogic_vector(unsigned(not op_a_i) + 1) when sign_a = '1' else op_a_i;
                            divisor  <= std_ulogic_vector(unsigned(not op_b_i) + 1) when sign_b = '1' else op_b_i;

                            valid_o <= '0';

                            current_state <= Check;
                        else
                            valid_o <= '0';

                            current_state <= Idle;
                        end if;

                    when Check =>
                        -- Division by 0
                        if unsigned(divisor) = 0 then
                            quotient <= (others => '1');
                            rem_work <= '0' & unsigned(op_a_i);
                            neg_result <= '0';
                            neg_remainder <= '0';
                            valid_o <= '1';

                            current_state <= Idle;
                        -- Signed overflow ((-2^31) / (-1))
                        elsif op_a_i = x"80000000" and op_b_i = x"FFFFFFFF" and (funct3_i = "100" or funct3_i = "110") then
                            quotient <= op_a_i;
                            rem_work <= (others => '0');
                            neg_result <= '0';
                            neg_remainder <= '0';
                            valid_o <= '1';

                            current_state <= Idle;
                        else
                            quotient <= dividend;
                            rem_work <= (others => '0');

                            current_state <= Calc;
                        end if;

                    when Calc =>
                        divisor_ext := resize(unsigned(divisor), op_a_i'length + 1);
                        trial := rem_work(op_a_i'length - 1 downto 0) & quotient(quotient'high);

                        if trial >= divisor_ext then
                            rem_work <= trial - divisor_ext;
                            quotient <= quotient(quotient'high - 1 downto 0) & '1';
                        else
                            rem_work <= trial;
                            quotient <= quotient(quotient'high - 1 downto 0) & '0';
                        end if;

                        if cycles = op_a_i'length - 1 then
                            valid_o <= '1';

                            current_state <= Idle;
                        else
                            cycles := cycles + 1;

                            current_state <= Calc;
                        end if;

                end case;
            end if;
        end if;
    end process;

    quotient_corr <= std_ulogic_vector(unsigned(not quotient) + 1) when neg_result = '1' else quotient;
    remainder_corr <= std_ulogic_vector(unsigned(not rem_work(op_a_i'length - 1 downto 0)) + 1) when neg_remainder = '1' else
                      std_ulogic_vector(rem_work(op_a_i'length - 1 downto 0));

    quotient_o <= quotient_corr;
    remainder_o <= remainder_corr;

    busy_o <= '1' when (current_state = Calc) else
              '1' when (current_state = Check) else
              '1' when (current_state = Idle and start_i = '1' and start = '0') else
              '0';

end architecture tinymcu_cpu_div_rtl;
