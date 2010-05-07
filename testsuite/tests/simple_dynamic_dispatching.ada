with Stack_Handling; use Stack_Handling;
with Dispatching;

--  In this test there is a call to a method using dynamic dispatching,
--  and this call is part of the worst-case path for stack usage.

procedure Test is
   Obj : Dispatching.Intermediate_CA := new Dispatching.Intermediate;
begin
   Initialize_Stack;

   Dispatching.Foo (Obj.all);
   --  Obj belongs to the classwide type rooted at Intermediate, so
   --  this call can dispatch to any instance of Foo.
   --  GNATstack should take Base::Foo as the biggest stack
   --  consumer. If we want the actual execution of the program to
   --  actually traverse the worst-case path we need an object of
   --  type Intermediate.

   Print_Stack_Usage;
end Test;
