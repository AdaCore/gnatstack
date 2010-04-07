with Text_Output;

package body Display is
   Result      : String := "Stack usage: XXXXXXX bytes" & ASCII.LF;
   Numbers     : constant := 7;
   Start_Point : constant := 13;

   type Decimal_Character is range 0 .. 9;

   Remainder : Natural;
   Divisor   : Natural;
   Digit     : Decimal_Character;

   procedure Put_Stack_Usage (Stack_Size : Natural) is
   begin
      --  Check whether we are in the range we can represent

      if Stack_Size >= 10 ** Numbers then
         Text_Output.Put_Line ("Cannot represent this stack usage");

      else

         --  Set the stack usage value in the String

         Remainder := Stack_Size;
         Divisor := 10 ** Numbers;

         for Location in 1 .. Numbers loop
            Divisor := Divisor / 10;

            Digit := Decimal_Character (Remainder / Divisor);

            Remainder := Remainder - Natural (Digit) * Divisor;

            Result (Start_Point + Location) := Character'Val (48 + Digit);
         end loop;

         --  Now print it

         Text_Output.Put_Line (Result);
      end if;
   end Put_Stack_Usage;
end Display;
