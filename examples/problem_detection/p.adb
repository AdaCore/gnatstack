with Ada.Calendar;

procedure P is

   procedure R;

   procedure Q is
      Size : Integer := Ada.Calendar.Year (Ada.Calendar.Clock);

      Data : array (1 .. Size) of Integer;
      --  Dynamically sized local objects

   begin
      R;
   end Q;

   procedure R is
   begin
      Q;
   end R;
begin
   Q;
end P;
