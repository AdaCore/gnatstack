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
--  Used for Generate_VCG_Graph
--           Print_Longest_Path;
procedure SSAT is
begin
   --  Get input arguments and generate (and decorate) the callgraph tree

   Parser.Parse_Arguments;

   --  Analyze stack usage

   Worst_Case_Analyzer.Worst_Case_Analysis;

   --  Display results

   Display.Generate_VCG_Graph;

   Display.Print_Longest_Path;
end SSAT;
