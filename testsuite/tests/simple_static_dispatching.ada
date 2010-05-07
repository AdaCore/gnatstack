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

package Dispatching is
   type Base is tagged null record;
   procedure Foo (X : Base);

   type Base_CA is access all Base'Class;

   type Intermediate is new Base with null record;

   type Intermediate_CA is access all Intermediate'Class;

   type Derived is new Intermediate with null record;
   procedure Foo (X : Derived);

   type Derived_CA is access all Derived'Class;

   type Subderived is new Derived with null record;
   procedure Foo (X : Subderived);

   type Subderived_CA is access all Subderived'Class;

   Buffer_10   : array (1 .. 10)   of Integer := (others => 10);
   Buffer_100  : array (1 .. 100)  of Integer := (others => 10);
   Buffer_1000 : array (1 .. 1000) of Integer := (others => 10);

end Dispatching;

package body Dispatching is
   procedure Foo (X : Base) is
      Big_Stack_Eater : array (1 .. 1000) of Integer;
   begin
      --  Modify data on the stack

      for Index in Big_Stack_Eater'Range loop
         Big_Stack_Eater (Index) := Buffer_1000 (Index);
      end loop;

      for Index in Big_Stack_Eater'Range loop
         Buffer_1000 (Index) := Big_Stack_Eater (1000 - Index + 1);
      end loop;
   end Foo;

   procedure Foo (X : Derived) is
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

   procedure Foo (X : Subderived) is
      Medium_Stack_Eater : array (1 .. 100) of Integer;
   begin
      --  Modify data on the stack

      for Index in Medium_Stack_Eater'Range loop
         Medium_Stack_Eater (Index) := Buffer_100 (Index);
      end loop;

      for Index in Medium_Stack_Eater'Range loop
         Buffer_100 (Index) := Medium_Stack_Eater (100 - Index + 1);
      end loop;
   end Foo;
end Dispatching;
