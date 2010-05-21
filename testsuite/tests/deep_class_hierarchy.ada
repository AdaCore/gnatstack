with Stack_Handling; use Stack_Handling;
with Dispatching;
with My_Dispatching;

--  In this test there is a call to a method using dynamic dispatching,
--  and this call is part of the worst-case path for stack usage.

procedure Test is
   Obj : Dispatching.Intermediate_CA := new My_Dispatching.Tagged10;
begin
   Initialize_Stack;

   Dispatching.Foo (Obj.all);
   --  Obj belongs to the classwide type rooted at Intermediate, so
   --  this call can dispatch to any instance of Foo.
   --  GNATstack should take Tagged10::Foo as the biggest stack
   --  consumer. If we want the actual execution of the program to
   --  actually traverse the worst-case path we need an object of
   --  type Tagged10.

   Print_Stack_Usage;
end Test;

with Dispatching;

package My_Dispatching is
   Buffer_5000 : array (1 .. 5000) of Integer := (others => 1);

   type Tagged1  is new Dispatching.Subderived with null record;
   type Tagged2  is new Tagged1 with null record;
   type Tagged3  is new Tagged2 with null record;
   type Tagged4  is new Tagged3 with null record;
   type Tagged5  is new Tagged4 with null record;
   type Tagged6  is new Tagged5 with null record;
   type Tagged7  is new Tagged6 with null record;
   type Tagged8  is new Tagged7 with null record;
   type Tagged9  is new Tagged8 with null record;
   type Tagged10 is new Tagged9 with null record;

   procedure Foo (X : Tagged10);
end My_Dispatching;

package body My_Dispatching is
   procedure Foo (X : Tagged10) is
      Big_Stack_Eater : array (1 .. 5000) of Integer;
   begin
      --  Modify data on the stack

      for Index in Big_Stack_Eater'Range loop
         Big_Stack_Eater (Index) := Buffer_5000 (Index);
      end loop;

      for Index in Big_Stack_Eater'Range loop
         Buffer_5000 (Index) := Big_Stack_Eater (5000 - Index + 1);
      end loop;
   end Foo;
end My_Dispatching;
