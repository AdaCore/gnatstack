
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
