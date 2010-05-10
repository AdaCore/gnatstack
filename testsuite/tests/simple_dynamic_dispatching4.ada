with Stack_Handling; use Stack_Handling;
with Dispatching;

--  In this test there is a call to a method using dynamic dispatching,
--  and this call is part of the worst-case path for stack usage.

procedure Test is
   Obj : Dispatching.Derived_CA := new Dispatching.Subderived;
begin
   Initialize_Stack;

   Dispatching.Foo (Obj.all);
   --  Obj belongs to the classwide type rooted at Derived, so
   --  this call can dispatch to any instance of either Derived::Foo
   --  or to Subderived::Foo.
   --  GNATstack should take Subsubderived::Foo as the biggest stack
   --  consumer. If we want the actual execution of the program to
   --  actually traverse the worst-case path we need an object of
   --  type Subsubderived.

   Print_Stack_Usage;
end Test;
