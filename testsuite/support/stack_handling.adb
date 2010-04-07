with System.Storage_Elements; use System.Storage_Elements;
with Interfaces.C; use Interfaces.C;

with Parameters; use Parameters;

with Display;

with Last_Chance_Handler;

package body Stack_Handling is

   Stack_Size_In_Bytes : constant Integer :=
     Integer (Top_Of_Stack'Address - Bottom_Of_Stack'Address);
   --  Amount of stack allocated to the environment task (in bytes)

   type Pattern_Type is mod 2 ** (4 * 8);
   for Pattern_Type'Size use 4 * 8;
   --  Four bytes (each with 2 hexadecimal values) so 8 hexadecimal characters

   Dead_Beef_Pattern : constant Pattern_Type := 16#DEAD_BEEF#;
   --  Pattern that we are gone to insert in the stack

   type Mem_Array is array (1 .. Stack_Size_In_Bytes / 4) of Pattern_Type;
   --  Divide by 4 to transform size in bytes into number of 4-byte
   --  "deadbeef" elements.

   Stack : Mem_Array;
   for Stack'Address use Bottom_Of_Stack'Address;
   pragma Volatile (Stack);
   --  This array represents the whole stack for the environment task

   procedure Initialize_Stack is
      Current_Stack : constant System.Address := Get_Stack_Pointer;
      --  Variable that will contain the current stack pointer. We do
      --  not want to modify the part of the stack that is being used, that
      --  is, the part from the top until the current stack pointer.

   begin
      --  Fill the part of the stack that is not in use with the deadbeef
      --  pattern. This space is limited by the bottom of the allocated
      --  stack and the current stack pointer.

      Stack (1 .. Integer (Current_Stack - Bottom_Of_Stack'Address) / 4) :=
        (others => Dead_Beef_Pattern);
   end Initialize_Stack;

   procedure Print_Stack_Usage is
      Index : Natural := Mem_Array'First;

      Bytes_Used : Natural := 0;

   begin
      while Index <= Mem_Array'Last and then
        Stack (Index) = Dead_Beef_Pattern
      loop
         Index := Index + 1;
      end loop;

      --  Index points to the last double word that has been modified.

      --  The stack is always double-word (8-byte) aligned, so we do not
      --  need to look into the individual bytes.

      Bytes_Used := (Mem_Array'Last - Index + 1) * 4;

      Display.Put_Stack_Usage (Bytes_Used);
   end Print_Stack_Usage;

end Stack_Handling;
