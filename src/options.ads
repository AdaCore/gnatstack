------------------------------------------------------------------------------
--                        STATIC STACK ANALYSIS TOOL                        --
--                                                                          --
--                              O P T I O N S                               --
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

with GNAT.Strings;
--  Used for String_Access

package Options is

   Verbose : Boolean := False;
   --  Verbose output

   Debug : Boolean := False;
   --  Debug output

   Generate_XML_Output : Boolean := False;
   --  XML output

   Number_Of_Biggest_Frames : Natural := 0;
   --  Print this number of subprograms corresponding to those requiring the
   --  biggest local stack usage.

   type Order_Type is (Alphabetical, Stack_Usage);

   Order : Order_Type := Stack_Usage;
   --  Determines the order in which the results are displayed. It can be
   --  either in alphabetical order (according to the symbol name), or in
   --  decreasing order of stack usage.

   type Warning_Options is (Cycle, Unbounded, External, Indirect);

   Warnings : array (Warning_Options) of Boolean := (others => False);
   --  Active warnings (for cycles, unbounded frames, external calls, and
   --  indirect calls)

   Display_Call_Chains : Boolean := False;
   --  Print the call chain information for the different entry points. This
   --  is the list of subprograms that make up the longest path in terms of
   --  stack usage.

   Explore_All : Boolean := False;
   --  Compute worst case stack usage for every node in the partition (every
   --  node not called by any other).

   Compute_All_Cycles : Boolean := False;
   --  Flag that indicates whether we want to get the full list of potential
   --  cycles in the program (True) or simply to know if a subprogram belong
   --  to at least one cycle.

   List_Of_Entry_Points : GNAT.Strings.String_Access := null;
   --  List of entry points to be analyzed

   Entry_Point_Pattern : GNAT.Strings.String_Access := null;
   --  Consider as entry points all the subprograms containing this pattern in
   --  the symbol name.

   Automatic_Entry_Point_Detection : Boolean := False;
   --  Flag that determines whether the automatic mechanism to detect entry
   --  points is to be used.

   Output_VCG : GNAT.Strings.String_Access := null;
   --  Name of the generated call graph file

   Output_Undefined : GNAT.Strings.String_Access := null;
   --  Name of the generated file containing undefined information, such as
   --  external and indirect calls.

   Output_XML : GNAT.Strings.String_Access := null;
   --  Name of the generated file containing the XML output

   Default_Unknown : Natural := 0;
   --  Value used (in bytes) when there is no information about stack usage
   --  for a given subprogram.

   Default_Unbounded : Natural := 0;
   --  Value used (in bytes) when there is an unbounded stack allocation for
   --  a given subprogram.
end Options;
