------------------------------------------------------------------------------
--                        STATIC STACK ANALYSIS TOOL                        --
--                                                                          --
--                   W O R S T _ C A S E _ A N A L Y Z E R                  --
--                                                                          --
--                                 S p e c                                  --
--                                                                          --
--                     Copyright (C) 2005-2007, AdaCore                     --
--                                                                          --
-- GNATStack  is free  software;  you can redistribute  it and/or modify it --
-- under terms of the  GNU General Public License as published  by the Free --
-- Software  Foundation;  either version 2,  or (at your option)  any later --
-- version.  GNATstack is distributed  in the hope that it will be  useful, --
-- but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANT- --
-- ABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public --
-- License for  more details.  You should have  received  a copy of the GNU --
-- General Public License distributed with GNATStack;  see file COPYING. If --
-- not, write to the  Free Software Foundation,  51 Franklin Street,  Fifth --
-- Floor, Boston, MA 02110-1301, USA.                                       --
------------------------------------------------------------------------------

with Static_Stack_Analysis;

package Worst_Case_Analyzer is

   procedure Get_Longest_Path
     (Path   : in out Static_Stack_Analysis.Paths.Vector;
      Target : Static_Stack_Analysis.Node_Id);
   --  This procedure returns the longest path, in terms of stack usage, that
   --  can be followed starting from the specified node.

   procedure Worst_Case_Analysis;
   --  Traverse the call graph in order to extract information about worst-case
   --  stack usage.

end Worst_Case_Analyzer;
