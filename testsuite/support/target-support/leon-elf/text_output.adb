with System;

package body Text_Output is

   -----------
   -- Local --
   -----------

   type Scaler_12 is mod 2 **  12;
   for Scaler_12'Size use  12;

   type Reserved_20 is array (0 .. 19) of Boolean;
   for Reserved_20'Size use 20;
   pragma Pack (Reserved_20);

   type Reserved_23 is array (0 .. 22) of Boolean;
   for Reserved_23'Size use 23;
   pragma Pack (Reserved_23);

   type Reserved_24 is array (0 .. 23) of Boolean;
   for Reserved_24'Size use 24;
   pragma Pack (Reserved_24);

   type Reserved_25 is array (0 .. 24) of Boolean;
   for Reserved_25'Size use 25;
   pragma Pack (Reserved_25);

   UART_1_Data_Register_Address :
     constant System.Address := System'To_Address (16#80000070#);

   UART_1_Status_Register_Address :
     constant System.Address := System'To_Address (16#80000074#);

   UART_1_Control_Register_Address :
     constant System.Address := System'To_Address (16#80000078#);

   UART_1_Scaler_Register_Address :
     constant System.Address := System'To_Address (16#8000007C#);

   type UART_Data_Register is
      record
         RTD      : Character;
         Reserved : Reserved_24;
      end record;

   for UART_Data_Register use
      record
         RTD      at 0 range 24 .. 31;
         Reserved at 0 range  0 .. 23;
      end record;

   for UART_Data_Register'Size use 32;

   pragma Suppress_Initialization (UART_Data_Register);

   type UART_Status_Register is
      record
         DR       : Boolean;
         TS       : Boolean;
         TH       : Boolean;
         BR       : Boolean;
         OV       : Boolean;
         PE       : Boolean;
         FE       : Boolean;
         Reserved : Reserved_25;
      end record;

   for UART_Status_Register use
      record
         DR       at 0 range 31 .. 31;
         TS       at 0 range 30 .. 30;
         TH       at 0 range 29 .. 29;
         BR       at 0 range 28 .. 28;
         OV       at 0 range 27 .. 27;
         PE       at 0 range 26 .. 26;
         FE       at 0 range 25 .. 25;
         Reserved at 0 range  0 .. 24;
      end record;

   for UART_Status_Register'Size use 32;

   pragma Suppress_Initialization (UART_Status_Register);

   type UART_Control_Register is
      record
         RE       : Boolean;
         TE       : Boolean;
         RI       : Boolean;
         TI       : Boolean;
         PS       : Boolean;
         PE       : Boolean;
         FL       : Boolean;
         LB       : Boolean;
         EC       : Boolean;
         Reserved : Reserved_23;
      end record;

      for UART_Control_Register use
      record
         RE       at 0 range 31 .. 31;
         TE       at 0 range 30 .. 30;
         RI       at 0 range 29 .. 29;
         TI       at 0 range 28 .. 28;
         PS       at 0 range 27 .. 27;
         PE       at 0 range 26 .. 26;
         FL       at 0 range 25 .. 25;
         LB       at 0 range 24 .. 24;
         EC       at 0 range 23 .. 23;
         Reserved at 0 range  0 .. 22;
      end record;

   for UART_Control_Register'Size use 32;

   pragma Suppress_Initialization (UART_Control_Register);

   type UART_Scaler_Register is
      record
         UART_Scaler : Scaler_12;
         Reserved    : Reserved_20;
      end record;

   for UART_Scaler_Register use
      record
         UART_Scaler at 0 range 20 .. 31;
         Reserved    at 0 range  0 .. 19;
      end record;

   for UART_Scaler_Register'Size use 32;

   pragma Suppress_Initialization (UART_Scaler_Register);

   UART_1_Data : UART_Data_Register;
   pragma Atomic (UART_1_Data);
   for UART_1_Data'Address use UART_1_Data_Register_Address;

   UART_1_Status : UART_Status_Register;
   pragma Atomic (UART_1_Status);
   for UART_1_Status'Address use UART_1_Status_Register_Address;

   UART_1_Control : UART_Control_Register;
   pragma Atomic (UART_1_Control);
   for UART_1_Control'Address use UART_1_Control_Register_Address;

   UART_1_Scaler : UART_Scaler_Register;
   pragma Atomic (UART_1_Scaler);
   for UART_1_Scaler'Address use UART_1_Scaler_Register_Address;

   Clock_Frequency : constant Natural;  --  Hertz
   pragma Import (Asm, Clock_Frequency, "clock_frequency");
   --  Frequency of the system clock

   procedure Initialize_Console;
   pragma Inline_Always (Initialize_Console);

   procedure Console_Send (Char : Character);
   pragma Inline_Always (Console_Send);

   ------------------------
   -- Initialize_Console --
   ------------------------

   procedure Initialize_Console is
      Control_Aux : UART_Control_Register;
      Scaler_Aux  : UART_Scaler_Register;
   begin
      Control_Aux := UART_1_Control;

      Scaler_Aux :=
        (UART_Scaler =>
           Scaler_12
           ((Clock_Frequency * 10 / (115200 * 8) - 5) / 10),
         Reserved => (others => False));

      Control_Aux.RE := True;
      Control_Aux.TE := True;
      Control_Aux.RI := False;
      Control_Aux.PE := False;
      Control_Aux.PS := False;
      Control_Aux.FL := False;
      Control_Aux.LB := False;
      Control_Aux.EC := False;
      Control_Aux.Reserved := (others => False);

      UART_1_Control := Control_Aux;
      UART_1_Scaler  := Scaler_Aux;
   end Initialize_Console;

   ------------------
   -- Console_Send --
   ------------------

   procedure Console_Send (Char : Character)
   is
      UART_Tx         : constant UART_Data_Register :=
        (RTD => Char, Reserved => (others => False));

      UART_Status_Aux : UART_Status_Register;
   begin
      --  Send the character through the selected channel by polling

      --  Wait until the port is ready to load data

      loop
         UART_Status_Aux := UART_1_Status;
         exit when UART_Status_Aux.TH;
      end loop;

      --  Send the character once the UART is ready

      UART_1_Data := UART_Tx;
   end Console_Send;

   --------------
   -- Put_Line --
   --------------

   procedure Put_Line (Str : String) is
   begin
      for C in Str'Range loop
         Console_Send (Str (C));
      end loop;

      Console_Send (ASCII.LF);
      Console_Send (ASCII.CR);
   end Put_Line;

begin
   Initialize_Console;
end Text_Output;
