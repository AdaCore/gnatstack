--  This is the LEON specific one

with System;

package Parameters is
   Top_Of_Stack : constant System.Address;
   pragma Import (Asm, Top_Of_Stack, "__stack");
   --  Top of the stack allocated to the environment task

   Bottom_Of_Stack : constant System.Address;
   pragma Import (Asm, Bottom_Of_Stack, "_stack_start");
   --  Bottom of the stack allocated to the environment task

   function Get_Stack_Pointer return System.Address;
   pragma Inline_Always (Get_Stack_Pointer);
   --  Get the current stack pointer
   --  Inline this function so they do not affect stack utilization
end Parameters;
