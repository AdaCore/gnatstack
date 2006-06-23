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
--  Used for Output_File
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

with Worst_Case_Analyzer;
--  Used for Get_Longest_Path

with Ada.Text_IO;
--  Used for Create
--           Close
--           Put
--           Put_Line

with Ada.Integer_Text_IO;
--  Used for Put

with GNAT.OS_Lib;
--  Used for Delete_File

with GNAT.Strings;
--  Used for String_Access

package body Display is

   use type Static_Stack_Analysis.List_Of_Locations.Set;
   use type Static_Stack_Analysis.Subprogram_Name;
   use type Static_Stack_Analysis.Frame_Size;

   --------------------------
   -- Ordered entry points --
   --------------------------

   package Ordered_Entries is
     new Static_Stack_Analysis.List_Of_Entry_Points.Generic_Sorting
       (Static_Stack_Analysis.Stack_Usage_Order);
   --  This package is used for ordering edges (call-to-subprograms) according
   --  to their stack usage.

   ----------------
   -- Local data --
   ----------------

   VCG_Descriptor : Ada.Text_IO.File_Type;
   --  File where the VCG callgraph is stored

   -----------------------
   -- Local subprograms --
   -----------------------

   procedure Generate_VCG_Graph;
   --  Generate a VCG file containing the annotated callgraph

   procedure Print_Longest_Paths;
   --  Generate the callgraph chains that contains the longest paths with
   --  respect to stack usage. It will generate the worst case call chain for
   --  every entry point (if specific entry points have been indicated) or for
   --  every subprogram (if the flag for analyzing every subprogram has been
   --  set).

   procedure Expand_Location
        (Position : Static_Stack_Analysis.List_Of_Locations.Cursor);
   --  Print the location using the format: file:demangled:line:column

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
   --  Print the information about an indirect (including dispatching) call

   procedure Print_Node (Position : in Static_Stack_Analysis.Paths.Cursor);
   --  Print the information about this concrete node (name, location,
   --  stack usage, and subprogram called).

   procedure Print_Path (Path : in Static_Stack_Analysis.Paths.Vector);
   --  Print the specify path. The displayed information will be the set of
   --  subprograms in the path (if Verbose is False), and it will also
   --  include local and accumulated stack consumption (if Verbose is True).

   procedure Print_Cycle_Id
     (Cycle : in Static_Stack_Analysis.List_Of_Cycles.Cursor);
   --  Print the unique identifier associated to the cycle

   procedure Print_Cycle
     (Cycle : in Static_Stack_Analysis.List_Of_Cycles.Cursor);
   --  Print the set of subprograms belonging to the cycle

   ------------------------
   -- Print_Longest_Paths --
   ------------------------

   procedure Print_Longest_Paths is

      procedure Print_Longest_Path
        (Position : in Static_Stack_Analysis.Node_Id);
      --  Print the longest path for the specified subprogram

      procedure Print_Longest_Path
        (Position : in Static_Stack_Analysis.List_Of_Entry_Points.Cursor);
      --  Print the longest path for the specified entry point

      procedure Print_Longest_Path
        (Position : in Static_Stack_Analysis.Node_Id)
      is
         Path : Static_Stack_Analysis.Paths.Vector :=
           Static_Stack_Analysis.Paths.Empty_Vector;

      begin
         Worst_Case_Analyzer.Get_Longest_Path (Path, Position);
         Print_Path (Path);
         Ada.Text_IO.New_Line;
      end Print_Longest_Path;

      procedure Print_Longest_Path
        (Position : in Static_Stack_Analysis.List_Of_Entry_Points.Cursor) is
      begin
         Print_Longest_Path
           (Static_Stack_Analysis.List_Of_Entry_Points.Element (Position));
      end Print_Longest_Path;

      use type Options.Order_Type;

   begin
      --  Reorder if necessary

      if Options.Order = Options.Stack_Usage then
         --  Order entry points according to their stack consumption

         Ordered_Entries.Sort (Static_Stack_Analysis.Entry_Points);
      end if;

      --  Generate the worst case graph for every entry point

      Static_Stack_Analysis.List_Of_Entry_Points.Iterate
        (Static_Stack_Analysis.Entry_Points,
         Print_Longest_Path'Access);
   end Print_Longest_Paths;

   ---------------------
   -- Expand_Location --
   ---------------------

   procedure Expand_Location
     (Position : Static_Stack_Analysis.List_Of_Locations.Cursor)
   is
      Location : constant Static_Stack_Analysis.Location :=
        Static_Stack_Analysis.List_Of_Locations.Element (Position);

   begin
      Ada.Text_IO.Put (Location.File.all & ":");
      Ada.Text_IO.Put (Location.Demangled.all & ":");
      Ada.Integer_Text_IO.Put (Location.Line_Number, 0);
      Ada.Text_IO.Put (":");
      Ada.Integer_Text_IO.Put (Location.Column_Number, 0);
   end Expand_Location;

   ------------------------
   -- Generate_VCG_Graph --
   ------------------------

   procedure Generate_VCG_Graph is
      use type GNAT.Strings.String_Access;

      Success : Boolean;

   begin
      --  If no file has been specified as output use the default graph.vcg

      if Options.Output_File = null then
         Options.Output_File := new String'("graph.vcg");
      end if;

      if GNAT.OS_Lib.Is_Regular_File (Options.Output_File.all) then
         GNAT.OS_Lib.Delete_File (Options.Output_File.all, Success);
         pragma Assert (Success);
      end if;

      Ada.Text_IO.Create
        (VCG_Descriptor, Ada.Text_IO.Out_File, Options.Output_File.all);

      Ada.Text_IO.Set_Output (VCG_Descriptor);

      --  Graph header

      Ada.Text_IO.Put_Line ("graph: { title: ""Callgraph information:""");

      --  Read information about nodes and edges

      Static_Stack_Analysis.List_Of_Nodes.Iterate
        (Static_Stack_Analysis.List_Of_Subprograms, Expand_Node'Access);

      --  End of graph

      Ada.Text_IO.Put_Line ("}");

      Ada.Text_IO.Set_Output (Ada.Text_IO.Standard_Output);

      Ada.Text_IO.Close (VCG_Descriptor);
   end Generate_VCG_Graph;

   -----------------
   -- Expand_Node --
   -----------------

   procedure Expand_Node (Position : in Static_Stack_Analysis.Node_Id) is
      Node : constant Static_Stack_Analysis.Node_Class_Access :=
        Static_Stack_Analysis.List_Of_Nodes.Element (Position);

      Stack : constant Static_Stack_Analysis.Stack_Usage_Info :=
        Static_Stack_Analysis.Get_Stack_Usage (Node.all);

      procedure Expand_Edge (Position : in Static_Stack_Analysis.Edge_Id);
      --  Generate the information about this call to subprogram

      procedure Expand_Edge (Position : in Static_Stack_Analysis.Edge_Id) is
         Edge : constant Static_Stack_Analysis.Edge :=
           Static_Stack_Analysis.List_Of_Edges.Element (Position);

         Target : constant Static_Stack_Analysis.Node_Class_Access :=
           Static_Stack_Analysis.List_Of_Nodes.Element (Edge.Target);

      begin
         --  Caller

         Ada.Text_IO.Put ("edge: { sourcename: """);
         Ada.Text_IO.Put
           (Static_Stack_Analysis.Get_Subprogram_Name (Node.all).all);

         --  Callee

         Ada.Text_IO.Put (""" targetname: """);
         Ada.Text_IO.Put
           (Static_Stack_Analysis.Get_Subprogram_Name (Target.all).all);

         --  Type of line

         Ada.Text_IO.Put_Line (""" priority: 100 linestyle: solid }");
      end Expand_Edge;

   begin
      --  Generate the node line

      --  Open node

      Ada.Text_IO.Put ("node: {");

      --  Title

      Ada.Text_IO.Put (" title: """);

      Ada.Text_IO.Put
           (Static_Stack_Analysis.Get_Subprogram_Name (Node.all).all);

      Ada.Text_IO.Put ('"');

      --  Label

      Ada.Text_IO.Put (" label: """);

      declare
         Locations : constant Static_Stack_Analysis.List_Of_Locations.Set :=
           Static_Stack_Analysis.Get_Location_List (Node.all);

      begin
         if not Locations.Is_Empty then
            Ada.Text_IO.Put ("\n");

            Static_Stack_Analysis.List_Of_Locations.Iterate
              (Locations, Expand_Location'Access);
         end if;
      end;

      --  Print stack usage for the subprogram

      Ada.Text_IO.Put ("\nLocal: ");

      Expand_Stack_Usage (Stack);

      --  Print the maximum accumulated stack usage

      Ada.Text_IO.Put ("\nAccumulated: ");

      Expand_Stack_Usage (Node.Accumulated_Stack_Usage);

      Ada.Text_IO.Put ('"');

      --  Shape

      if Node.all in Static_Stack_Analysis.Unresolved_Node'Class then
         Ada.Text_IO.Put (" shape : ellipse");
      end if;

      --  Close node

      Ada.Text_IO.Put_Line (" }");

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
                  Stack_Info.Unknown_Usage),
         0);

      Ada.Text_IO.Put (" bytes");

      --  Clarify stack usage information when we have something which is not
      --  static

      if Stack_Info.Frame_Type /= Static_Stack_Analysis.Static then
         Ada.Text_IO.Put (" (");

         if Stack_Info.Static_Usage /= 0 then
            Ada.Integer_Text_IO.Put (Integer (Stack_Info.Static_Usage), 0);
            Ada.Text_IO.Put ("s");
         end if;

         if Stack_Info.Dynamic_Usage /= 0 then
            if Stack_Info.Static_Usage /= 0 then
               Ada.Text_IO.Put (",");
            end if;

            Ada.Integer_Text_IO.Put (Integer (Stack_Info.Dynamic_Usage), 0);
            Ada.Text_IO.Put ("u");
         end if;

         if Stack_Info.Unknown_Usage /= 0 then
            if Stack_Info.Static_Usage /= 0
              or else Stack_Info.Dynamic_Usage /= 0
            then
               Ada.Text_IO.Put (",");
            end if;

            Ada.Integer_Text_IO.Put (Integer (Stack_Info.Unknown_Usage), 0);
            Ada.Text_IO.Put ("e");
         end if;

         Ada.Text_IO.Put (")");
      end if;
   end Expand_Stack_Usage;

   ----------------
   -- Print_Node --
   ----------------

   procedure Print_Node
     (Position : in Static_Stack_Analysis.Paths.Cursor)
   is
      Explored_Item : constant Static_Stack_Analysis.Path_Element :=
        Static_Stack_Analysis.Paths.Element (Position);

      Explored_Node : Static_Stack_Analysis.Node_Class_Access;

      use type Static_Stack_Analysis.List_Of_Nodes.Cursor;

   begin
      --  Print node

      if
        Static_Stack_Analysis.List_Of_Nodes.Has_Element
          (Explored_Item.Source_Node)
      then
         Explored_Node := Static_Stack_Analysis.List_Of_Nodes.Element
           (Explored_Item.Source_Node);

         --  Indentation

         Ada.Text_IO.Put (" +-> ");

         --  Print subprogram name

         Ada.Text_IO.Put
           (Static_Stack_Analysis.Get_Subprogram_Name (Explored_Node.all).all);

         --  Print location list

         if Options.Verbose then
            Ada.Text_IO.Put (" at ");

            Static_Stack_Analysis.List_Of_Locations.Iterate
              (Static_Stack_Analysis.Get_Location_List (Explored_Node.all),
               Expand_Location'Access);
         end if;

         --  Print local and accumulated stack usage

         if Options.Verbose then
            Ada.Text_IO.Put (" : ");

            Expand_Stack_Usage
              (Static_Stack_Analysis.Get_Stack_Usage (Explored_Node.all));

            --  Print local and accumulated stack usage

            if Options.Verbose then
               Ada.Text_IO.Put (" Accumulated : ");

               Expand_Stack_Usage (Explored_Node.Accumulated_Stack_Usage);
            end if;
         end if;

         --  Information about cycles

         if not Static_Stack_Analysis.List_Of_Cycles.Is_Empty
           (Explored_Node.Cycles)
         then
            Ada.Text_IO.Put (" (");

            Explored_Node.Cycles.Iterate (Print_Cycle_Id'Access);

            Ada.Text_IO.Put (")");
         end if;

         Ada.Text_IO.New_Line;
      end if;
   end Print_Node;

   ----------------
   -- Print_Path --
   ----------------

   procedure Print_Path (Path : in Static_Stack_Analysis.Paths.Vector) is
      Top_Subprogram : constant Static_Stack_Analysis.Node_Class_Access :=
        Static_Stack_Analysis.List_Of_Nodes.Element
          (Static_Stack_Analysis.Paths.First_Element (Path).Source_Node);

   begin
      --  Print the global information

      Ada.Text_IO.Put
        (Static_Stack_Analysis.Get_Subprogram_Name (Top_Subprogram.all).all);

      Ada.Text_IO.Put (" : total ");

      Expand_Stack_Usage
        (Static_Stack_Analysis.Get_Accumulated_Stack_Usage
           (Top_Subprogram.all));

      Ada.Text_IO.New_Line;

      --  Print the call chain

      Static_Stack_Analysis.Paths.Iterate (Path, Print_Node'Access);
   end Print_Path;

   -----------------
   -- Print_Cycle --
   -----------------

   procedure Print_Cycle
     (Cycle : in Static_Stack_Analysis.List_Of_Cycles.Cursor)
   is
      Path : constant Static_Stack_Analysis.Paths.Vector :=
        Static_Stack_Analysis.List_Of_Cycles.Element (Cycle).Path;

   begin
      Print_Cycle_Id (Cycle);

      Ada.Text_IO.Put (" ");

      Print_Path (Path);

      --  We repeat the first node just for better clarity

      Print_Node (Static_Stack_Analysis.Paths.First (Path));

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
      if Node.all in Static_Stack_Analysis.Unresolved_Node'Class then
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

   begin
      if Node.all in Static_Stack_Analysis.Fake_Node'Class then
         Ada.Text_IO.Put_Line
           ("  " & Static_Stack_Analysis.Get_Subprogram_Name (Node.all).all);
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
      if
        Static_Stack_Analysis.Get_Stack_Usage (Node.all).Frame_Type =
        Static_Stack_Analysis.Unbounded
      then
         Ada.Text_IO.Put_Line
           ("  " & Static_Stack_Analysis.Get_Subprogram_Name (Node.all).all);
      end if;
   end Print_Unbounded;

   -------------
   -- Results --
   -------------

   procedure Results is
   begin
      --  Information about cycles

      if Options.Warnings (Options.Cycle) then
         Ada.Text_IO.Put_Line
           ("List of cycles:");
         Static_Stack_Analysis.Cycles.Iterate (Print_Cycle'Access);
         Ada.Text_IO.New_Line;
      end if;

      --  Print the list of subprograms with dynamic frames whose maximum
      --  bounds cannot be statically computed.

      if Options.Warnings (Options.Unbounded) then
         Ada.Text_IO.Put_Line
           ("List of subprograms with dynamic unbounded frames:");
         Static_Stack_Analysis.List_Of_Subprograms.Iterate
           (Print_Unbounded'Access);
         Ada.Text_IO.New_Line;
      end if;

      --  Information about subprograms for which we do not have any stack
      --  usage

      if Options.Warnings (Options.Unbounded) then
         Ada.Text_IO.Put_Line
           ("List of external subprograms:");
         Static_Stack_Analysis.List_Of_Subprograms.Iterate
           (Print_External'Access);
         Ada.Text_IO.New_Line;
      end if;

      --  Information about indirect (including dispatching) calls

      if Options.Warnings (Options.Indirect) then
         Ada.Text_IO.Put_Line
           ("List of indirect (including dispatching) calls:");
         Static_Stack_Analysis.List_Of_Subprograms.Iterate
           (Print_Indirect'Access);
         Ada.Text_IO.New_Line;
      end if;

      --  Generate file containing the whole call graph

      Generate_VCG_Graph;

      --  Print the stack usage information

      Ada.Text_IO.Put_Line ("Stack usage information");

      Ada.Text_IO.New_Line;

      Print_Longest_Paths;

   end Results;
end Display;
