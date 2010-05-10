with Stack_Handling; use Stack_Handling;
with My_Dispatching;

--  In this test there is a call to a method using dynamic dispatching,
--  and this call is part of the worst-case path for stack usage.

procedure Test is
   Obj : My_Dispatching.Mysubderived_CA := new My_Dispatching.Mysubderived;

   procedure Caller (Object : My_Dispatching.Mysubderived_CA) is
   begin
      My_Dispatching.Foo (Obj.all);
      --  Obj belongs to the classwide type rooted at Mysubderived, so
      --  this call can dispatch to either Subderived::Foo or
      --  Subsubderived::Foo. GNATstack should take Subderived::Foo as
      --  the biggest stack consumer. If we want the actual execution of
      --  the program to actually traverse the worst-case path we need an
      --  object of type either Subderived or Mysubderived.
   end Caller;

begin
   Initialize_Stack;

   Caller (Obj);

   Print_Stack_Usage;
end Test;

with Dispatching;

package My_Dispatching is
   Buffer_10 : array (1 .. 10) of Integer := (others => 10);

   type Mysubderived is new Dispatching.Subderived with null record;
   type Mysubderived_CA is access all Mysubderived'Class;

   type Subsubderived is new Mysubderived  with null record;
   procedure Foo (X : Subsubderived);
end My_Dispatching;

package body My_Dispatching is
   procedure Foo (X : Subsubderived) is
      Small_Stack_Eater : array (1 .. 10) of Integer;
   begin
      --  Modify data on the stack

      for Index in Small_Stack_Eater'Range loop
         Small_Stack_Eater (Index) := Buffer_10 (Index);
      end loop;

      for Index in Small_Stack_Eater'Range loop
         Buffer_10 (Index) := Small_Stack_Eater (10 - Index + 1);
      end loop;
   end Foo;
end My_Dispatching;
