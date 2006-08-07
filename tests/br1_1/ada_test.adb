procedure Ada_Test is
   Length : constant := 100;
   Str : String (1 .. Length);

   procedure Fill_String (Str : in out String);

   procedure Fill_String (Str : in out String) is
   begin
      Str := (others => 'x');
   end Fill_String;   

begin
   Fill_String (Str);
end; 
