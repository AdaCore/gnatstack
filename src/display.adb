------------------------------------------------------------------------------
--                        STATIC STACK ANALYSIS TOOL                        --
--                                                                          --
--                              D I S P L A Y                               --
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

with Options;
--  Used for Output_VCG
--           Explore_All
--           Verbose
--           Order
--           Warnings

with Static_Stack_Analysis;
--  Used for List_Of_Locations
--           List_Of_Subprograms
--           List_Of_Nodes
--           List_Of_Edges
--           Get_Stack_Usage
--           Get_Subprogram_Name
--           Phase

with Call_Graphs;
--  Used for Extract_Cycles

with Worst_Case_Analyzer;
--  Used for Get_Longest_Path

with Ada.Text_IO;
--  Used for Create
--           Close
--           Put
--           Put_Line

with Ada.Containers;
--  Used for Count_Type

with Ada.Integer_Text_IO;
--  Used for Put

with GNAT.OS_Lib;
--  Used for Delete_File

with GNAT.Strings;
--  Used for String_Access

with GNAT.Regpat;
--  Used for Match

package body Display is

   use type Static_Stack_Analysis.List_Of_Locations.Set;
   use type Static_Stack_Analysis.Subprogram_Name;
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

   VCG_Descriptor : Ada.Text_IO.File_Type;
   --  File where the VCG callgraph is stored

   Undefined_Descriptor : Ada.Text_IO.File_Type;
   --  File containing undefined information (unknown stack usage, indirect
   --  calls, etc.).

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

   procedure Print_Ada_Name
     (Node : Static_Stack_Analysis.Node_Class_Access);
   --  Print the subprogram name associated to the node. It will use the
   --  demangled Ada name, if possible, remove path information, and use task
   --  names for task entries.

   procedure Expand_Location
        (Position : Static_Stack_Analysis.List_Of_Locations.Cursor);
   --  Print the location using the format: demangled(:|\n)file:line:column

   procedure Expand_Stack_Usage
     (Stack_Info : Static_Stack_Analysis.Stack_Usage_Info);
   --  Print the information about stack usage (local and accumulated)

   procedure Expand_Node (Position : in Static_Stack_Analysis.Node_Id);
   --  Print the information about the specified node, including stack usage
   --  (and accumulated stack usage), and subprograms that are called.

   procedure Print_Unbounded (Position : in Static_Stack_Analysis.Node_Id);
   --  Print the subprogram name if the position corresponds to a node with a
   --  dynamic and unbounded stack usage.

   procedure Print_External (Position : in Static_Stack_Analysis.Node_Id);
   --  Print the subprogram name if the position corresponds to a node with
   --  no information about stack usage.

   procedure Print_Indirect (Position : in Static_Stack_Analysis.Node_Id);
   --  Print the information about indirect (including dispatching) calls made
   --  by this subprogram.

   procedure Print_Node
     (Subprogram_Name          : String;
      Local_Stack_Usage       : in Static_Stack_Analysis.Stack_Usage_Info;
      Accumulated_Stack_Usage : in Static_Stack_Analysis.Stack_Usage_Info;
      Locations               : in Static_Stack_Analysis.List_Of_Locations.Set;
      Unresolved              : in Boolean := False;
      To_Undefined_File       : in Boolean := False);
   --  Print the information about this concrete subprogram with the format
   --  used by the compiler when generating call graph and stack usage
   --  information. If To_Undefined_File is True then the node is generated in
   --  an intermediate file that is used as a stub that can be later filled by
   --  the user (or any external tool). Otherwise the output is sent to the
   --  file containing the VCG call graph being generated.

   procedure Print_Edge (Source : in String; Target : in String);
   --  Print the information about this concrete call-to-subprogram with the
   --  format used by the compiler when generating call graph and stack usage
   --  information.

   procedure Print_Node (Node : Static_Stack_Analysis.Node_Class_Access);
   --  Print the information about this concrete node (name, location, stack
   --  usage, and subprogram called, depending on the verbosity chosen).

   procedure Print_Node_In_Path
     (Position : in Static_Stack_Analysis.Paths.Cursor);
   --  Iterator for printing all the nodes in a path

   procedure Print_Entry (Root : Static_Stack_Analysis.Node_Class_Access);
   --  Print a summary of the stack requirements for an entry point

   procedure Print_Cycle_Id
     (Cycle : in Static_Stack_Analysis.List_Of_Cycles.Cursor);
   --  Print the unique identifier associated to the cycle

   procedure Print_Cycle
     (Cycle : in Static_Stack_Analysis.List_Of_Cycles.Cursor);
   --  Print the set of subprograms belonging to the cycle

   procedure Print_Biggest_Frames (Frames : Natural);
   --  Print the indicated number of subprograms corresponding to those
   --  requiring the biggest local stack usage.

   ---------------------
   -- Expand_Location --
   ---------------------

   procedure Expand_Location
     (Position : Static_Stack_Analysis.List_Of_Locations.Cursor)
   is
      Location : constant Static_Stack_Analysis.Location :=
        Static_Stack_Analysis.List_Of_Locations.Element (Position);

      use type Ada.Text_IO.File_Access;

   begin
      --  Demangled name

      Ada.Text_IO.Put (Location.Demangled.all);

      --  Separator between the Ada name and the file location

      if Ada.Text_IO.Is_Open (VCG_Descriptor) then
         --  Separator for the VCG file

         Ada.Text_IO.Put ("\n");

      else
         Ada.Text_IO.Put (":");
      end if;

      --  File location

      Ada.Text_IO.Put (Location.File.all & ":");
      Ada.Integer_Text_IO.Put (Location.Line_Number, 0);
      Ada.Text_IO.Put (":");
      Ada.Integer_Text_IO.Put (Location.Column_Number, 0);

      if Static_Stack_Analysis.List_Of_Locations.Has_Element
        (Static_Stack_Analysis.List_Of_Locations.Next (Position))
      then
         --  Separator among locations

         Ada.Text_IO.Put (",");
      end if;
   end Expand_Location;

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
        (Position : in Static_Stack_Analysis.Node_Id);
      --  Check whether this node is one of those with the biggest stack
      --  requirements and add it to the list if that is the case.

      procedure Print_Node
        (Position : in Static_Stack_Analysis.List_Of_Node_Ids.Cursor);
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
        (Position : in Static_Stack_Analysis.Node_Id)
      is
         Node : constant Static_Stack_Analysis.Node_Class_Access :=
           Static_Stack_Analysis.List_Of_Nodes.Element (Position);

         use type Ada.Containers.Count_Type;

      begin
         --  Add only those frames with a known stack usage and that are
         --  reachable from any entry point.

         if Node.all in Static_Stack_Analysis.Explicit_Node'Class
           and then
             Node.Analysis_Finished
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
        (Position : in Static_Stack_Analysis.List_Of_Node_Ids.Cursor)
      is
         Node : constant Static_Stack_Analysis.Node_Class_Access :=
           Static_Stack_Analysis.List_Of_Nodes.Element
             (Static_Stack_Analysis.List_Of_Node_Ids.Element (Position));

      begin
         --  Subprogram name

         Print_Name (Node);

         Ada.Text_IO.Put (": ");

         --  Local stack usage

         Expand_Stack_Usage (Static_Stack_Analysis.Get_Stack_Usage (Node.all));

         Ada.Text_IO.New_Line;
      end Print_Node;

   begin
      --  Iterate the list of subprograms looking for the most stack consumming
      --  subprograms.

      Static_Stack_Analysis.List_Of_Nodes.Iterate
        (Static_Stack_Analysis.List_Of_Subprograms, Get_Biggest_Frame'Access);

      --  Print the results

      Static_Stack_Analysis.List_Of_Node_Ids.Iterate
        (Big_Frames, Print_Node'Access);
   end Print_Biggest_Frames;

   ----------------
   -- Print_Edge --
   ----------------

   procedure Print_Edge (Source : in String; Target : in String) is
   begin
      --  Caller

      Ada.Text_IO.Put ("edge: { sourcename: """);
      Ada.Text_IO.Put (Source);

      --  Callee

      Ada.Text_IO.Put (""" targetname: """);
      Ada.Text_IO.Put (Target);

      --  Type of line

      Ada.Text_IO.Put_Line (""" priority: 100 linestyle: solid }");
   end Print_Edge;

   -------------------------
   -- Print_Longest_Paths --
   -------------------------

   procedure Print_Longest_Paths is

      procedure Print_Longest_Path
        (Position : in Static_Stack_Analysis.Node_Id);
      --  Print the longest path for the specified subprogram

      procedure Print_Longest_Path
        (Position : in Static_Stack_Analysis.List_Of_Node_Ids.Cursor);
      --  Print the longest path for the specified entry point

      procedure Print_Longest_Path
        (Position : in Static_Stack_Analysis.Node_Id)
      is
         Path : Static_Stack_Analysis.Paths.Vector :=
           Static_Stack_Analysis.Paths.Empty_Vector;

      begin
         --  Get the worst-case path

         Worst_Case_Analyzer.Get_Longest_Path (Path, Position);

         --  Print a summary of the worst-case stack usage

         Print_Entry (Static_Stack_Analysis.List_Of_Nodes.Element (Position));

         --  Print the call chain

         if Options.Display_Call_Chains then
            Static_Stack_Analysis.Paths.Iterate
              (Path, Print_Node_In_Path'Access);
         end if;

         Ada.Text_IO.New_Line;
      end Print_Longest_Path;

      procedure Print_Longest_Path
        (Position : in Static_Stack_Analysis.List_Of_Node_Ids.Cursor) is
      begin
         Print_Longest_Path
           (Static_Stack_Analysis.List_Of_Node_Ids.Element (Position));
      end Print_Longest_Path;

      use type Options.Order_Type;

   begin
      --  Reorder if necessary

      if Options.Order = Options.Stack_Usage then
         --  Order entry points according to their stack consumption

         Ordered_Entries.Sort (Static_Stack_Analysis.Entry_Points);
      end if;

      --  Generate the worst case graph for every entry point

      Static_Stack_Analysis.List_Of_Node_Ids.Iterate
        (Static_Stack_Analysis.Entry_Points, Print_Longest_Path'Access);
   end Print_Longest_Paths;

   ----------------
   -- Print_Name --
   ----------------

   procedure Print_Name (Node : Static_Stack_Analysis.Node_Class_Access) is
   begin
      if Options.Verbose then
         --  Symbol name

         Ada.Text_IO.Put
           (Static_Stack_Analysis.Get_Subprogram_Name (Node.all).all);

         --  Location list
         Ada.Text_IO.Put (" at ");

         Static_Stack_Analysis.List_Of_Locations.Iterate
           (Static_Stack_Analysis.Get_Location_List (Node.all),
            Expand_Location'Access);

      else
         --  Print subprogram name

         Print_Ada_Name (Node);
      end if;
   end Print_Name;

   ----------------
   -- Print_Node --
   ----------------

   procedure Print_Node
     (Subprogram_Name         : in String;
      Local_Stack_Usage       : in Static_Stack_Analysis.Stack_Usage_Info;
      Accumulated_Stack_Usage : in Static_Stack_Analysis.Stack_Usage_Info;
      Locations               : in Static_Stack_Analysis.List_Of_Locations.Set;
      Unresolved              : in Boolean := False;
      To_Undefined_File       : in Boolean := False) is
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

   procedure Print_Node (Node : Static_Stack_Analysis.Node_Class_Access) is
      Stack_Info : constant Static_Stack_Analysis.Stack_Usage_Info :=
        Static_Stack_Analysis.Get_Stack_Usage (Node.all);

      use type Static_Stack_Analysis.Phase_Type;

   begin
      --  Indentation

      Ada.Text_IO.Put (" +-> ");

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

      elsif Static_Stack_Analysis.Phase = Static_Stack_Analysis.Print_Results
        and then
      (Stack_Info.Dynamic_Usage /= Static_Stack_Analysis.No_Value
       or else Stack_Info.Unknown_Usage /= Static_Stack_Analysis.No_Value
       or else Stack_Info.Cycle_Usage /= Static_Stack_Analysis.No_Value)
      then
         --  In non-verbose mode we just put a mark indicating that the
         --  resulting value is not accurate when we are printing the paths.

         Ada.Text_IO.Put (" *");
      end if;

      Ada.Text_IO.New_Line;
   end Print_Node;

   --------------------
   -- Print_Ada_Name --
   --------------------

   procedure Print_Ada_Name
     (Node : Static_Stack_Analysis.Node_Class_Access)
   is
      Name : constant Static_Stack_Analysis.Subprogram_Name :=
        Static_Stack_Analysis.Get_Subprogram_Name (Node.all);

      Location_List : constant Static_Stack_Analysis.List_Of_Locations.Set :=
        Static_Stack_Analysis.Get_Location_List (Node.all);

      Location_Index : Static_Stack_Analysis.List_Of_Locations.Cursor :=
        Location_List.First;

      Location : Static_Stack_Analysis.Location :=
        Static_Stack_Analysis.Null_Location;

      Found : Boolean := False;

   begin
      --  Print demangled names if possible

      while
        Static_Stack_Analysis.List_Of_Locations.Has_Element (Location_Index)
      loop
         Location :=
           Static_Stack_Analysis.List_Of_Locations.Element (Location_Index);

         if Location.Demangled /= null then
            if Found then
               --  Separator between demangled names

               Ada.Text_IO.Put (",");
            end if;

            Ada.Text_IO.Put (Location.Demangled.all);
            Found := True;
         end if;

         Static_Stack_Analysis.List_Of_Locations.Next (Location_Index);
      end loop;

      if not Found then
         --  Print the symbol name, removing path information
         declare
            Matches : GNAT.Regpat.Match_Array (0 .. 3);

            use type GNAT.Regpat.Match_Location;

         begin
            GNAT.Regpat.Match ("^(.+)??(:)??(.+)$", Name.all, Matches);

            if Matches (0) /= GNAT.Regpat.No_Match then
               Ada.Text_IO.Put
                 (Name.all (Matches (3).First .. Matches (3).Last));

            else
               Ada.Text_IO.Put (Name.all);
            end if;
         end;
      end if;
   end Print_Ada_Name;

   ----------------------
   -- Generate_Results --
   ----------------------

   procedure Generate_Results is
   begin
      --  Print subprograms ordered by local stack usage (if requested)

      if Options.Number_Of_Biggest_Frames > 0 then
         Ada.Text_IO.Put_Line ("Local stack usage information");

         Ada.Text_IO.New_Line;

         Print_Biggest_Frames (Options.Number_Of_Biggest_Frames);

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
   end Generate_Results;

   ---------------------------
   -- Generate_Output_Files --
   ---------------------------

   procedure Generate_Output_Files is
      use type GNAT.Strings.String_Access;

      Success : Boolean;

   begin
      --  If no file has been specified as call graph output use the default
      --  graph.vcg.

      if Options.Output_VCG = null then
         Options.Output_VCG := new String'("graph.vcg");
      end if;

      if GNAT.OS_Lib.Is_Regular_File (Options.Output_VCG.all) then
         GNAT.OS_Lib.Delete_File (Options.Output_VCG.all, Success);
         pragma Assert (Success);
      end if;

      Ada.Text_IO.Create
        (VCG_Descriptor, Ada.Text_IO.Out_File, Options.Output_VCG.all);

      Ada.Text_IO.Set_Output (VCG_Descriptor);

      --  If no file has been specified as output for undefined information
      --  use the default undefined.ciu.

      if Options.Output_Undefined = null then
         Options.Output_Undefined := new String'("undefined.ciu");
      end if;

      if GNAT.OS_Lib.Is_Regular_File (Options.Output_Undefined.all) then
         GNAT.OS_Lib.Delete_File (Options.Output_Undefined.all, Success);
         pragma Assert (Success);
      end if;

      Ada.Text_IO.Create
        (Undefined_Descriptor,
         Ada.Text_IO.Out_File,
         Options.Output_Undefined.all);

      --  Graph header

      Ada.Text_IO.Put_Line ("graph: { title: ""Callgraph information:""");

      --  Read information about nodes and edges

      Static_Stack_Analysis.List_Of_Nodes.Iterate
        (Static_Stack_Analysis.List_Of_Subprograms, Expand_Node'Access);

      --  End of graph

      Ada.Text_IO.Put_Line ("}");

      Ada.Text_IO.Set_Output (Ada.Text_IO.Standard_Output);

      Ada.Text_IO.Close (Undefined_Descriptor);

      Ada.Text_IO.Close (VCG_Descriptor);
   end Generate_Output_Files;

   -----------------------
   -- Generate_Warnings --
   -----------------------

   procedure Generate_Warnings is
   begin
      if not Static_Stack_Analysis.Cycles.Is_Empty
        or else Call_Graphs.Unbounded_Frames
        or else Call_Graphs.External_Calls
        or else Call_Graphs.Indirect_Calls
      then
         Ada.Text_IO.Put_Line
           ("Worst case analysis is *not* accurate ; use -W options for " &
            "details");
         Ada.Text_IO.New_Line;
      end if;

      --  Information about cycles

      if Options.Warnings (Options.Cycle)
        and then not Static_Stack_Analysis.Cycles.Is_Empty
      then
         Ada.Text_IO.Put_Line
           ("List of cycles:");
         Ada.Text_IO.New_Line;
         Static_Stack_Analysis.Cycles.Iterate (Print_Cycle'Access);
         Ada.Text_IO.New_Line;
      end if;

      --  Print the list of subprograms with dynamic frames whose maximum
      --  bounds cannot be statically computed.

      if Options.Warnings (Options.Unbounded)
        and then Call_Graphs.Unbounded_Frames
      then
         Ada.Text_IO.Put_Line
           ("List of subprograms with dynamic unbounded frames:");
         Ada.Text_IO.New_Line;
         Static_Stack_Analysis.List_Of_Subprograms.Iterate
           (Print_Unbounded'Access);
         Ada.Text_IO.New_Line;
      end if;

      --  Information about subprograms for which we do not have any stack
      --  usage

      if Options.Warnings (Options.External)
        and then Call_Graphs.External_Calls
      then
         Ada.Text_IO.Put_Line
           ("List of external subprograms:");
         Ada.Text_IO.New_Line;
         Static_Stack_Analysis.List_Of_Subprograms.Iterate
           (Print_External'Access);
         Ada.Text_IO.New_Line;
      end if;

      --  Information about indirect (including dispatching) calls

      if Options.Warnings (Options.Indirect)
        and then Call_Graphs.Indirect_Calls
      then
         Ada.Text_IO.Put_Line
           ("List of indirect (including dispatching) calls:");
         Ada.Text_IO.New_Line;
         Static_Stack_Analysis.List_Of_Subprograms.Iterate
           (Print_Indirect'Access);
         Ada.Text_IO.New_Line;
      end if;
   end Generate_Warnings;

   -----------------
   -- Expand_Node --
   -----------------

   procedure Expand_Node (Position : in Static_Stack_Analysis.Node_Id) is
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

      procedure Expand_Edge (Position : in Static_Stack_Analysis.Edge_Id);
      --  Generate the information about this call to subprogram

      procedure Expand_Edge (Position : in Static_Stack_Analysis.Edge_Id) is
         Target : constant Static_Stack_Analysis.Node_Class_Access :=
           Static_Stack_Analysis.List_Of_Nodes.Element
             (Static_Stack_Analysis.List_Of_Edges.Element (Position).Target);

         Callee : constant String :=
           Static_Stack_Analysis.Get_Subprogram_Name (Target.all).all;

      begin
         --  Print both to the VCG file containing the call graph and to the
         --  file that will be later filled by the user.

         Ada.Text_IO.Set_Output (VCG_Descriptor);

         Print_Edge (Source => Caller, Target => Callee);

         if Target.all in Static_Stack_Analysis.Fake_Node'Class then
            Ada.Text_IO.Set_Output (Undefined_Descriptor);

            Print_Edge (Source => Caller, Target => "XXX");
         end if;

      end Expand_Edge;

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

      if Unresolved then
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

   end Expand_Node;

   ------------------------
   -- Expand_Stack_Usage --
   ------------------------

   procedure Expand_Stack_Usage
     (Stack_Info : Static_Stack_Analysis.Stack_Usage_Info)
   is
      use type Static_Stack_Analysis.Stack_Usage;

   begin
      Ada.Integer_Text_IO.Put
        (Integer (Stack_Info.Static_Usage + Stack_Info.Dynamic_Usage +
                  Stack_Info.Unknown_Usage + Stack_Info.Cycle_Usage),
         0);

      Ada.Text_IO.Put (" bytes");

      --  Clarify stack usage information when we have something which is not
      --  static, or we have a cycle.

      if Stack_Info.Dynamic_Usage /= Static_Stack_Analysis.No_Value
        or else Stack_Info.Unknown_Usage /= Static_Stack_Analysis.No_Value
        or else Stack_Info.Cycle_Usage /= Static_Stack_Analysis.No_Value
      then
         if Options.Verbose then
            Ada.Text_IO.Put (" (");

            if Stack_Info.Dynamic_Usage /= Static_Stack_Analysis.No_Value then
               Ada.Text_IO.Put ("unbounded");
            end if;

            if Stack_Info.Unknown_Usage /= Static_Stack_Analysis.No_Value then
               if
                 Stack_Info.Dynamic_Usage /= Static_Stack_Analysis.No_Value
               then
                  Ada.Text_IO.Put (",");
               end if;

               Ada.Text_IO.Put ("unresolved");
            end if;

            if Stack_Info.Cycle_Usage /= Static_Stack_Analysis.No_Value then
               if Stack_Info.Dynamic_Usage /= Static_Stack_Analysis.No_Value
                 or else
                   Stack_Info.Unknown_Usage /= Static_Stack_Analysis.No_Value
               then
                  Ada.Text_IO.Put (",");
               end if;

               Ada.Text_IO.Put ("cycle");
            end if;

            Ada.Text_IO.Put (")");
         end if;
      end if;
   end Expand_Stack_Usage;

   ------------------------
   -- Print_Node_In_Path --
   ------------------------

   procedure Print_Node_In_Path
     (Position : in Static_Stack_Analysis.Paths.Cursor)
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
        Static_Stack_Analysis.Is_Task_Entry
          (Static_Stack_Analysis.Get_Subprogram_Name (Root.all));

      if Is_Task then
         --  This is an Ada task

         Ada.Text_IO.Put ("Task ");
      end if;

      Print_Ada_Name (Root);

      Ada.Text_IO.Put (" : total ");

      --  For tasks we need to add the task wrapper

      if Is_Task and then
        Static_Stack_Analysis.List_Of_Nodes.Has_Element
          (Static_Stack_Analysis.Task_Wrapper)
      then
         Task_Wrapper :=
           Static_Stack_Analysis.List_Of_Nodes.Element
             (Static_Stack_Analysis.Task_Wrapper);

         Accumulated_Stack :=
           (Static_Stack_Analysis.Get_Accumulated_Stack_Usage (Root.all) +
            Static_Stack_Analysis.Get_Stack_Usage (Task_Wrapper.all));

      else
         Accumulated_Stack :=
           Static_Stack_Analysis.Get_Accumulated_Stack_Usage (Root.all);
      end if;

      Expand_Stack_Usage (Accumulated_Stack);

      if not Options.Debug
        and then
          (Accumulated_Stack.Dynamic_Usage /= Static_Stack_Analysis.No_Value
             or else
           Accumulated_Stack.Unknown_Usage /= Static_Stack_Analysis.No_Value
             or else
           Accumulated_Stack.Cycle_Usage /= Static_Stack_Analysis.No_Value)
      then
         --  In non-verbose mode we just put a mark indicating that the
         --  resulting value is not accurate.

         Ada.Text_IO.Put (" *");
      end if;

      Ada.Text_IO.New_Line;

      if Task_Wrapper /= null then
         --  Print the frame for the task wrapper

         Print_Node (Task_Wrapper);
      end if;
   end Print_Entry;

   -----------------
   -- Print_Cycle --
   -----------------

   procedure Print_Cycle
     (Cycle : in Static_Stack_Analysis.List_Of_Cycles.Cursor)
   is
      Path : constant Static_Stack_Analysis.Paths.Vector :=
        Static_Stack_Analysis.List_Of_Cycles.Element (Cycle).Path;

      Root : constant Static_Stack_Analysis.Paths.Cursor :=
        Static_Stack_Analysis.Paths.First (Path);

   begin
      Print_Cycle_Id (Cycle);

      Ada.Text_IO.Put (" ");

      Print_Ada_Name
        (Static_Stack_Analysis.List_Of_Nodes.Element
           (Static_Stack_Analysis.Paths.Element (Root).Source_Node));

      Ada.Text_IO.New_Line;

      --  Print the call chain

      Static_Stack_Analysis.Paths.Iterate (Path, Print_Node_In_Path'Access);

      --  We repeat the first node just for clarity

      Print_Node_In_Path (Root);

      Ada.Text_IO.New_Line;

   end Print_Cycle;

   --------------------
   -- Print_Cycle_Id --
   --------------------

   procedure Print_Cycle_Id
     (Cycle : in Static_Stack_Analysis.List_Of_Cycles.Cursor) is
   begin
      Ada.Text_IO.Put ("<c");

      Ada.Integer_Text_IO.Put
        (Static_Stack_Analysis.List_Of_Cycles.Element (Cycle).Id, 0);

      Ada.Text_IO.Put (">");
   end Print_Cycle_Id;

   --------------------
   -- Print_External --
   --------------------

   procedure Print_External (Position : in Static_Stack_Analysis.Node_Id) is
      Node : constant Static_Stack_Analysis.Node_Class_Access :=
        Static_Stack_Analysis.List_Of_Nodes.Element (Position);

   begin
      if Node.Analysis_Finished
        and then Node.all in Static_Stack_Analysis.Unresolved_Node'Class
      then
         Ada.Text_IO.Put_Line
           ("  " & Static_Stack_Analysis.Get_Subprogram_Name (Node.all).all);
      end if;
   end Print_External;

   --------------------
   -- Print_Indirect --
   --------------------

   procedure Print_Indirect (Position : in Static_Stack_Analysis.Node_Id) is
      Node : constant Static_Stack_Analysis.Node_Class_Access :=
        Static_Stack_Analysis.List_Of_Nodes.Element (Position);

      Counter : Natural := 0;
      --  Number of indirect calls made by the node under analysis

      procedure Is_Indirect (Position : in Static_Stack_Analysis.Edge_Id);
      --  If the referenced call is an indirect call Counter is incremented

      procedure Is_Indirect (Position : in Static_Stack_Analysis.Edge_Id) is

         procedure Is_Indirect
           (Target : Static_Stack_Analysis.Node_Class_Access);

         procedure Is_Indirect
           (Target : Static_Stack_Analysis.Node_Class_Access) is
         begin
            if Target.all in Static_Stack_Analysis.Fake_Node'Class then
               Counter := Counter + 1;
            end if;
         end Is_Indirect;

      begin
         Static_Stack_Analysis.List_Of_Nodes.Query_Element
           (Static_Stack_Analysis.List_Of_Edges.Element (Position).Target,
            Is_Indirect'Access);
      end Is_Indirect;

   begin
      if Node.Analysis_Finished then
         Node.Target_Calls.Iterate (Is_Indirect'Access);

         if Counter > 0 then
            Ada.Text_IO.Put ("  ");

            Ada.Integer_Text_IO.Put (Counter, 0);

            Ada.Text_IO.Put (" indirect calls in: ");

            Print_Name (Node);

            Ada.Text_IO.New_Line;
         end if;
      end if;
   end Print_Indirect;

   ---------------------
   -- Print_Unbounded --
   ---------------------

   procedure Print_Unbounded (Position : in Static_Stack_Analysis.Node_Id) is
      Node : constant Static_Stack_Analysis.Node_Class_Access :=
        Static_Stack_Analysis.List_Of_Nodes.Element (Position);

      use type Static_Stack_Analysis.Stack_Usage;

   begin
      if Node.Analysis_Finished
        and then
          Static_Stack_Analysis.Get_Stack_Usage (Node.all).Frame_Type =
          Static_Stack_Analysis.Unbounded
      then
         Ada.Text_IO.Put ("  ");

         Print_Name (Node);

         Ada.Text_IO.New_Line;
      end if;
   end Print_Unbounded;

end Display;
