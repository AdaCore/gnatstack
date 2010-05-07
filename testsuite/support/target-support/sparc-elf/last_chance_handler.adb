with System.Machine_Code; use System.Machine_Code;

with Memory;

procedure Last_Chance_Handler (Msg : System.Address; Line : Integer) is
   pragma Unreferenced (Msg, Line);
begin
   --  Finish execution (unsuccessfully => g1 = 0)

   Asm ("mov 0, %%g1" & ASCII.LF & ASCII.HT & "ta 0",
        No_Output_Operands, No_Input_Operands, "g1", True);
end Last_Chance_Handler;


