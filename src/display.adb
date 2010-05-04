------------------------------------------------------------------------------
--                        STATIC STACK ANALYSIS TOOL                        --
--                                                                          --
--                              D I S P L A Y                               --
--                                                                          --
--                                 B o d y                                  --
--                                                                          --
--                     Copyright (C) 2005-2010, AdaCore                     --
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

with Options;
with Static_Stack_Analysis;
with Worst_Case_Analyzer;

with Ada.Containers;

with Ada.Text_IO;
with Ada.Integer_Text_IO;
with Ada.Strings.Fixed;

with GNAT.OS_Lib;
with GNAT.Strings;

package body Display is

   use Ada.Strings.Fixed;

   use type Static_Stack_Analysis.List_Of_Locations.Set;
   use type Static_Stack_Analysis.Name;
   use type Static_Stack_Analysis.Frame_Size;

   --------------------------
   -- Ordered entry points --
   --------------------------

   package Ordered_Entries is
     new Static_Stack_Analysis.List_Of_Node_Ids.Generic_Sorting
       (Static_Stack_Analysis.Stack_Usage_Order);
   --  This package is used for ordering edges (call-to-subprograms) according
   --  to their stack usage.

   ----------------
   -- Local data --
   ----------------

   VCG_Descriptor       : Ada.Text_IO.File_Type;
   --  File where the VCG callgraph is stored

   XML_Descriptor       : Ada.Text_IO.File_Type;
   --  File where the XML output is stored

   Undefined_Descriptor : Ada.Text_IO.File_Type;
   --  File containing undefined information (unknown stack usage, indirect
   --  calls, etc.).

   XML_Indentation : Natural := 0;
   --  Global variable that contains the required indentation in the XML file

   Indent_String : constant String := "  ";

   First_Dispatching : Boolean := True;
   --  Boolean to know whether we have already displayed information about
   --  dispatching calls.

   First_Dereferencing : Boolean := True;
   --  Boolean to know whether we have already displayed information about
   --  indirect calls.

   -----------------------
   -- Local subprograms --
   -----------------------

   procedure Generate_Output_Files;
   --  Generate a VCG file containing the annotated call graph and the file
   --  containing undefined information (unknown stack usage, indirect calls,
   --  etc.).

   procedure Print_Longest_Paths;
   --  Generate the callgraph chains that contains the longest paths with
   --  respect to stack usage. It will generate the worst case call chain for
   --  every entry point (if specific entry points have been indicated) or for
   --  every subprogram (if the flag for analyzing every subprogram has been
   --  set).

   procedure Print_Name
     (Node : Static_Stack_Analysis.Node_Class_Access);
   --  Print the subprogram name associated to the node. Depending on the
   --  active verbosity it will print only the Ada name or it will print also
   --  the symbol name and its location.

   procedure Print_Source_Name
     (Node : Static_Stack_Analysis.Node_Class_Access;
      File : Ada.Text_IO.File_Type := Ada.Text_IO.Standard_Output);
   --  Print the subprogram name associated to the node. It will use the
   --  demangled Ada/C++ name, if possible, remove path information, and use
   --  task names for task entries.

   procedure Expand_Location
     (Position : Static_Stack_Analysis.List_Of_Locations.Cursor);
   --  Print the location using the format: demangled(:|\n)file:line:column

   procedure Expand_Stack_Usage
     (Stack_Info : Static_Stack_Analysis.Stack_Usage_Info);
   --  Print the information about stack usage (local and accumulated)

   procedure Expand_Node (Position : Static_Stack_Analysis.Node_Id);
   --  Print the information about the specified node, including stack usage
   --  (and accumulated stack usage), and subprograms that are called.

   procedure Print_Unbounded (Position : Static_Stack_Analysis.Node_Id);
   --  Print the list of dynamic objects if the position corresponds to a node
   --  with a dynamic and unbounded stack usage.

   procedure Print_External (Position : Static_Stack_Analysis.Node_Id);
   --  Print the subprogram name if the position corresponds to a node with
   --  no information about stack usage.

   procedure Print_Unresolved_Indirect
     (Position : Static_Stack_Analysis.Node_Id);
   --  Print the information about unresolved indirect (including dispatching)
   --  calls made by this subprogram.

   procedure Print_Node
     (Subprogram_Name         : String;
      Local_Stack_Usage       : Static_Stack_Analysis.Stack_Usage_Info;
      Accumulated_Stack_Usage : Static_Stack_Analysis.Stack_Usage_Info;
      Locations               : Static_Stack_Analysis.List_Of_Locations.Set;
      Unresolved              : Boolean := False;
      To_Undefined_File       : Boolean := False);
   --  Print the information about this concrete subprogram with the format
   --  used by the compiler when generating call graph and stack usage
   --  information. If To_Undefined_File is True then the node is generated in
   --  an intermediate file that is used as a stub that can be later filled by
   --  the user (or any external tool). Otherwise the output is sent to the
   --  file containing the VCG call graph being generated.

   procedure Print_Edge
     (Source : String;
      Target : String;
      Loc    : Static_Stack_Analysis.Location;
      File   : Ada.Text_IO.File_Type);
   --  Print the information about this concrete call-to-subprogram with the
   --  format used by the compiler when generating call graph and stack usage
   --  information.

   procedure Print_Node (Node : Static_Stack_Analysis.Node_Class_Access);
   --  Print the information about this concrete node (name, location, stack
   --  usage, and subprogram called, depending on the verbosity chosen).

   procedure Print_Node_In_Path
     (Position : Static_Stack_Analysis.Paths.Cursor);
   --  Iterator for printing all the nodes in a path

   procedure Print_Entry (Root : Static_Stack_Analysis.Node_Class_Access);
   --  Print a summary of the stack requirements for an entry point

   procedure Print_Cycle_Id
     (Cycle : Static_Stack_Analysis.List_Of_Cycles.Cursor);
   --  Print the unique identifier associated to the cycle

   procedure Print_Cycle
     (Cycle : Static_Stack_Analysis.List_Of_Cycles.Cursor);
   --  Print the set of subprograms belonging to the cycle

   procedure Print_Biggest_Frames (Frames : Natural);
   --  Print the indicated number of subprograms corresponding to those
   --  requiring the biggest local stack usage.

   procedure Print_Dynamic_Objects
     (Position : Static_Stack_Analysis.List_Of_Locations.Cursor);
   --  Print the location of a list of dynamically sized local objects using
   --  the format: name file:line

   procedure Print_XML_Edge (Position : Static_Stack_Analysis.Edge_Id);
   --  Print the information about this call to subprogram using the format:
   --   <subprogram>
   --     <prefixname type="strings">
   --       <value>A.B.C</value>
   --     </prefixname>
   --     <locationset>
   --       ...
   --     </locationset>

   procedure Print_XML_Location
     (Position : Static_Stack_Analysis.List_Of_Locations.Cursor);
   --  Print the location using the format:
   --   <location>
   --     <subprogramname type="strings">
   --       <value>C</value>
   --     </subprogramname>
   --     <file type="strings">
   --       <value>a-b.adb</value>
   --     </file>
   --     <line type="integers">
   --       <value>1</value>
   --     </line>
   --     <column type="integers">
   --       <value>1</value>
   --     </column>
   --   </location>

   procedure Print_XML_Stack_Usage
     (Stack_Usage : Static_Stack_Analysis.Stack_Usage_Info);
   --  Print the stack usage using the format:
   --   <size type="integers">
   --     <value>102</value>
   --   </size>
   --   <qualifier>
   --     <value>STATIC</value>
   --   </qualifier>

   procedure Open_Tag (Tag_Name : String);
   procedure Close_Tag (Tag_Name : String);
   --  Puts into XML file string <Tag_Name> or </Tag_Name>. The indentation is
   --  automatically handled by the level of open tags.

   procedure Report_XML (Message : String; New_Line : Boolean := True);
   --  Sends the message into the XML output file. The message is appended with
   --  platform-specific EOL if New_Line is True. Does nothing if
   --  Generate_XML_Output is set False.

   procedure Print_Resolved_Indirect_Calls;
   --  Display the list of indirect calls (including dispatching calls) that
   --  have been resolved by either user-defined information or dispatching
   --  or signature analysis.

   ------------------------
   -- Close_Output_Files --
   ------------------------

   procedure Close_Output_Files is
   begin
      --  End of graph

      Ada.Text_IO.Put_Line (VCG_Descriptor, "}");

      --  Close all files and set the standard output

      Ada.Text_IO.Set_Output (Ada.Text_IO.Standard_Output);

      if Options.Generate_XML_Output then
         Close_Tag ("GNATstack_Information");

         Ada.Text_IO.Close (XML_Descriptor);
         GNAT.Strings.Free (Options.Output_XML);
      end if;

      --  Close the file for undefined data if it was created

      if Global_Data.External_Calls or else Global_Data.Indirect_Calls then
         Ada.Text_IO.Close (Undefined_Descriptor);
      end if;

      GNAT.Strings.Free (Options.Output_Undefined);

      Ada.Text_IO.Close (VCG_Descriptor);
      GNAT.Strings.Free (Options.Output_VCG);
   end Close_Output_Files;

   ---------------
   -- Close_Tag --
   ---------------

   procedure Close_Tag (Tag_Name : String) is
   begin
      --  Decrease indentation
      XML_Indentation := XML_Indentation - 1;

      Report_XML ("</" & Tag_Name & '>');
   end Close_Tag;

   ---------------------
   -- Expand_Location --
   ---------------------

   procedure Expand_Location
     (Position : Static_Stack_Analysis.List_Of_Locations.Cursor)
   is
      Location : constant Static_Stack_Analysis.Location :=
        Static_Stack_Analysis.List_Of_Locations.Element (Position);

      use type Ada.Text_IO.File_Access;
      use type Static_Stack_Analysis.File_Name;

   begin
      --  Demangled name

      if Location.Demangled /= null then
         Ada.Text_IO.Put (Location.Demangled.all);

         --  Separator between the Ada name and the file location

         if Ada.Text_IO.Name (Ada.Text_IO.Current_Output) =
           Ada.Text_IO.Name (Ada.Text_IO.Standard_Output)
         then
            --  Separator for the regular output
            Ada.Text_IO.Put (":");

         else
            --  Separator for the VCG files
            Ada.Text_IO.Put ("\n");
         end if;
      end if;

      --  File location

      if Location.File /= null then
         Ada.Text_IO.Put (Location.File.all & ":");
         Ada.Integer_Text_IO.Put (Location.Line_Number, 0);
         Ada.Text_IO.Put (":");
         Ada.Integer_Text_IO.Put (Location.Column_Number, 0);
      end if;

      if Static_Stack_Analysis.List_Of_Locations.Has_Element
        (Static_Stack_Analysis.List_Of_Locations.Next (Position))
      then
         --  Separator among locations

         Ada.Text_IO.Put (",");
      end if;
   end Expand_Location;

   -----------------------
   -- Open_Output_Files --
   -----------------------

   procedure Open_Output_Files is
      use type GNAT.Strings.String_Access;

      Success : Boolean;
   begin
      --  If no file has been specified as call graph output use the default
      --  graph.vcg.

      if Options.Output_VCG = null then
         --  This dinamically allocated String will be later destroyed in
         --  procedure Close_Output_Files.

         Options.Output_VCG := new String'("graph.vcg");
      end if;

      if GNAT.OS_Lib.Is_Regular_File (Options.Output_VCG.all) then
         GNAT.OS_Lib.Delete_File (Options.Output_VCG.all, Success);
         pragma Assert (Success);
      end if;

      Ada.Text_IO.Create
        (VCG_Descriptor, Ada.Text_IO.Out_File, Options.Output_VCG.all);

      --  If no file has been specified as output for undefined information
      --  use the default undefined.ciu.

      if Options.Output_Undefined = null then
         --  This dinamically allocated String will be later destroyed in
         --  procedure Close_Output_Files.

         Options.Output_Undefined := new String'("undefined.ciu");
      end if;

      if GNAT.OS_Lib.Is_Regular_File (Options.Output_Undefined.all) then
         GNAT.OS_Lib.Delete_File (Options.Output_Undefined.all, Success);
         pragma Assert (Success);
      end if;

      --  Create the file for undefined data if there is any external or
      --  indirect call to put in it.

      if Global_Data.External_Calls or else Global_Data.Indirect_Calls then
         Ada.Text_IO.Create
           (Undefined_Descriptor,
            Ada.Text_IO.Out_File,
            Options.Output_Undefined.all);
      end if;

      --  Create the file containing the XML output, if needed

      if Options.Generate_XML_Output then
         --  If no file has been specified as XML output use the default
         --  stack_usage.xml.

         if Options.Output_XML = null then
            --  This dinamically allocated String will be later destroyed in
            --  procedure Close_Output_Files.

            Options.Output_XML := new String'("stack_usage.xml");
         end if;

         if GNAT.OS_Lib.Is_Regular_File (Options.Output_XML.all) then
            GNAT.OS_Lib.Delete_File (Options.Output_XML.all, Success);
            pragma Assert (Success);
         end if;

         Ada.Text_IO.Create
           (XML_Descriptor, Ada.Text_IO.Out_File, Options.Output_XML.all);
      end if;

      --  Generate file headers

      --  Graph header

      Ada.Text_IO.Put_Line
        (VCG_Descriptor, "graph: { title: ""Callgraph information:""");

      --  XML header

      if Options.Generate_XML_Output then
         Ada.Text_IO.Put_Line (XML_Descriptor, "<?xml version=""1.0""?>");
         Open_Tag ("GNATstack_Information");
      end if;

      Ada.Text_IO.Set_Output (Ada.Text_IO.Standard_Output);
   end Open_Output_Files;

   --------------
   -- Open_Tag --
   --------------

   procedure Open_Tag (Tag_Name : String) is
   begin
      Report_XML ('<' & Tag_Name & '>');

      --  Increase indentation
      XML_Indentation := XML_Indentation + 1;
   end Open_Tag;

   --------------------------
   -- Print_Biggest_Frames --
   --------------------------

   procedure Print_Biggest_Frames (Frames : Natural) is
      function Local_Usage_Ordering
        (Left, Right : Static_Stack_Analysis.Node_Id) return Boolean;
      --  Returns True if Left has a local stack usage greater than Right,
      --  False otherwise. It is used for ordering sets of nodes according
      --  to their local stack usage (in decreasing order).

      procedure Get_Biggest_Frame
        (Position : Static_Stack_Analysis.Node_Id);
      --  Check whether this node is one of those with the biggest stack
      --  requirements and add it to the list if that is the case.

      procedure Print_Node
        (Position : Static_Stack_Analysis.List_Of_Node_Ids.Cursor);
      --  Print the subprogram name and its local stack usage

      package Ordered_Frames is
        new Static_Stack_Analysis.List_Of_Node_Ids.Generic_Sorting
          (Local_Usage_Ordering);
      --  Subprograms ordered according to their local stack usage

      Big_Frames : Static_Stack_Analysis.List_Of_Node_Ids.Vector;
      --  List of subprograms with the biggest local stack usage

      function Local_Usage_Ordering
        (Left, Right : Static_Stack_Analysis.Node_Id) return Boolean is
      begin
         return
           Static_Stack_Analysis."<"
             (Static_Stack_Analysis.Get_Stack_Usage
                (Static_Stack_Analysis.List_Of_Nodes.Element (Right).all),
              Static_Stack_Analysis.Get_Stack_Usage
                (Static_Stack_Analysis.List_Of_Nodes.Element (Left).all));
      end Local_Usage_Ordering;

      procedure Get_Biggest_Frame
        (Position : Static_Stack_Analysis.Node_Id)
      is
         Node : constant Static_Stack_Analysis.Node_Class_Access :=
           Static_Stack_Analysis.List_Of_Nodes.Element (Position);

         use type Ada.Containers.Count_Type;

      begin
         --  Add only those frames with a known stack usage and that are
         --  reachable from any entry point.

         if Node.all in Static_Stack_Analysis.Explicit_Node'Class
           and then
             (Static_Stack_Analysis.List_Of_Node_Ids.Length (Big_Frames) <
              Ada.Containers.Count_Type (Frames)
                or else
              Local_Usage_Ordering (Position, Big_Frames.Last_Element))
         then
            --  Insert the element in the list and reorder the resulting list
            --  according to the local stack consumption.

            Big_Frames.Append (Position);

            Ordered_Frames.Sort (Big_Frames);

            if Static_Stack_Analysis.List_Of_Node_Ids.Length (Big_Frames) >
               Ada.Containers.Count_Type (Frames)
            then
               --  Remove the last one. The list is already ordered so the last
               --  one is that with the smallest stack usage.

               Static_Stack_Analysis.List_Of_Node_Ids.Delete_Last (Big_Frames);
            end if;
         end if;
      end Get_Biggest_Frame;

      procedure Print_Node
        (Position : Static_Stack_Analysis.List_Of_Node_Ids.Cursor)
      is
         Node : constant Static_Stack_Analysis.Node_Class_Access :=
           Static_Stack_Analysis.List_Of_Nodes.Element
             (Static_Stack_Analysis.List_Of_Node_Ids.Element (Position));

         Stack_Info : constant Static_Stack_Analysis.Stack_Usage_Info :=
           Static_Stack_Analysis.Get_Stack_Usage (Node.all);
      begin
         Open_Tag ("frame");

         --  Subprogram name

         Print_Name (Node);

         Ada.Text_IO.Put (": ");

         --  Local stack usage

         Expand_Stack_Usage (Stack_Info);

         --  If the code is not directly reachable from any of the specified
         --  entry points we mark the subprogram as such. The subprogram may
         --  be reachable via indirect calls

         if not Node.Is_Reachable then
            Ada.Text_IO.Put (" (not directly reachable)");
         end if;

         --  Send stack information to the XML file if needed

         if Options.Generate_XML_Output then
            Open_Tag ("localstackusage");
            Print_XML_Stack_Usage (Stack_Info);
            Close_Tag ("localstackusage");
         end if;

         Close_Tag ("frame");

         Ada.Text_IO.New_Line;
      end Print_Node;

   begin
      --  Iterate the list of subprograms looking for the most stack consuming
      --  subprograms.

      Static_Stack_Analysis.List_Of_Nodes.Iterate
        (Global_Data.List_Of_Subprograms, Get_Biggest_Frame'Access);

      --  Print the results

      Static_Stack_Analysis.List_Of_Node_Ids.Iterate
        (Big_Frames, Print_Node'Access);
   end Print_Biggest_Frames;

   ---------------------------
   -- Print_Dynamic_Objects --
   ---------------------------

   procedure Print_Dynamic_Objects
     (Position : Static_Stack_Analysis.List_Of_Locations.Cursor)
   is
      Location : constant Static_Stack_Analysis.Location :=
        Static_Stack_Analysis.List_Of_Locations.Element (Position);

      use type Ada.Text_IO.File_Access;

   begin
      --  Tabulation

      Ada.Text_IO.Put ("    ");

      --  Object name

      Ada.Text_IO.Put (Location.Demangled.all);

      --  File location

      Ada.Text_IO.Put (" at ");

      Ada.Text_IO.Put (Location.File.all & ":");
      Ada.Integer_Text_IO.Put (Location.Line_Number, 0);

      Ada.Text_IO.New_Line;

      --  Print information about unbounded frames in the XML file

      if Options.Generate_XML_Output then
         Open_Tag ("unboundedobject");

         Open_Tag ("object type=""strings""");
         Report_XML (Message => "<value>", New_Line => False);
         Ada.Text_IO.Put_Line
           (XML_Descriptor, Location.Demangled.all & "</value>");
         Close_Tag ("object");

         Open_Tag ("file type=""strings""");
         Report_XML (Message => "<value>", New_Line => False);
         Ada.Text_IO.Put_Line
           (XML_Descriptor, Location.File.all & "</value>");
         Close_Tag ("file");

         Open_Tag ("line type=""integers""");
         Report_XML (Message => "<value>", New_Line => False);
         Ada.Integer_Text_IO.Put
           (XML_Descriptor, Location.Line_Number, 0);
         Ada.Text_IO.Put_Line
           (XML_Descriptor, "</value>");
         Close_Tag ("line");

         Close_Tag ("unboundedobject");
      end if;
   end Print_Dynamic_Objects;

   ----------------
   -- Print_Edge --
   ----------------

   procedure Print_Edge
     (Source : String;
      Target : String;
      Loc    : Static_Stack_Analysis.Location;
      File   : Ada.Text_IO.File_Type)
   is
      use type Static_Stack_Analysis.Location;

   begin
      --  Caller

      Ada.Text_IO.Put (File, "edge: { sourcename: """);
      Ada.Text_IO.Put (File, Source);

      --  Callee

      Ada.Text_IO.Put (File, """ targetname: """);
      Ada.Text_IO.Put (File, Target);

      --  Location

      if Loc /= Static_Stack_Analysis.Null_Location then
         Ada.Text_IO.Put (File, """ label: """);

         Ada.Text_IO.Put (File, Loc.File.all);

         if Loc.Line_Number > 0 then
            Ada.Text_IO.Put (File, ":");
            Ada.Integer_Text_IO.Put (File, Loc.Line_Number, 0);
            if Loc.Column_Number > 0 then
               Ada.Text_IO.Put (File, ":");
               Ada.Integer_Text_IO.Put (File, Loc.Column_Number, 0);
            end if;
         end if;
      end if;

      --  End of line

      Ada.Text_IO.Put_Line (File, """ }");
   end Print_Edge;

   -------------------------
   -- Print_Longest_Paths --
   -------------------------

   procedure Print_Longest_Paths is

      procedure Print_Longest_Path
        (Position : Static_Stack_Analysis.Node_Id);
      --  Print the longest path for the specified subprogram

      procedure Print_Longest_Path
        (Position : Static_Stack_Analysis.List_Of_Node_Ids.Cursor);
      --  Print the longest path for the specified entry point

      procedure Print_Longest_Path
        (Position : Static_Stack_Analysis.Node_Id)
      is
         Path : Static_Stack_Analysis.Paths.Vector :=
           Static_Stack_Analysis.Paths.Empty_Vector;

      begin
         --  Get the worst-case path

         Worst_Case_Analyzer.Get_Longest_Path (Path, Position);

         Open_Tag ("entry");

         --  Print a summary of the worst-case stack usage

         Print_Entry (Static_Stack_Analysis.List_Of_Nodes.Element (Position));

         --  Print the call chain

         if Options.Display_Call_Chains then
            Static_Stack_Analysis.Paths.Iterate
              (Path, Print_Node_In_Path'Access);
         end if;

         --  Note that this Tag is open in Print_Entry

         Close_Tag ("callchain");

         Close_Tag ("entry");

         Ada.Text_IO.New_Line;
      end Print_Longest_Path;

      procedure Print_Longest_Path
        (Position : Static_Stack_Analysis.List_Of_Node_Ids.Cursor) is
      begin
         Print_Longest_Path
           (Static_Stack_Analysis.List_Of_Node_Ids.Element (Position));
      end Print_Longest_Path;

      use type Options.Order_Type;

   begin
      --  Reorder if necessary

      if Options.Order = Options.Stack_Usage then
         --  Order entry points according to their stack consumption

         Ordered_Entries.Sort (Global_Data.Entry_Points);
      end if;

      --  Generate the worst case graph for every entry point

      Open_Tag ("entryset");

      Static_Stack_Analysis.List_Of_Node_Ids.Iterate
        (Global_Data.Entry_Points, Print_Longest_Path'Access);

      Close_Tag ("entryset");
   end Print_Longest_Paths;

   ----------------
   -- Print_Name --
   ----------------

   procedure Print_Name (Node : Static_Stack_Analysis.Node_Class_Access) is
      Locations : constant Static_Stack_Analysis.List_Of_Locations.Set :=
        Static_Stack_Analysis.Get_Location_List (Node.all);

   begin
      --  Print subprogram name

      Print_Source_Name (Node);

      --  Print symbol name in debug mode
      if Options.Debug then
         Ada.Text_IO.Put
           (" (" &
            Static_Stack_Analysis.Get_Subprogram_Name (Node.all).all &
            ")");
      end if;

      if Options.Verbose and then not Locations.Is_Empty then
         --  Location list
         Ada.Text_IO.Put (" at ");

         Static_Stack_Analysis.List_Of_Locations.Iterate
           (Locations, Expand_Location'Access);
      end if;

      --  Send subprogram name and locations to the XML file

      if Options.Generate_XML_Output then
         Open_Tag ("prefixname type=""strings""");
         Report_XML (Message => "<value>", New_Line => False);
         Print_Source_Name (Node, XML_Descriptor);
         Ada.Text_IO.Put_Line
           (XML_Descriptor, "</value>");
         Close_Tag ("prefixname");

         Open_Tag ("locationset");
         Static_Stack_Analysis.List_Of_Locations.Iterate
           (Locations, Print_XML_Location'Access);
         Close_Tag ("locationset");
      end if;
   end Print_Name;

   ----------------
   -- Print_Node --
   ----------------

   procedure Print_Node
     (Subprogram_Name         : String;
      Local_Stack_Usage       : Static_Stack_Analysis.Stack_Usage_Info;
      Accumulated_Stack_Usage : Static_Stack_Analysis.Stack_Usage_Info;
      Locations               : Static_Stack_Analysis.List_Of_Locations.Set;
      Unresolved              : Boolean := False;
      To_Undefined_File       : Boolean := False) is
   begin
      --  Generate the node line

      --  Open node

      Ada.Text_IO.Put ("node: {");

      --  Title

      Ada.Text_IO.Put (" title: """ & Subprogram_Name & '"');

      --  Label

      Ada.Text_IO.Put (" label: """);

      if not Locations.Is_Empty then
         Static_Stack_Analysis.List_Of_Locations.Iterate
           (Locations, Expand_Location'Access);

         Ada.Text_IO.Put ("\n");
      end if;

      --  Print stack usage for the subprogram

      if Unresolved and then To_Undefined_File then
         Ada.Text_IO.Put ("XXX bytes""");
      else
         Ada.Text_IO.Put ("Local: ");

         Expand_Stack_Usage (Local_Stack_Usage);

         --  Print the maximum accumulated stack usage

         Ada.Text_IO.Put ("\nAccumulated: ");

         Expand_Stack_Usage (Accumulated_Stack_Usage);

         Ada.Text_IO.Put ('"');
      end if;

      --  Shape

      if Unresolved and then not To_Undefined_File then
         Ada.Text_IO.Put (" shape : ellipse");
      end if;

      --  Close node

      Ada.Text_IO.Put_Line (" }");
   end Print_Node;

   Dispatching_Call_Mark : Boolean := False;
   --  Mark used to determine whether a call is the result of a dispatching
   --  call.

   procedure Print_Node (Node : Static_Stack_Analysis.Node_Class_Access) is
      Stack_Info : constant Static_Stack_Analysis.Stack_Usage_Info :=
        Static_Stack_Analysis.Get_Stack_Usage (Node.all);

      use type Global_Data.Phase_Type;

   begin
      --  If this is an artificial node created for dispatching calls we
      --  do not print it, but we mark that the following call is the result
      --  of a dispatching call.

      if Node.all in Static_Stack_Analysis.Dispatching_Node'Class then
         Dispatching_Call_Mark := True;

      --  Normal node
      else
         Open_Tag ("subprogram");

         --  Indentation

         Ada.Text_IO.Put (" +-> ");

         --  Dispatching indication if needed

         if Dispatching_Call_Mark then
            Ada.Text_IO.Put ("dispatching to ");
            Dispatching_Call_Mark := False;
         end if;

         --  Subprogram name

         Print_Name (Node);

         --  Print local stack usage

         if Options.Verbose then
            Ada.Text_IO.Put (" : ");

            Expand_Stack_Usage (Stack_Info);

            --  Information about cycles

            if
            not Static_Stack_Analysis.List_Of_Cycles.Is_Empty (Node.Cycles)
            then
               Ada.Text_IO.Put (" (");

               Node.Cycles.Iterate (Print_Cycle_Id'Access);

               Ada.Text_IO.Put (")");
            end if;

         elsif Global_Data.Phase = Global_Data.Print_Results and then
             (Stack_Info.Dynamic_Usage /= Static_Stack_Analysis.Empty_Value
                 or else
              Stack_Info.Unknown_Usage /= Static_Stack_Analysis.Empty_Value
                 or else
              Stack_Info.Cycle_Usage /= Static_Stack_Analysis.Empty_Value)
         then
            --  In non-verbose mode we just put a mark indicating that the
            --  resulting value is not accurate when we are printing the paths.

            Ada.Text_IO.Put (" *");
         end if;

         Close_Tag ("subprogram");

         Ada.Text_IO.New_Line;
      end if;
   end Print_Node;

   -----------------------
   -- Print_Source_Name --
   -----------------------

   procedure Print_Source_Name
     (Node : Static_Stack_Analysis.Node_Class_Access;
      File : Ada.Text_IO.File_Type := Ada.Text_IO.Standard_Output)
   is
   begin
      --  Print the symbol name (demangled), removing file information. If it
      --  is an Ada/C++ subprogram we demangle the subprogram name.

      Ada.Text_IO.Put
        (File, Static_Stack_Analysis.Get_Demangled_Name (Node.all).all);
   end Print_Source_Name;

   ----------------------
   -- Generate_Results --
   ----------------------

   procedure Generate_Results is
   begin
      --  Print subprograms ordered by local stack usage (if requested)

      if Options.Number_Of_Biggest_Frames > 0 then
         Ada.Text_IO.Put_Line ("Local stack usage information");

         Ada.Text_IO.New_Line;

         Open_Tag ("bigframeset");

         Print_Biggest_Frames (Options.Number_Of_Biggest_Frames);

         Close_Tag ("bigframeset");

         Ada.Text_IO.New_Line;
      end if;

      --  Generate the files containing the whole call graph and the undefined
      --  references.

      Generate_Output_Files;

      --  Print the stack usage information

      Ada.Text_IO.Put_Line
        ("Accumulated stack usage information for entry points");

      Ada.Text_IO.New_Line;

      Print_Longest_Paths;

      Print_Resolved_Indirect_Calls;
   end Generate_Results;

   ---------------------------
   -- Generate_Output_Files --
   ---------------------------

   procedure Generate_Output_Files is
   begin
      --  Read information about nodes and edges

      Open_Tag ("subprogramset");

      Static_Stack_Analysis.List_Of_Nodes.Iterate
        (Global_Data.List_Of_Subprograms, Expand_Node'Access);

      Close_Tag ("subprogramset");
   end Generate_Output_Files;

   -----------------------
   -- Generate_Warnings --
   -----------------------

   procedure Generate_Warnings is
      Has_Warning : Boolean := True;
      --  If true the warning switch is set.

      Has_Clarify : Boolean := False;
      --  If true, a clarify information was already displayed.

      procedure Clarify (Msg : String);
      --  Display message for clarification.  Open parenthesis or write a
      --  comma before the message.

      procedure Clarify (Msg : String) is
      begin
         if Has_Clarify then
            Ada.Text_IO.Put (", ");
         else
            Has_Clarify := True;
         end if;
         Ada.Text_IO.Put (Msg);
      end Clarify;

   begin
      --  XML section describing global application properties

      Open_Tag ("global");

      --  Analyze accuracy

      Open_Tag ("accurate type=""booleans""");

      if not Global_Data.Cycles.Is_Empty
        or else Global_Data.Unbounded_Frames
        or else Global_Data.External_Calls
        or else Global_Data.Indirect_Calls
      then
         --  Screen output

         Ada.Text_IO.New_Line;

         Ada.Text_IO.Put ("Worst case analysis is *not* accurate because of ");

         if not Global_Data.Cycles.Is_Empty then
            Clarify ("cycles");
            Has_Warning := Has_Warning and Options.Warnings (Options.Cycle);
         end if;

         if Global_Data.Unbounded_Frames then
            Clarify ("unbounded frames");
            Has_Warning := Has_Warning
              and Options.Warnings (Options.Unbounded);
         end if;

         if Global_Data.External_Calls then
            Clarify ("external calls");
            Has_Warning := Has_Warning and Options.Warnings (Options.External);

         end if;

         if Global_Data.Indirect_Calls then
            Clarify ("indirect calls");
            Has_Warning := Has_Warning and Options.Warnings (Options.Indirect);
         end if;

         Ada.Text_IO.Put (".");
         if not Has_Warning then
            Ada.Text_IO.Put (" Use -Wa for details.");
         end if;
         Ada.Text_IO.New_Line;
         Ada.Text_IO.New_Line;

         --  XML output

         Report_XML ("<value>FALSE</value>");
      else
         --  XML output

         Report_XML ("<value>TRUE</value>");
      end if;

      Close_Tag ("accurate");

      --  Information about cycles

      Open_Tag ("cycleset");

      if Options.Warnings (Options.Cycle)
        and then not Global_Data.Cycles.Is_Empty
      then
         Ada.Text_IO.Put_Line
           ("List of reachable cycles:");
         Ada.Text_IO.New_Line;
         Global_Data.Cycles.Iterate (Print_Cycle'Access);
      end if;

      Close_Tag ("cycleset");

      --  Print the list of dynamic objects whose maximum stack requirements
      --  cannot be statically computed.

      Open_Tag ("unboundedset");

      if Options.Warnings (Options.Unbounded)
        and then Global_Data.Unbounded_Frames
      then
         Ada.Text_IO.Put_Line
           ("List of reachable subprograms with dynamic unbounded frames:");
         Ada.Text_IO.New_Line;
         Global_Data.List_Of_Subprograms.Iterate
           (Print_Unbounded'Access);
         Ada.Text_IO.New_Line;
      end if;

      Close_Tag ("unboundedset");

      --  Information about subprograms for which we do not have any stack
      --  usage

      Open_Tag ("externalset");

      if Options.Warnings (Options.External)
        and then Global_Data.External_Calls
      then
         Ada.Text_IO.Put_Line
           ("List of reachable external subprograms:");
         Ada.Text_IO.New_Line;
         Global_Data.List_Of_Subprograms.Iterate (Print_External'Access);
         Ada.Text_IO.New_Line;
      end if;

      Close_Tag ("externalset");

      --  Information about indirect (including dispatching) calls

      Open_Tag ("indirectset");

      if Options.Warnings (Options.Indirect)
        and then Global_Data.Indirect_Calls
      then
         Ada.Text_IO.Put_Line
           ("List of reachable and unresolved indirect (including " &
            "dispatching) calls:");
         Ada.Text_IO.New_Line;
         Global_Data.List_Of_Subprograms.Iterate
           (Print_Unresolved_Indirect'Access);
         Ada.Text_IO.New_Line;
      end if;

      Close_Tag ("indirectset");

      Close_Tag ("global");
   end Generate_Warnings;

   -----------------
   -- Expand_Node --
   -----------------

   procedure Expand_Node (Position : Static_Stack_Analysis.Node_Id) is
      Node : constant Static_Stack_Analysis.Node_Class_Access :=
        Static_Stack_Analysis.List_Of_Nodes.Element (Position);

      Unresolved : constant Boolean :=
        Node.all in Static_Stack_Analysis.Unresolved_Node'Class;

      Stack : constant Static_Stack_Analysis.Stack_Usage_Info :=
        Static_Stack_Analysis.Get_Stack_Usage (Node.all);

      Caller : constant String :=
        Static_Stack_Analysis.Get_Subprogram_Name (Node.all).all;

      Locations : constant Static_Stack_Analysis.List_Of_Locations.Set :=
           Static_Stack_Analysis.Get_Location_List (Node.all);

      procedure Expand_Edge (Position : Static_Stack_Analysis.Edge_Id);
      --  Generate the information about this call to subprogram

      procedure Expand_Edge (Position : Static_Stack_Analysis.Edge_Id) is
         Edge   : constant Static_Stack_Analysis.Edge :=
           Static_Stack_Analysis.List_Of_Edges.Element (Position);

         Target : constant Static_Stack_Analysis.Node_Class_Access :=
           Static_Stack_Analysis.List_Of_Nodes.Element (Edge.Target);

         Callee : constant String :=
           Static_Stack_Analysis.Get_Subprogram_Name (Target.all).all;

         use type Static_Stack_Analysis.File_Name;

      begin
         --  Print both to the VCG file containing the call graph and to the
         --  file that will be later filled by the user.

         Print_Edge
           (Source => Caller,
            Target => Callee,
            Loc => Static_Stack_Analysis.Null_Location,
            File => VCG_Descriptor);

         --  Print missing information for indirect calls in the undefined.ciu
         --  file but only if the node is reachable.

         if Node.Is_Reachable and then
           Target.all in Static_Stack_Analysis.Fake_Node'Class and then
           Target.Target_Calls.Is_Empty
         then
            --  In the undefined.ciu file we put the information only if the
            --  node is reachable.

            Print_Edge
              (Source => Caller,
               Target => "XXX",
               Loc    => (if Edge.Point_Of_Call.Is_Empty then
                            Static_Stack_Analysis.Null_Location
                          else
                            Edge.Point_Of_Call.First_Element),
               File   => Undefined_Descriptor);

            --   ??? We are only printing the first element of the set of
            --  locations which should be enough to identify the call.
         end if;

      end Expand_Edge;

   --  Start of processing for Expand_Node
   begin
      --  Print both to the VCG file containing the call graph and to the file
      --  that will be later filled by the user.

      Ada.Text_IO.Set_Output (VCG_Descriptor);

      Print_Node
        (Subprogram_Name         => Caller,
         Local_Stack_Usage       => Stack,
         Accumulated_Stack_Usage => Node.Accumulated_Stack_Usage,
         Locations               => Locations,
         Unresolved              => Unresolved,
         To_Undefined_File       => False);

      --  In the undefined.ciu file we put the information only if the node
      --  is reachable.

      if Unresolved and then Node.Is_Reachable then
         Ada.Text_IO.Set_Output (Undefined_Descriptor);

         Print_Node
           (Subprogram_Name         => Caller,
            Local_Stack_Usage       => Stack,
            Accumulated_Stack_Usage => Node.Accumulated_Stack_Usage,
            Locations               => Locations,
            Unresolved              => Unresolved,
            To_Undefined_File       => True);
      end if;

      --  Generate the edges (that is, all the calls to subprogram) that have
      --  this subprogram as caller.

      Static_Stack_Analysis.List_Of_Edges.Iterate
        (Node.Target_Calls, Expand_Edge'Access);

      Ada.Text_IO.Set_Output (Ada.Text_IO.Standard_Output);

      --  Send subprogram information to the XML file

      if Options.Generate_XML_Output then
         Open_Tag ("subprogram");

         Open_Tag ("prefixname type=""strings""");
         Report_XML (Message => "<value>", New_Line => False);
         Print_Source_Name (Node, XML_Descriptor);
         Ada.Text_IO.Put_Line
           (XML_Descriptor, "</value>");
         Close_Tag ("prefixname");

         Open_Tag ("locationset");
         Static_Stack_Analysis.List_Of_Locations.Iterate
           (Locations, Print_XML_Location'Access);
         Close_Tag ("locationset");

         Open_Tag ("globalstackusage");
         Print_XML_Stack_Usage (Node.Accumulated_Stack_Usage);
         Close_Tag ("globalstackusage");

         Open_Tag ("localstackusage");
         Print_XML_Stack_Usage (Stack);
         Close_Tag ("localstackusage");

         Open_Tag ("subprogramcalledset");
         Static_Stack_Analysis.List_Of_Edges.Iterate
           (Node.Target_Calls, Print_XML_Edge'Access);
         Close_Tag ("subprogramcalledset");

         Close_Tag ("subprogram");
      end if;
   end Expand_Node;

   ------------------------
   -- Expand_Stack_Usage --
   ------------------------

   procedure Expand_Stack_Usage
     (Stack_Info : Static_Stack_Analysis.Stack_Usage_Info)
   is
      use Static_Stack_Analysis;

      Minimum_Size : constant Integer :=
        Integer (Stack_Info.Static_Usage  + Stack_Info.Dynamic_Usage +
                   Stack_Info.Unknown_Usage);
      --  Note: we do not add Cycle_Usage as it is an artificial value.

      Uncertain_Part : constant Boolean :=
        Stack_Info.Dynamic_Usage = Unspecified_Value or else
        Stack_Info.Unknown_Usage = Unspecified_Value or else
        Stack_Info.Cycle_Usage   = Unspecified_Value;

   begin
      if Minimum_Size = 0 and then Uncertain_Part then
         Ada.Text_IO.Put ("? bytes");

      elsif Minimum_Size > 0 then
         Ada.Integer_Text_IO.Put (Minimum_Size, 0);

         if Uncertain_Part then
            Ada.Text_IO.Put ("+?");
         end if;

         Ada.Text_IO.Put (" bytes");
      end if;

      --  Clarify stack usage information when we have something which is not
      --  static, or we have a cycle.

      if Options.Verbose and then
        (Stack_Info.Dynamic_Usage /= Empty_Value or else
         Stack_Info.Unknown_Usage /= Empty_Value or else
         Stack_Info.Cycle_Usage   /= Empty_Value)
      then
         Ada.Text_IO.Put (" (");

         --  Unbounded part
         if Stack_Info.Dynamic_Usage = Unspecified_Value then
            Ada.Text_IO.Put ("unbounded");

         elsif Stack_Info.Dynamic_Usage >= 0 then
            Ada.Text_IO.Put
              ("with -d" & Integer'Image (Options.Default_Unbounded));
         end if;

         --  Unknown part
         if Stack_Info.Unknown_Usage /= Empty_Value then

            if Stack_Info.Dynamic_Usage /= Empty_Value then
               Ada.Text_IO.Put (", ");
            end if;

            if Stack_Info.Unknown_Usage = Unspecified_Value then
               Ada.Text_IO.Put ("unresolved");

            elsif Stack_Info.Unknown_Usage >= 0 then
               Ada.Text_IO.Put
                 ("with -u" & Integer'Image (Options.Default_Unknown));
            end if;
         end if;

         if Stack_Info.Cycle_Usage /= Empty_Value then
            if Stack_Info.Dynamic_Usage /= Empty_Value or else
               Stack_Info.Unknown_Usage /= Empty_Value
            then
               Ada.Text_IO.Put (", ");
            end if;

            Ada.Text_IO.Put ("cycle");
         end if;

         Ada.Text_IO.Put (")");
      end if;
   end Expand_Stack_Usage;

   --------------------
   -- Increase_Count --
   --------------------

   procedure Increase_Count (Entity : Global_Data.Entities) is
      use Global_Data;

   begin
      Entities_Processed (Entity) := Entities_Processed (Entity) + 1;

      if not Options.Quiet then
         case Entity is
            when Subprogram | Call_To_Subprogram =>
               Ada.Text_IO.Put
                 ("Parsing" &
                    Natural'Image (Entities_Processed (Subprogram)) &
                    " subprograms and" &
                    Natural'Image (Entities_Processed (Call_To_Subprogram)) &
                    " calls to subprogram" & ASCII.CR);

            when Cycle =>
               Ada.Text_IO.Put
                 ("Detected" &
                    Natural'Image (Entities_Processed (Cycle)) &
                    " cycles" & ASCII.CR);
         end case;
      end if;
   end Increase_Count;

   ------------------------
   -- Print_Node_In_Path --
   ------------------------

   procedure Print_Node_In_Path
     (Position : Static_Stack_Analysis.Paths.Cursor)
   is
      Explored_Item : constant Static_Stack_Analysis.Path_Element :=
        Static_Stack_Analysis.Paths.Element (Position);

   begin
      --  Print node

      if
        Static_Stack_Analysis.List_Of_Nodes.Has_Element
          (Explored_Item.Source_Node)
      then
         Print_Node
           (Static_Stack_Analysis.List_Of_Nodes.Element
              (Explored_Item.Source_Node));
      end if;
   end Print_Node_In_Path;

   ----------------
   -- Print_Path --
   ----------------

   procedure Print_Entry (Root : Static_Stack_Analysis.Node_Class_Access) is
      Task_Wrapper : Static_Stack_Analysis.Node_Class_Access := null;

      Is_Task : Boolean;

      Accumulated_Stack : Static_Stack_Analysis.Stack_Usage_Info;

      use type Static_Stack_Analysis.Stack_Usage_Info;
      use type Static_Stack_Analysis.Node_Class_Access;

   begin
      --  Print the global information

      Is_Task :=
        Global_Data.Is_Task_Entry
          (Static_Stack_Analysis.Get_Subprogram_Name (Root.all));

      if Is_Task then
         --  This is an Ada task

         Ada.Text_IO.Put ("Task ");
      end if;

      Print_Source_Name (Root);

      Ada.Text_IO.Put (" : total ");

      --  For tasks we need to add the task wrapper

      if Is_Task and then
        Static_Stack_Analysis.List_Of_Nodes.Has_Element
          (Global_Data.Task_Wrapper)
      then
         Task_Wrapper :=
           Static_Stack_Analysis.List_Of_Nodes.Element
             (Global_Data.Task_Wrapper);

         Accumulated_Stack :=
           (Static_Stack_Analysis.Get_Accumulated_Stack_Usage (Root.all) +
            Static_Stack_Analysis.Get_Stack_Usage (Task_Wrapper.all));

      else
         Accumulated_Stack :=
           Static_Stack_Analysis.Get_Accumulated_Stack_Usage (Root.all);
      end if;

      Expand_Stack_Usage (Accumulated_Stack);

      Ada.Text_IO.New_Line;

      --  Print entry point information to the XML file

      if Options.Generate_XML_Output then
         Open_Tag ("prefixname type=""strings""");
         Report_XML (Message => "<value>", New_Line => False);
         Print_Source_Name (Root, XML_Descriptor);
         Ada.Text_IO.Put_Line
           (XML_Descriptor, "</value>");
         Close_Tag ("prefixname");

         Open_Tag ("locationset");
         Static_Stack_Analysis.List_Of_Locations.Iterate
           (Static_Stack_Analysis.Get_Location_List (Root.all),
            Print_XML_Location'Access);
         Close_Tag ("locationset");

         Open_Tag ("localstackusage");
         Print_XML_Stack_Usage (Accumulated_Stack);
         Close_Tag ("localstackusage");
      end if;

      --  Note that this Tag is closed in Print_Longest_Path

      Open_Tag ("callchain");

      if Task_Wrapper /= null then
         --  Print the frame for the task wrapper
         Open_Tag ("subprogram");
         Print_Node (Task_Wrapper);
         Close_Tag ("subprogram");
      end if;
   end Print_Entry;

   -----------------
   -- Print_Cycle --
   -----------------

   procedure Print_Cycle
     (Cycle : Static_Stack_Analysis.List_Of_Cycles.Cursor)
   is
      Path : constant Static_Stack_Analysis.Paths.Vector :=
        Static_Stack_Analysis.List_Of_Cycles.Element (Cycle).Path;

      Root : constant Static_Stack_Analysis.Paths.Cursor :=
        Static_Stack_Analysis.Paths.First (Path);

   begin
      Open_Tag ("cycle");

      Print_Cycle_Id (Cycle);

      Ada.Text_IO.Put (" ");

      Print_Source_Name
        (Static_Stack_Analysis.List_Of_Nodes.Element
           (Static_Stack_Analysis.Paths.Element (Root).Source_Node));

      Ada.Text_IO.New_Line;

      --  Print the call chain

      Static_Stack_Analysis.Paths.Iterate (Path, Print_Node_In_Path'Access);

      --  We repeat the first node just for clarity

      Print_Node_In_Path (Root);

      Ada.Text_IO.New_Line;

      Close_Tag ("cycle");
   end Print_Cycle;

   --------------------
   -- Print_Cycle_Id --
   --------------------

   procedure Print_Cycle_Id
     (Cycle : Static_Stack_Analysis.List_Of_Cycles.Cursor) is
   begin
      Ada.Text_IO.Put ("<c");

      Ada.Integer_Text_IO.Put
        (Static_Stack_Analysis.List_Of_Cycles.Element (Cycle).Id, 0);

      Ada.Text_IO.Put (">");
   end Print_Cycle_Id;

   --------------------
   -- Print_External --
   --------------------

   procedure Print_External (Position : Static_Stack_Analysis.Node_Id) is
      Node : constant Static_Stack_Analysis.Node_Class_Access :=
        Static_Stack_Analysis.List_Of_Nodes.Element (Position);

   begin
      --  If the code is not directly reachable from any of the specified
      --  entry points we do not display this node (although the subprogram may
      --  be reachable via indirect calls).

      if Node.all in Static_Stack_Analysis.Unresolved_Node'Class
        and then Node.Is_Reachable then
         Ada.Text_IO.Put ("  ");

         Open_Tag ("external");

         Print_Name (Node);

         Close_Tag ("external");

         Ada.Text_IO.New_Line;
      end if;
   end Print_External;

   -----------------------------------
   -- Print_Resolved_Indirect_Calls --
   -----------------------------------

   procedure Print_Resolved_Indirect_Calls is
      use Static_Stack_Analysis;

      Caller : Node_Class_Access;

      First_Local_Dispatching : Boolean := True;

      First_Local_Dereferencing : Boolean := True;

      procedure Print_Targets (Position : Static_Stack_Analysis.Edge_Id);
      --  Print the list of targets that resolve an indirect call

      procedure Print_Targets (Position : Static_Stack_Analysis.Edge_Id) is
         Call : constant Edge := List_Of_Edges.Element (Position);

         Callee_Ptr : constant Node_Class_Access :=
           List_Of_Nodes.Element (Call.Target);

      begin
         --  Put indentation

         Ada.Text_IO.Put ("    +-> ");

         --  Subprogram name

         Print_Name (Callee_Ptr);

         Ada.Text_IO.New_Line;
      end Print_Targets;

      procedure Print_Dispatching_Callers
        (Position : Static_Stack_Analysis.Node_Id);
      --  Print the list of subprograms performing dispatching calls

      procedure Print_Dereference_Callers
        (Position : Static_Stack_Analysis.Node_Id);
      --  Print the list of subprograms performing dereferences to
      --  access-to-subprogram values.

      procedure Print_Dispatching_Targets
        (Position : Static_Stack_Analysis.Edge_Id);
      --  Print the list of potential targets for every dispatching call

      procedure Print_Dereference_Targets
        (Position : Static_Stack_Analysis.Edge_Id);
      --  Print the list of potential targets for every indirect call

      procedure Print_Dispatching_Targets
        (Position : Static_Stack_Analysis.Edge_Id)
      is
         Call   : constant Edge := List_Of_Edges.Element (Position);

         Target : constant Node_Class_Access :=
           List_Of_Nodes.Element (Call.Target);

      begin
         if Target.all in Dispatching_Node'Class
           and then not Target.Target_Calls.Is_Empty
         then
            if First_Dispatching then
               First_Dispatching := False;
               Ada.Text_IO.Put_Line
                 ("List of dispatching calls resolved by analysis");
               Ada.Text_IO.New_Line;
            end if;

            if First_Local_Dispatching then
               First_Local_Dispatching := False;
               Ada.Text_IO.Put ("From subprogram ");
               Print_Name (Caller);
               Ada.Text_IO.Put_Line (":");
               Ada.Text_IO.New_Line;
            end if;

            --  Print the location of the call

            if Call.Point_Of_Call.Is_Empty then
               Ada.Text_IO.Put ("  Indirect call");
            else
               --  Location list
               Ada.Text_IO.Put ("  Call at ");

               Static_Stack_Analysis.List_Of_Locations.Iterate
                 (Call.Point_Of_Call, Expand_Location'Access);
            end if;

            Ada.Text_IO.Put (" may dispatch to:");
            Ada.Text_IO.New_Line;

            List_Of_Edges.Iterate (Target.Target_Calls, Print_Targets'Access);

            Ada.Text_IO.New_Line;
         end if;
      end Print_Dispatching_Targets;

      procedure Print_Dereference_Targets
        (Position : Static_Stack_Analysis.Edge_Id)
      is
         Call   : constant Edge := List_Of_Edges.Element (Position);

         Target : constant Node_Class_Access :=
           List_Of_Nodes.Element (Call.Target);

      begin
         if Target.all in Indirect_Node'Class
           and then not Target.Target_Calls.Is_Empty
         then
            if First_Dereferencing then
               First_Dereferencing := False;
               Ada.Text_IO.Put_Line
                 ("List of dereference calls resolved by manual information");
               Ada.Text_IO.New_Line;
            end if;

            if First_Local_Dereferencing then
               First_Local_Dereferencing := False;
               Ada.Text_IO.Put ("From subprogram ");
               Print_Name (Caller);
               Ada.Text_IO.Put_Line (":");
            end if;

            --  Print the location of the call

            if Call.Point_Of_Call.Is_Empty then
               Ada.Text_IO.Put ("  Indirect call");
            else
               --  Location list
               Ada.Text_IO.Put ("  Call at ");

               Static_Stack_Analysis.List_Of_Locations.Iterate
                 (Call.Point_Of_Call, Expand_Location'Access);
            end if;

            Ada.Text_IO.Put (" may dereference:");
            Ada.Text_IO.New_Line;

            List_Of_Edges.Iterate (Target.Target_Calls, Print_Targets'Access);

            Ada.Text_IO.New_Line;
         end if;
      end Print_Dereference_Targets;

      procedure Print_Dispatching_Callers
        (Position : Static_Stack_Analysis.Node_Id) is
      begin
         Caller := List_Of_Nodes.Element (Position);

         if Caller.all in Explicit_Node'Class then
            First_Local_Dispatching := True;

            List_Of_Edges.Iterate
              (Caller.Target_Calls, Print_Dispatching_Targets'Access);
         end if;
      end Print_Dispatching_Callers;

      procedure Print_Dereference_Callers
        (Position : Static_Stack_Analysis.Node_Id) is
      begin
         Caller := List_Of_Nodes.Element (Position);

         if Caller.all in Explicit_Node'Class then
            First_Local_Dereferencing := True;

            List_Of_Edges.Iterate
              (Caller.Target_Calls, Print_Dereference_Targets'Access);
         end if;
      end Print_Dereference_Callers;

      use type Options.Target_Resolution_Options;

   --  Start of processing for Print_Resolved_Indirect_Calls
   begin
      if Options.Target_Resolution = Options.Dispatching_Calls or else
        Options.Target_Resolution = Options.Both
      then
         --  Iterate the list of subprograms looking for dispatching calls and
         --  print the potential targets for each if they have been computed.

         List_Of_Nodes.Iterate
           (Global_Data.List_Of_Subprograms, Print_Dispatching_Callers'Access);
      end if;

      if Options.Target_Resolution = Options.Indirect_Calls or else
        Options.Target_Resolution = Options.Both
      then
         --  Iterate the list of subprograms looking for dereferences to
         --  access-to-subprogram values and print the potential targets for
         --  each.

         List_Of_Nodes.Iterate
           (Global_Data.List_Of_Subprograms, Print_Dereference_Callers'Access);
      end if;
   end Print_Resolved_Indirect_Calls;

   -------------------------------
   -- Print_Unresolved_Indirect --
   -------------------------------

   procedure Print_Unresolved_Indirect
     (Position : Static_Stack_Analysis.Node_Id)
   is
      Node : constant Static_Stack_Analysis.Node_Class_Access :=
        Static_Stack_Analysis.List_Of_Nodes.Element (Position);

      Indirect_Calls : constant Static_Stack_Analysis.List_Of_Edges.Vector :=
        Static_Stack_Analysis.Get_Indirect_Calls
          (Node.all,
           Static_Stack_Analysis.Both,
           Static_Stack_Analysis.Unresolved);
      --  Set of locations where there is an indirect call within the
      --  subprogram being analyzed.

      procedure Print_Location
        (Position : Static_Stack_Analysis.List_Of_Edges.Cursor);
      --  Print the location of the represented calls using the format:
      --  file:line.

      procedure Print_Location
        (Position : Static_Stack_Analysis.List_Of_Edges.Cursor)
      is
         Call : constant Static_Stack_Analysis.Edge :=
           Static_Stack_Analysis.List_Of_Edges.Element (Position);

         Location : constant Static_Stack_Analysis.Location :=
           (if Call.Point_Of_Call.Is_Empty then
               Static_Stack_Analysis.Null_Location
            else
               Call.Point_Of_Call.First_Element);

         use type Static_Stack_Analysis.Location;
         use type Static_Stack_Analysis.File_Name;
      begin
         --  Do not print anything if the location is empty

         if Location /= Static_Stack_Analysis.Null_Location
           and then Location.File /= null
         then
            --  File location

            Ada.Text_IO.Put ("    at " & Location.File.all & ":");
            Ada.Integer_Text_IO.Put (Location.Line_Number, 0);
            Ada.Text_IO.New_Line;

            --  Print location to the XML file

            if Options.Generate_XML_Output then
               Open_Tag ("indirectcall");

               Open_Tag ("file type=""strings""");
               Report_XML (Message => "<value>", New_Line => False);
               Ada.Text_IO.Put_Line
                 (XML_Descriptor, Location.File.all & "</value>");
               Close_Tag ("file");

               Open_Tag ("line type=""integers""");
               Report_XML (Message => "<value>", New_Line => False);
               Ada.Integer_Text_IO.Put
                 (XML_Descriptor, Location.Line_Number, 0);
               Ada.Text_IO.Put_Line
                 (XML_Descriptor, "</value>");
               Close_Tag ("line");

               Close_Tag ("indirectcall");
            end if;
         end if;
      end Print_Location;

   begin
      --  If the code is not directly reachable from any of the specified
      --  entry points we do not display this node (although the subprogram may
      --  be reachable via indirect calls).

      if not Indirect_Calls.Is_Empty and then Node.Is_Reachable then
         Ada.Text_IO.Put ("  ");

         Ada.Integer_Text_IO.Put (Integer (Indirect_Calls.Length), 0);

         if Integer (Indirect_Calls.Length) > 1 then
            Ada.Text_IO.Put (" indirect calls in: ");
         else
            Ada.Text_IO.Put (" indirect call in: ");
         end if;

         Open_Tag ("indirect");

         Print_Name (Node);

         Ada.Text_IO.New_Line;

         Open_Tag ("indirectcallset");

         Static_Stack_Analysis.List_Of_Edges.Iterate
           (Indirect_Calls, Print_Location'Access);

         Close_Tag ("indirectcallset");

         Close_Tag ("indirect");
      end if;
   end Print_Unresolved_Indirect;

   ---------------------
   -- Print_Unbounded --
   ---------------------

   procedure Print_Unbounded (Position : Static_Stack_Analysis.Node_Id) is
      Node : constant Static_Stack_Analysis.Node_Class_Access :=
        Static_Stack_Analysis.List_Of_Nodes.Element (Position);

      use Static_Stack_Analysis;

   begin
      --  If the code is not directly reachable from any of the specified
      --  entry points we do not display this node (although the subprogram may
      --  be reachable via indirect calls).

      if Get_Stack_Usage (Node.all).Frame_Type = Unbounded
        and then Node.Is_Reachable
      then
         Ada.Text_IO.Put ("  In ");

         Open_Tag ("unbounded");

         Print_Name (Node);

         Ada.Text_IO.New_Line;

         Open_Tag ("unboundedobjectset");

         Static_Stack_Analysis.List_Of_Locations.Iterate
           (Static_Stack_Analysis.Explicit_Node (Node.all).Dynamic_Objects,
            Print_Dynamic_Objects'Access);

         Close_Tag ("unboundedobjectset");

         Close_Tag ("unbounded");
      end if;
   end Print_Unbounded;

   --------------------
   -- Print_XML_Edge --
   --------------------

   procedure Print_XML_Edge (Position : Static_Stack_Analysis.Edge_Id) is
      Target : constant Static_Stack_Analysis.Node_Class_Access :=
        Static_Stack_Analysis.List_Of_Nodes.Element
          (Static_Stack_Analysis.List_Of_Edges.Element (Position).Target);

      Locations : constant Static_Stack_Analysis.List_Of_Locations.Set :=
           Static_Stack_Analysis.Get_Location_List (Target.all);

   begin
      Open_Tag ("subprogram");

      Open_Tag ("prefixname type=""strings""");
      Report_XML (Message => "<value>", New_Line => False);
      Print_Source_Name (Target, XML_Descriptor);
      Ada.Text_IO.Put_Line
        (XML_Descriptor, "</value>");
      Close_Tag ("prefixname");

      Open_Tag ("locationset");
      Static_Stack_Analysis.List_Of_Locations.Iterate
        (Locations, Print_XML_Location'Access);
      Close_Tag ("locationset");

      Close_Tag ("subprogram");
   end Print_XML_Edge;

   ------------------------
   -- Print_XML_Location --
   ------------------------

   procedure Print_XML_Location
     (Position : Static_Stack_Analysis.List_Of_Locations.Cursor)
   is
      Location : constant Static_Stack_Analysis.Location :=
        Static_Stack_Analysis.List_Of_Locations.Element (Position);

      use type Static_Stack_Analysis.File_Name;

   begin
      Open_Tag ("location");

      if Location.Demangled /= null then
         Open_Tag ("subprogramname type=""strings""");
         Report_XML (Message => "<value>", New_Line => False);
         Ada.Text_IO.Put_Line
           (XML_Descriptor, Location.Demangled.all & "</value>");
         Close_Tag ("subprogramname");
      end if;

      if Location.File /= null then
         Open_Tag ("file type=""strings""");
         Report_XML (Message => "<value>", New_Line => False);
         Ada.Text_IO.Put_Line
           (XML_Descriptor, Location.File.all & "</value>");
         Close_Tag ("file");

         Open_Tag ("line type=""integers""");
         Report_XML (Message => "<value>", New_Line => False);
         Ada.Integer_Text_IO.Put
           (XML_Descriptor, Location.Line_Number, 0);
         Ada.Text_IO.Put_Line
           (XML_Descriptor, "</value>");
         Close_Tag ("line");

         Open_Tag ("column type=""integers""");
         Report_XML (Message => "<value>", New_Line => False);
         Ada.Integer_Text_IO.Put
           (XML_Descriptor, Location.Column_Number, 0);
         Ada.Text_IO.Put_Line
           (XML_Descriptor, "</value>");
         Close_Tag ("column");
      end if;

      Close_Tag ("location");
   end Print_XML_Location;

   ---------------------------
   -- Print_XML_Stack_Usage --
   ---------------------------

   procedure Print_XML_Stack_Usage
     (Stack_Usage : Static_Stack_Analysis.Stack_Usage_Info)
   is
   begin
      Open_Tag ("size type=""integers""");
      Report_XML (Message => "<value>", New_Line => False);
      Ada.Integer_Text_IO.Put
        (XML_Descriptor, Integer (Stack_Usage.Static_Usage), 0);
      Ada.Text_IO.Put_Line
        (XML_Descriptor, "</value>");
      Close_Tag ("size");

      Open_Tag ("qualifier");
      Report_XML
        ("<value>" &
         Static_Stack_Analysis.Stack_Usage'Image (Stack_Usage.Frame_Type) &
         "</value>");
      Close_Tag ("qualifier");
   end Print_XML_Stack_Usage;

   ----------------
   -- Report_XML --
   ----------------

   procedure Report_XML (Message : String; New_Line : Boolean := True) is
   begin

      if Options.Generate_XML_Output then
         Ada.Text_IO.Put
           (XML_Descriptor, XML_Indentation * Indent_String & Message);

         if New_Line then
            Ada.Text_IO.New_Line (XML_Descriptor);
         end if;
      end if;

   end Report_XML;
end Display;
