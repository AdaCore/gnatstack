with Stack_Handling; use Stack_Handling;
with Dispatching;
with My_Dispatching;

--  In this test there is a call to a method using dynamic dispatching,
--  and this call is part of the worst-case path for stack usage.

procedure Test is
   Obj : Dispatching.Intermediate_CA := new My_Dispatching.Subsubderived;
begin
   Initialize_Stack;

   Dispatching.Foo (Obj.all);
   --  Obj belongs to the classwide type rooted at Intermediate, so
   --  this call can dispatch to any instance of Foo.
   --  GNATstack should take Subsubderived::Foo as the biggest stack
   --  consumer. If we want the actual execution of the program to
   --  actually traverse the worst-case path we need an object of
   --  type Subsubderived.

   Print_Stack_Usage;
end Test;

with Dispatching;

package My_Dispatching is
   type Subsubderived is new Dispatching.Subderived with null record;
   procedure Foo (X : Subsubderived);

   Buffer_5000  : array (1 .. 5000)  of Integer := (others => 10);
end My_Dispatching;

package body My_Dispatching is

   package Inner is
      type T is tagged null record;
      procedure Proc (This : in out T);
   end Inner;

   package body Inner is
      procedure Proc (This : in out T) is
      begin
         null;
      end Proc;
   end Inner;

   Obj : Inner.T;

   procedure Foo (X : Subsubderived) is
      Stack_Eater : array (1 .. 5000) of Integer;
   begin
      --  Modify data on the stack

      for Index in Stack_Eater'Range loop
         Stack_Eater (Index) := Buffer_5000 (Index);
      end loop;

      for Index in Stack_Eater'Range loop
         Buffer_5000 (Index) := Stack_Eater (5000 - Index + 1);
      end loop;

      --  Call procedure in nested body

      Inner.Proc (Obj);
   end Foo;
end My_Dispatching;
