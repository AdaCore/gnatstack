with Stack_Handling; use Stack_Handling;
with Test_Proc;

--  In this test there are two indirect calls from the same subprogram,
--  which are resolved by user-defined code to the same target, and this
--  call is part of the worst-case path for stack usage. There is an
--  external .ci file which indicates to GNATstack the target of the
--  indirect calls, including the exact location of the call), enabling
--  GNATstack to find the actual worst-case path.

procedure Test is
   use type Test_Proc.Access_Procedure;
begin
   Initialize_Stack;

   Test_Proc.Ptr1 := Test_Proc.Do_Something'Access;
   Test_Proc.Ptr2 := Test_Proc.Do_Something'Access;

   Test_Proc.Ptr1.all;

   if Test_Proc.Ptr2 /= null then
      Test_Proc.Ptr2.all;
   end if;

   Print_Stack_Usage;
end Test;

package Test_Proc is
   type Access_Procedure is access procedure;

   procedure Do_Something;

   procedure Direct_Call;

   Ptr1 : Access_Procedure := null;
   Ptr2 : Access_Procedure := null;

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

   procedure Direct_Call is
   begin
      Do_Something;
   end Direct_Call;
end Test_Proc;
