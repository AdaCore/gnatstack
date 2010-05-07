with Stack_Handling; use Stack_Handling;
with Dispatching;

--  In this test there is a call to a method using static dispatching,
--  and this call is part of the worst-case path for stack usage.

procedure Test is
   Obj : Dispatching.Intermediate;
begin
   Initialize_Stack;

   Dispatching.Foo (Obj);
   --  Obj belongs to the type Intermediate, which does not override
   --  Foo, so this is a static call to Base::Foo.
   --  GNATstack should take Base::Foo as the biggest stack
   --  consumer.

   Print_Stack_Usage;
end Test;
