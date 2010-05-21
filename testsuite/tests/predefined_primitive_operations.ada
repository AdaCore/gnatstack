with Stack_Handling; use Stack_Handling;
with My_Dispatching;

--  In this test there is a call to a method using dynamic dispatching,
--  and this call is part of the worst-case path for stack usage. The
--  primitive operation has a name close to a predefined primitive
--  operation.

procedure Test is
   Obj : My_Dispatching.T_CA := new My_Dispatching.T;
begin
   Initialize_Stack;

   My_Dispatching.Size (Obj.all);
   --  This test creates a primitive operation with a name close to the
   --  predefined primitive operation associated to 'Size (_size).

   Print_Stack_Usage;
end Test;

package My_Dispatching is
   type T is tagged null record;
   procedure Size (This : in out T);

   type T_CA is access all T'Class;

   Buffer_500   : array (1 .. 500)   of Integer := (others => 10);
end My_Dispatching;

package body My_Dispatching is
   procedure Size (This : in out T) is
      Stack_Eater : array (1 .. 500) of Integer;
   begin
      --  Modify data on the stack

      for Index in Stack_Eater'Range loop
         Stack_Eater (Index) := Buffer_500 (Index);
      end loop;

      for Index in Stack_Eater'Range loop
         Buffer_500 (Index) := Stack_Eater (500 - Index + 1);
      end loop;
   end Size;
end My_Dispatching;
