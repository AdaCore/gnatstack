with Ext;
--  Ext is compiled without stack usage information

procedure P is
   Set_Alignment : access procedure (Minimum : Integer) :=
     Ext.Set_Alignment'Access;
   --  Indirect call

   procedure R;

   procedure Q is
      Data : array (1 .. Ext.Get_Size (10)) of Character;
      --  Dynamically sized local objects
   begin
      R;
   end Q;

   procedure R is
   begin
      Q;
   end R;
begin
   --  Set minimum alignment (via indirect call)
   Set_Alignment.all (Integer'Alignment);

   --  Recursion: Q -> R -> Q
   Q;
end P;
