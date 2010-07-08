with Stack_Handling; use Stack_Handling;
with Dispatching;
with My_Dispatching;

--  In this test there is a call to a method using dynamic dispatching,
--  and this call is part of the worst-case path for stack usage. This
--  call is made from elaboration code.

procedure Test is
   Obj : Dispatching.Derived_CA := new Dispatching.Derived;
begin
   --  The call to Initialize_Stack is moved to the elaboration code.
   --  Otherwise, it happens too late (after the elaboration code).
   --  Initialize_Stack;

   My_Dispatching.Intermediate (Obj);
   --  Obj belongs to the classwide type rooted at Derived, so
   --  this call can dispatch to either Derived::Foo or
   --  Subderived::Foo.
   --  GNATstack should take Subderived::Foo as the biggest stack
   --  consumer. However, the worst-case comes from elaboration
   --  code.

   Print_Stack_Usage;
end Test;

with Dispatching;

package My_Dispatching is
   procedure Intermediate (Obj : Dispatching.Derived_CA);
end My_Dispatching;

with Stack_Handling;

package body My_Dispatching is

   Inner_Obj : Dispatching.Intermediate_CA :=
     new Dispatching.Intermediate;

   procedure Intermediate (Obj : Dispatching.Derived_CA) is
   begin
      Dispatching.Foo (Obj.all);
   end Intermediate;

begin
   Stack_Handling.Initialize_Stack;
   Dispatching.Foo (Inner_Obj.all);
end My_Dispatching;
