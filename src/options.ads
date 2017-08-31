------------------------------------------------------------------------------
--                        STATIC STACK ANALYSIS TOOL                        --
--                                                                          --
--                              O P T I O N S                               --
--                                                                          --
--                                 S p e c                                  --
--                                                                          --
--                     Copyright (C) 2005-2017, AdaCore                     --
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

with GNAT.Strings;

with Static_Stack_Analysis;

package Options is

   Verbose : Boolean := False;
   --  Verbose output

   Debug : Boolean := False;
   --  Debug output

   Progress_Information : Boolean := False;
   --  Print progress information

   Very_Quiet : Boolean := False;
   --  No console output at all

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

   type Target_Resolution_Options is
     (None, Indirect_Calls, Dispatching_Calls, Both);

   Target_Resolution : Target_Resolution_Options := None;
   --  Determines whether we want to display information about indirect and
   --  dispatching calls resolved using either compiler-generated or manual
   --  information.

   Display_Call_Chains : Boolean := True;
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

   Default_Unknown : Integer := Static_Stack_Analysis.Unspecified_Value;
   --  Value used (in bytes) when there is no information about stack usage
   --  for a given subprogram.

   Default_Unbounded : Integer := Static_Stack_Analysis.Unspecified_Value;
   --  Value used (in bytes) when there is an unbounded stack allocation for
   --  a given subprogram.

   Default_Cycle : Integer := Static_Stack_Analysis.Unspecified_Value;
   --  Value used (in bytes) for subprograms in a cycle.

   Objcopy_Cmd : GNAT.Strings.String_Access := new String'("objcopy");
   --  Name of the objcopy (including the prefix/suffix) to be used to extract
   --  .ci info from objects. This command can be changed with the -oc option.

   Remove_Temporary_Files : Boolean := True;
   --  Indicates whether we remove the temporary files created by GNATstack
   --  (if any) or not. This option can be changed with the -k option.

   Section_Name : GNAT.Strings.String_Access := new String'(".GNU.callgraph");
   --  Name of the section where the .ci information is stored in the object
   --  file. This value can be changed with the -s option.

   Runtime : GNAT.Strings.String_Access := null;
   --  Name of the run-time library used

   Project : GNAT.Strings.String_Access := null;
   --  Name of the project file used

   Target : GNAT.Strings.String_Access := null;
   --  Name of the prefix for cross compilers

end Options;
