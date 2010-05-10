with Stack_Handling; use Stack_Handling;
with Dispatching;
with My_Dispatching;

--  In this test there is a call to a method using dynamic dispatching,
--  and this call is part of the worst-case path for stack usage.

procedure Test is
   Obj : Dispatching.Base_CA := new My_Dispatching.Subsubderived;
begin
   Initialize_Stack;

   Dispatching.Foo (Obj.all);
   --  Obj belongs to the classwide type rooted at Base, so
   --  this call can dispatch to any instance of Foo.
   --  GNATstack should take Subsubderived::Foo as the biggest stack
   --  consumer. If we want the actual execution of the program to
   --  actually traverse the worst-case path we need an object of
   --  type Subsubderived.

   Print_Stack_Usage;
end Test;

with Dispatching;

package My_Dispatching is
   Buffer_10000 : array (1 .. 10000) of Integer := (others => 10);

   type Subsubderived is new Dispatching.Subderived with null record;

   procedure Foo (X : Subsubderived);
end My_Dispatching;

package body My_Dispatching is
   procedure Foo (X : Subsubderived) is
      Really_Big_Stack_Eater : array (1 .. 10000) of Integer;
   begin
      --  Modify data on the stack

      for Index in Really_Big_Stack_Eater'Range loop
         Really_Big_Stack_Eater (Index) := Buffer_10000 (Index);
      end loop;

      for Index in Really_Big_Stack_Eater'Range loop
         Buffer_10000 (Index) := Really_Big_Stack_Eater (10000 - Index + 1);
      end loop;
   end Foo;
end My_Dispatching;
