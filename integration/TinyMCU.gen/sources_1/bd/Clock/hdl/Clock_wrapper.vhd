--Copyright 1986-2022 Xilinx, Inc. All Rights Reserved.
--Copyright 2022-2024 Advanced Micro Devices, Inc. All Rights Reserved.
----------------------------------------------------------------------------------
--Tool Version: Vivado v.2024.1 (lin64) Build 5076996 Wed May 22 18:36:09 MDT 2024
--Date        : Sat Aug 22 20:35:46 2026
--Host        : daniel running 64-bit Ubuntu 22.04.5 LTS
--Command     : generate_target Clock_wrapper.bd
--Design      : Clock_wrapper
--Purpose     : IP block netlist
----------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
library UNISIM;
use UNISIM.VCOMPONENTS.ALL;
entity Clock_wrapper is
  port (
    ClockIn : in STD_LOGIC;
    ClockOut : out STD_LOGIC;
    Reset : in STD_LOGIC
  );
end Clock_wrapper;

architecture STRUCTURE of Clock_wrapper is
  component Clock is
  port (
    ClockIn : in STD_LOGIC;
    ClockOut : out STD_LOGIC;
    Reset : in STD_LOGIC
  );
  end component Clock;
begin
Clock_i: component Clock
     port map (
      ClockIn => ClockIn,
      ClockOut => ClockOut,
      Reset => Reset
    );
end STRUCTURE;
