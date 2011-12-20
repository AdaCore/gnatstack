------------------------------------------------------------------------------
--                        STATIC STACK ANALYSIS TOOL                        --
--                                                                          --
--                           C A L L _ G R A P H S                          --
--                                                                          --
--                                 S p e c                                  --
--                                                                          --
--                     Copyright (C) 2005-2011, AdaCore                     --
--                                                                          --
-- GNATstack  is free  software;  you can redistribute  it and/or modify it --
-- under terms of the  GNU General Public License as published  by the Free --
-- Software  Foundation;  either version 3,  or (at your option)  any later --
-- version.  GNATstack is distributed  in the hope that it will be  useful, --
-- but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANT- --
-- ABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public --
-- License for  more details.  You should have  received  a copy of the GNU --
-- General Public License distributed with GNATstack; see file COPYING3. If --
-- not,  go to  http://www.gnu.org/licenses  for a  complete  copy  of  the --
-- license.                                                                 --
------------------------------------------------------------------------------

package Call_Graphs is

   procedure Analyze_Call_Graph;
   --  Depending on the selected flags, this procedure will extract all the
   --  cycles that can be reached from any subprogram, as well as undefined
   --  references, indirect calls and unbounded frames. It will also get the
   --  entry points for the application (depending on the options defined by
   --  the user).

   procedure Resolve_Aliases;
   --  Look for unresolved subprograms which need to be resolved using the
   --  aliasing information.

end Call_Graphs;
