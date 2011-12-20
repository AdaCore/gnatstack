------------------------------------------------------------------------------
--                        STATIC STACK ANALYSIS TOOL                        --
--                                                                          --
--                              D I S P L A Y                               --
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

with Global_Data;
--  Used for Entities

package Display is

   procedure Open_Output_Files;
   --  Open (and create) the required output files

   procedure Close_Output_Files;
   --  Close output files

   procedure Generate_Warnings;
   --  Generate all the information about incomplete information (missing stack
   --  usage data, indirect, dispatching and external calls, etc.).

   procedure Generate_Results;
   --  Generate all the results of the analysis (local stack usage and call
   --  graph and worst case stack usage information).

   procedure Increase_Count
     (Entity : Global_Data.Entities);
   --  Increase and print the number of subprograms, calls, or paths parsed

end Display;
