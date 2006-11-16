package body Ext is
   Threshold : Integer;

   procedure Set_Alignment (Minimum : Integer) is
   begin
      Threshold := Minimum;
   end Set_Alignment;

   function Get_Size (Value : Integer) return Integer is
   begin
      return (((Value - 1) / Threshold) + 1) * Threshold;
   end Get_Size;
end Ext;
