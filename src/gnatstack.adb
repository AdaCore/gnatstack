------------------------------------------------------------------------------
--                        STATIC STACK ANALYSIS TOOL                        --
--                                                                          --
--                             G N A T S T A C K                            --
--                                                                          --
--                                 B o d y                                  --
--                                                                          --
--                     Copyright (C) 2005-2025, AdaCore                     --
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

with Parser;
with Worst_Case_Analyzer;
with Display;
with Call_Graphs;
with Global_Data;
with Dispatching_Calls;
with Options;

with Ada.Text_IO;

with GNAT.OS_Lib;

procedure Gnatstack is
begin
   --  Get input arguments and generate (and decorate) the callgraph tree

   Global_Data.Phase := Global_Data.Parse;
   Parser.Parse_Arguments;

   --  Resolve information about dispatching calls

   Global_Data.Phase := Global_Data.Dispatching_Calls;

   --  Create the list of derived classes for every base class

   Dispatching_Calls.Create_Class_Hierarchies;

   --  Compute the list of methods which override every virtual method

   Dispatching_Calls.Create_Method_Hierarchies;

   --  Resolve dispatching calls

   Dispatching_Calls.Resolve_Dispatching_Calls;

   --  Resolve aliases

   Global_Data.Phase := Global_Data.Alias_Analysis;
   Call_Graphs.Resolve_Aliases;

   --  Do accuracy analysis of the graph and extract entry points

   Global_Data.Phase := Global_Data.Call_Graph_Analysis;
   Call_Graphs.Analyze_Call_Graph;

   --  Open (and create) the required output files

   Display.Open_Output_Files;

   --  Analyze stack usage

   Global_Data.Phase := Global_Data.Worst_Case_Analysis;
   Worst_Case_Analyzer.Worst_Case_Analysis;

   --  Display incomplete information (if warnings are activated)

   Global_Data.Phase := Global_Data.Print_Warnings;
   Display.Generate_Warnings;

   --  Display results

   Global_Data.Phase := Global_Data.Print_Results;
   Display.Generate_Results;

   --  Close output files

   Display.Close_Output_Files;

   if not Options.Very_Quiet then
      Ada.Text_IO.Put_Line ("GNATstack: analysis successfully finished");
   end if;

exception
   when others =>
      Ada.Text_IO.New_Line;
      Ada.Text_IO.Put ("GNATstack: analysis abandoned while ");

      case Global_Data.Phase is
         when Global_Data.Parse =>
            Ada.Text_IO.Put_Line ("parsing stack and callgraph information");
         when Global_Data.Dispatching_Calls =>
            Ada.Text_IO.Put_Line ("analyzing dispatching calls");
         when Global_Data.Call_Graph_Analysis =>
            Ada.Text_IO.Put_Line ("generating the call graph");
         when Global_Data.Alias_Analysis =>
            Ada.Text_IO.Put_Line ("resolving aliasing information");
         when Global_Data.Print_Warnings =>
            Ada.Text_IO.Put_Line ("displaying incomplete information");
         when Global_Data.Worst_Case_Analysis =>
            Ada.Text_IO.Put_Line
               ("traversing the call graph for worst case stack usage");
         when Global_Data.Print_Results =>
            Ada.Text_IO.Put_Line ("printing stack usage results");
      end case;

      GNAT.OS_Lib.OS_Exit (2);
end Gnatstack;
