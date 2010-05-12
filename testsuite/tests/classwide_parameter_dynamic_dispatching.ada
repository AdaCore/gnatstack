with Stack_Handling; use Stack_Handling;
with Dispatching;
with My_Dispatching;

--  In this test there is a call to a method using dynamic dispatching,
--  and this call is part of the worst-case path for stack usage.

procedure Test is
   Obj : Dispatching.Derived_CA := new My_Dispatching.MySubderived;
begin
   Initialize_Stack;

   My_Dispatching.Caller (Obj.all);
   --  Obj belongs to the classwide type rooted at Derived, so
   --  this call can dispatch to either Derived::Foo or
   --  Subderived::Foo.
   --  GNATstack should take Subderived::Foo as the biggest stack
   --  consumer. If we want the actual execution of the program to
   --  actually traverse the worst-case path we need an object of
   --  type Subderived'Class.

   Print_Stack_Usage;
end Test;

with Dispatching;

package My_Dispatching is
   type MySubderived is new Dispatching.Subderived with private;

   procedure Caller (Obj : in out Dispatching.Derived'Class);

private
   type Array_100 is array (1 .. 100) of Integer;

   type MySubderived is new Dispatching.Subderived with
      record
         Buffer_100 : Array_100;
      end record;
end My_Dispatching;

package body My_Dispatching is
   procedure Caller (Obj : in out Dispatching.Derived'Class) is
      Tmp : Array_100;
   begin
      --  Modify data on the stack

      if Obj in MySubderived'Class then
         for Index in Array_100'Range loop
            Tmp (Index) := MySubderived (Obj).Buffer_100 (Index);
         end loop;

         for Index in Array_100'Range loop
            MySubderived (Obj).Buffer_100 (Index) :=  Tmp (100 - Index + 1);
         end loop;
      end if;

      Dispatching.Foo (Obj);
   end Caller;

end My_Dispatching;
