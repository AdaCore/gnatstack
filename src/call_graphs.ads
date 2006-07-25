------------------------------------------------------------------------------
--                        STATIC STACK ANALYSIS TOOL                        --
--                                                                          --
--                           C A L L _ G R A P H S                          --
--                                                                          --
--                                 S p e c                                  --
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

with Static_Stack_Analysis;

package Call_Graphs is

   procedure Check_Accuracy
     (Position : in Static_Stack_Analysis.List_Of_Node_Ids.Cursor);
   --  Depending on the selected flags, this procedure will extract all the
   --  cycles that can be reached from the specified entry point, as well as
   --  undefined references, indirect calls and unbounded frames.

end Call_Graphs;
