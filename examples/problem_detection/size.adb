with System.Storage_Elements;
use  System.Storage_Elements;

function Size return Integer is
   use type System.Address;
begin
   if Size'Address < To_Address (16#1_0000#) then
      return 10;
   else
      return 20;
   end if;
end Size;
