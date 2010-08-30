with Stack_Handling; use Stack_Handling;
with My_Dispatching; use My_Dispatching;

--  In this test there is a call to a method using dynamic dispatching,
--  and this call is part of the worst-case path for stack usage. The
--  primitive operation is a predefined primitive operation (equality).
--  This test is expected to work on restricted run times (ZFP, Ravenscar)
--  so testing other primitive operations is not possible since Streams
--  are not supported (hence no 'Read, 'Write, 'Input, 'Output) and
--  controlled types either (hence no Initialize, Adjust, Finalize).

procedure Test is
   Obj1 : My_Dispatching.T_CA := new My_Dispatching.TT;
   Obj2 : My_Dispatching.T_CA := new My_Dispatching.TT;
begin
   Initialize_Stack;

   if Obj1.all = Obj2.all then
      My_Dispatching.Result := True;
   end if;

   Print_Stack_Usage;
end Test;

package My_Dispatching is
   type T is tagged null record;
   function "=" (Left, Right : T) return Boolean;

   type T_CA is access all T'Class;

   type TT is new T with null record;
   function "=" (Left, Right : TT) return Boolean;

   Buffer_500 : array (1 .. 500)   of Integer := (others => 10);

   Result : Boolean := False;
end My_Dispatching;

package body My_Dispatching is
   function "=" (Left, Right : T) return Boolean is
   begin
      return False;
   end "=";

   function "=" (Left, Right : TT) return Boolean is
      Stack_Eater : array (1 .. 500) of Integer;
   begin
      --  Modify data on the stack

      for Index in Stack_Eater'Range loop
         Stack_Eater (Index) := Buffer_500 (Index);
      end loop;

      for Index in Stack_Eater'Range loop
         Buffer_500 (Index) := Stack_Eater (500 - Index + 1);
      end loop;

      return Buffer_500 (Stack_Eater'Last) = Stack_Eater (Stack_Eater'First);
   end "=";
end My_Dispatching;
