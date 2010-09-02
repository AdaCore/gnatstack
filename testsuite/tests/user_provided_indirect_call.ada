with Stack_Handling; use Stack_Handling;
with Test_Proc;

--  In this test there is an indirect call (dereferencing an
--  access-to-subprogram variable), and this call is part of the
--  worst-case path for stack usage. There is an external .ci file
--  which indicates to GNATstack the target of the indirect call,
--  enabling GNATstack to find the actual worst-case path.

procedure Test is
begin
   Initialize_Stack;
   Test_Proc.Ptr := Test_Proc.Do_Something'Access;
   Test_Proc.Ptr.all;
   Print_Stack_Usage;
end Test;

package Test_Proc is
   type Access_Procedure is access procedure;

   Ptr : Access_Procedure;

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
