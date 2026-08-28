--Copyright 1986-2022 Xilinx, Inc. All Rights Reserved.
--Copyright 2022-2024 Advanced Micro Devices, Inc. All Rights Reserved.
----------------------------------------------------------------------------------
--Tool Version: Vivado v.2024.1 (lin64) Build 5076996 Wed May 22 18:36:09 MDT 2024
--Date        : Fri Aug 28 17:53:25 2026
--Host        : daniel running 64-bit Ubuntu 22.04.5 LTS
--Command     : generate_target Clock.bd
--Design      : Clock
--Purpose     : IP block netlist
----------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
library UNISIM;
use UNISIM.VCOMPONENTS.ALL;
entity Clock is
  port (
    ClockIn : in STD_LOGIC;
    ILA_Clock : out STD_LOGIC;
    Locked : out STD_LOGIC;
    MCU_Clock : out STD_LOGIC;
    Reset : in STD_LOGIC
  );
  attribute CORE_GENERATION_INFO : string;
  attribute CORE_GENERATION_INFO of Clock : entity is "Clock,IP_Integrator,{x_ipVendor=xilinx.com,x_ipLibrary=BlockDiagram,x_ipName=Clock,x_ipVersion=1.00.a,x_ipLanguage=VHDL,numBlks=1,numReposBlks=1,numNonXlnxBlks=0,numHierBlks=0,maxHierDepth=0,numSysgenBlks=0,numHlsBlks=0,numHdlrefBlks=0,numPkgbdBlks=0,bdsource=USER,da_board_cnt=1,synth_mode=Hierarchical}";
  attribute HW_HANDOFF : string;
  attribute HW_HANDOFF of Clock : entity is "Clock.hwdef";
end Clock;

architecture STRUCTURE of Clock is
  component Clock_clk_wiz_0_0 is
  port (
    reset : in STD_LOGIC;
    clk_in1 : in STD_LOGIC;
    locked : out STD_LOGIC;
    MCU : out STD_LOGIC;
    ILA : out STD_LOGIC
  );
  end component Clock_clk_wiz_0_0;
  signal ClockingWizard_ILA : STD_LOGIC;
  signal ClockingWizard_MCU : STD_LOGIC;
  signal ClockingWizard_locked : STD_LOGIC;
  signal Reset_1 : STD_LOGIC;
  signal clk_100MHz_1 : STD_LOGIC;
  attribute X_INTERFACE_INFO : string;
  attribute X_INTERFACE_INFO of ClockIn : signal is "xilinx.com:signal:clock:1.0 CLK.CLOCKIN CLK";
  attribute X_INTERFACE_PARAMETER : string;
  attribute X_INTERFACE_PARAMETER of ClockIn : signal is "XIL_INTERFACENAME CLK.CLOCKIN, ASSOCIATED_RESET Reset, CLK_DOMAIN Clock_clk_100MHz, FREQ_HZ 125000000, FREQ_TOLERANCE_HZ 0, INSERT_VIP 0, PHASE 0.0";
  attribute X_INTERFACE_INFO of ILA_Clock : signal is "xilinx.com:signal:clock:1.0 CLK.ILA_CLOCK CLK";
  attribute X_INTERFACE_PARAMETER of ILA_Clock : signal is "XIL_INTERFACENAME CLK.ILA_CLOCK, CLK_DOMAIN /ClockingWizard_clk_out1, FREQ_HZ 100000000, FREQ_TOLERANCE_HZ 0, INSERT_VIP 0, PHASE 0.0";
  attribute X_INTERFACE_INFO of MCU_Clock : signal is "xilinx.com:signal:clock:1.0 CLK.MCU_CLOCK CLK";
  attribute X_INTERFACE_PARAMETER of MCU_Clock : signal is "XIL_INTERFACENAME CLK.MCU_CLOCK, CLK_DOMAIN /ClockingWizard_clk_out1, FREQ_HZ 16000000, FREQ_TOLERANCE_HZ 0, INSERT_VIP 0, PHASE 0.0";
  attribute X_INTERFACE_INFO of Reset : signal is "xilinx.com:signal:reset:1.0 RST.RESET RST";
  attribute X_INTERFACE_PARAMETER of Reset : signal is "XIL_INTERFACENAME RST.RESET, INSERT_VIP 0, POLARITY ACTIVE_HIGH";
begin
  ILA_Clock <= ClockingWizard_ILA;
  Locked <= ClockingWizard_locked;
  MCU_Clock <= ClockingWizard_MCU;
  Reset_1 <= Reset;
  clk_100MHz_1 <= ClockIn;
ClockingWizard: component Clock_clk_wiz_0_0
     port map (
      ILA => ClockingWizard_ILA,
      MCU => ClockingWizard_MCU,
      clk_in1 => clk_100MHz_1,
      locked => ClockingWizard_locked,
      reset => Reset_1
    );
end STRUCTURE;
