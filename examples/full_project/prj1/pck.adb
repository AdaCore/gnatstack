package body Pck is

   procedure Local (Size : Integer) is
      Data : array (1 .. Size) of Integer;
   begin
      Process;
   end Local;

   procedure Process is
      procedure Inner is
      begin
         Local (10);
      end Inner;
   begin
      Inner;
   end Process;
end Pck;
