-- Copyright 1986-2022 Xilinx, Inc. All Rights Reserved.
-- Copyright 2022-2024 Advanced Micro Devices, Inc. All Rights Reserved.
-- --------------------------------------------------------------------------------
-- Tool Version: Vivado v.2024.1 (lin64) Build 5076996 Wed May 22 18:36:09 MDT 2024
-- Date        : Fri Aug 28 17:54:21 2026
-- Host        : daniel running 64-bit Ubuntu 22.04.5 LTS
-- Command     : write_vhdl -force -mode synth_stub
--               /home/daniel/Projects/CPU/integration/TinyMCU.gen/sources_1/bd/Clock/ip/Clock_clk_wiz_0_0/Clock_clk_wiz_0_0_stub.vhdl
-- Design      : Clock_clk_wiz_0_0
-- Purpose     : Stub declaration of top-level module interface
-- Device      : xc7z010clg400-1
-- --------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

entity Clock_clk_wiz_0_0 is
  Port ( 
    MCU : out STD_LOGIC;
    ILA : out STD_LOGIC;
    reset : in STD_LOGIC;
    locked : out STD_LOGIC;
    clk_in1 : in STD_LOGIC
  );

end Clock_clk_wiz_0_0;

architecture stub of Clock_clk_wiz_0_0 is
attribute syn_black_box : boolean;
attribute black_box_pad_pin : string;
attribute syn_black_box of stub : architecture is true;
attribute black_box_pad_pin of stub : architecture is "MCU,ILA,reset,locked,clk_in1";
begin
end;
