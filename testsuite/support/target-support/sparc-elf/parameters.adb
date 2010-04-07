with System.Machine_Code; use System.Machine_Code;

package body Parameters is
   function Get_Stack_Pointer return System.Address is
      Current_Stack : System.Address;
   begin
      Asm ("st %%sp, %0",
           Inputs  => No_Input_Operands,
           Outputs => System.Address'Asm_Output ("=m", Current_Stack),
           Volatile => True);
      return Current_Stack;
   end Get_Stack_Pointer;
end Parameters;
