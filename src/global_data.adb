------------------------------------------------------------------------------
--                        STATIC STACK ANALYSIS TOOL                        --
--                                                                          --
--                           G L O B A L _ D A T A                          --
--                                                                          --
--                                 B o d y                                  --
--                                                                          --
--                     Copyright (C) 2005-2006, AdaCore                     --
--                                                                          --
-- SSAT is free software;  you can  redistribute it  and/or modify it under --
-- terms of the  GNU General Public License as published  by the Free Soft- --
-- ware  Foundation;  either version 2,  or (at your option) any later ver- --
-- sion.  GNAT is distributed in the hope that it will be useful, but WITH- --
-- OUT ANY WARRANTY;  without even the  implied warranty of MERCHANTABILITY --
-- or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License --
-- for  more details.  You should have  received  a copy of the GNU General --
-- Public License  distributed with GNAT;  see file COPYING.  If not, write --
-- to  the  Free Software Foundation,  51  Franklin  Street,  Fifth  Floor, --
-- Boston, MA 02110-1301, USA.                                              --
------------------------------------------------------------------------------

with GNAT.Regpat;
--  Used for Match

package body Global_Data is

   -------------------
   -- Is_Task_Entry --
   -------------------

   function Is_Task_Entry
     (Name : Static_Stack_Analysis.Name) return Boolean is
   begin
      --  ??? This pattern matching is not accurate. It will notify as task
      --  entry points subprograms that are not.

      return GNAT.Regpat.Match ("(TKB|[^\\_]B|B\.([0-9]+))$", Name.all);
   end Is_Task_Entry;

end Global_Data;
