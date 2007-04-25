------------------------------------------------------------------------------
--                        STATIC STACK ANALYSIS TOOL                        --
--                                                                          --
--                             G N A T S T A C K                            --
--                                                                          --
--                                 B o d y                                  --
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

with Parser;
--  Used for Parse_Arguments

with Worst_Case_Analyzer;
--  Used for Worst_Case_Analysis

with Display;
--  Used for Generate_Results
--           Generate_Warnings

with Call_Graphs;
--  Used for Check_Accuracy

with Global_Data;
--  Used for Entry_Points
--           Phase

procedure Gnatstack is
begin
   --  Get input arguments and generate (and decorate) the callgraph tree

   Global_Data.Phase := Global_Data.Parse;
   Parser.Parse_Arguments;

   --  Do accuracy analysis of the graph

   Global_Data.Phase := Global_Data.Accuracy_Analysis;
   Global_Data.Entry_Points.Iterate (Call_Graphs.Check_Accuracy'Access);

   --  Open (and create) the required output files

   Display.Open_Output_Files;

   --  Display incomplete information (if warnings are activated)

   Global_Data.Phase := Global_Data.Print_Warnings;
   Display.Generate_Warnings;

   --  Analyze stack usage

   Global_Data.Phase := Global_Data.Worst_Case_Analysis;
   Worst_Case_Analyzer.Worst_Case_Analysis;

   --  Display results

   Global_Data.Phase := Global_Data.Print_Results;
   Display.Generate_Results;

   --  Close output files

   Display.Close_Output_Files;
end Gnatstack;
