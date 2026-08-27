--------------------------------------------------------------------------------
-- SPDX-License-Identifier: GPL-3.0-or-later
--
-- Company:
-- Engineer: Daniel Kampert
--
-- Create Date: 14.06.2026
-- Design Name: TinyMCU
-- Module Name: tinymcu_cpu_mult - tinymcu_cpu_mult_rtl
-- Project Name: TinyMCU
-- Description:
--   Shift-Add multiplier unit for the TinyMCU.
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

entity tinymcu_cpu_mult is
    port (
        -- Global control
        clk_i       : in  std_logic;
        rst_i       : in  std_logic;

        -- Data input
        op_a_i      : in  word_t;
        op_b_i      : in  word_t;

        -- Result
        result_o    : out word_t;

        -- Status and control
        start_i     : in  std_ulogic;
        busy_o      : out std_ulogic;
        valid_o     : out std_ulogic;
        funct3_i    : in  std_ulogic_vector(2 downto 0)
    );
end entity tinymcu_cpu_mult;

architecture tinymcu_cpu_mult_rtl of tinymcu_cpu_mult is

    type Mult_State_t is (Idle, Calc);

    signal op_a             : word_t;
    signal start            : std_ulogic;
    signal product          : std_ulogic_vector(((2 * op_a_i'length) - 1) downto 0);
    signal product_corr     : std_ulogic_vector(((2 * op_a_i'length) - 1) downto 0);
    signal neg_result       : std_ulogic;
    signal high_sel         : std_ulogic;

    signal current_state    : Mult_State_t := Idle;

begin

	process(clk_i)
        variable temp   : signed(op_a_i'length downto 0);
        variable cycles : integer range 0 to op_a_i'length;
        variable sign_a : std_ulogic;
        variable sign_b : std_ulogic;
	begin
		if rising_edge(clk_i) then
			if rst_i = '1' then
                cycles := 0;
                temp := (others => '0');

                valid_o <= '0';
                product <= (others => '0');
                op_a <= (others => '0');
                start <= '0';
                neg_result <= '0';
                high_sel <= '0';
                current_state <= Idle;
			else
				case current_state is
					when Idle =>
                        cycles := 0;

                        start <= start_i;

						if start_i = '1' and start = '0' then
                            -- Grab the sign from op_a when MULH or MULHSU
                            sign_a := op_a_i(op_a_i'length - 1) when (funct3_i = "001" or funct3_i = "010") else '0';

                            -- Grab the sign from op_b when MULH
                            sign_b := op_b_i(op_b_i'length - 1) when (funct3_i = "001") else '0';

                            -- The result must be inverted
                            neg_result <= sign_a xor sign_b;

                            -- Select the high word for anything but plain MUL
                            high_sel <= '0' when funct3_i = "000" else '1';

                            -- Save op_a as magnitude
                            --  Twos complement when negative value
                            --  Regular value when positive
                            op_a <= std_ulogic_vector(unsigned(not op_a_i) + 1) when sign_a = '1' else op_a_i;

                            product(((2 * op_a_i'length) - 1) downto op_a_i'length) <= (others => '0');
                            product((op_a_i'length - 1) downto 0) <= std_ulogic_vector(unsigned(not op_b_i) + 1) when sign_b = '1' else op_b_i;

                            valid_o <= '0';

                            current_state <= Calc;
                        else
                            valid_o <= '0';

                            current_state <= Idle;
						end if;

                    when Calc =>
                        if product(0) = '1' then
                            temp := signed('0' & product(((2 * op_a'length) - 1) downto op_a'length)) + signed('0' & op_a);
                        else
                            temp := signed('0' & product(((2 * op_a'length) - 1)downto op_a'length));
                        end if;

                        if cycles = op_a'length - 1 then
                            valid_o <= '1';

                            current_state <= Idle;
                        else
                            cycles := cycles + 1;

                            current_state <= Calc;
                        end if;

                        product <= std_ulogic_vector(temp) & product((op_a'length - 1) downto 1);

				end case;
			end if;
		end if;
	end process;

    product_corr <= std_ulogic_vector(unsigned(not product) + 1) when neg_result = '1' else product;

    result_o <= product_corr(((2 * op_a_i'length) - 1) downto op_a_i'length) when high_sel = '1' else
                product_corr((op_a'length - 1) downto 0);

    busy_o <= '1' when (current_state = Calc) else
              '1' when (current_state = Idle and start_i = '1' and start = '0') else
              '0';

end architecture tinymcu_cpu_mult_rtl;
