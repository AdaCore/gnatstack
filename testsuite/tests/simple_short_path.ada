with Stack_Handling; use Stack_Handling;
with Test_Proc;

procedure Test is
begin
   Initialize_Stack;
   Test_Proc.Do_Something;
   Print_Stack_Usage;
end Test;

package Test_Proc is
   procedure Do_Something;

   Size : constant := 64;

   type Buffer_Type is array (1 .. Size) of Integer;

   Buffer : Buffer_Type := (others => 10);
end Test_Proc;

package body Test_Proc is
   procedure Do_Something is
      Use_Stack : Buffer_Type;
   begin
      --  Modify data on the stack

      for Index in Buffer_Type'Range loop
         Use_Stack (Index) := Buffer (Index);
      end loop;

      for Index in Buffer_Type'Range loop
         Buffer (Index) := Use_Stack (Size - Index + 1);
      end loop;
   end Do_Something;
end Test_Proc;
