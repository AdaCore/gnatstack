package body Pck is

   procedure Local (Size : Integer) is
      Data : array (1 .. Size) of Integer;
   begin
      Process;
   end Local;

   procedure Process is
      procedure Inner is
         function Inc (D : Integer) return Integer;
         pragma Import (C, Inc, "inc");
      begin
         Local (Inc (10));
      end Inner;
   begin
      Inner;
   end Process;
end Pck;
