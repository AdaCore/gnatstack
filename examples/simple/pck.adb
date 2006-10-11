package body Pck is
   function Inverse (Data : Data_Type) return Data_Type is
      Result : Data_Type;
   begin
      for Index in Data_Type'Range loop
         Result (Index) := Data (Data_Type'Last - (Index - Data_Type'First));
      end loop;

      return Result;
   end Inverse;
end Pck;
