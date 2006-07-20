------------------------------------------------------------------------------
--                        STATIC STACK ANALYSIS TOOL                        --
--                                                                          --
--                                 S S A T                                  --
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

with Parser;
--  Used for Parse_Arguments

with Worst_Case_Analyzer;
--  Used for Worst_Case_Analysis

with Display;
--  Used for Generate_Results
--           Generate_Warnings

with Call_Graphs;
--  Used for Check_Accuracy

with Static_Stack_Analysis;
--  Used for Entry_Points

procedure SSAT is
begin
   --  Get input arguments and generate (and decorate) the callgraph tree

   Parser.Parse_Arguments;

   --  Do accuracy analysis of the graph

   Static_Stack_Analysis.Entry_Points.Iterate
     (Call_Graphs.Check_Accuracy'Access);

   --  Display incomplete information (if warnings are activated)

   Display.Generate_Warnings;

   --  Analyze stack usage

   Worst_Case_Analyzer.Worst_Case_Analysis;

   --  Display results

   Display.Generate_Results;
end SSAT;
