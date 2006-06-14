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

   ----------------
   -- Local data --
   ----------------

   VCG_Descriptor : Ada.Text_IO.File_Type;
   --  File where the VCG callgraph is stored

   -----------------------
   -- Local subprograms --
   -----------------------

   procedure Expand_Location
        (Position : Static_Stack_Analysis.List_Of_Locations.Cursor);
   --  Print the location using the format: file:demangled:line:column

   procedure Expand_Stack_Usage
     (Stack_Info : Static_Stack_Analysis.Stack_Usage_Info);
   --  Print the information about stack usage (local and accumulated)

   procedure Expand_Node (Position : in Static_Stack_Analysis.Node_Id);
   --  Print the information about the specified node, including stack usage
   --  (and accumulated stack usage), and subprograms that are called.

   procedure Print_Path (Path : in Static_Stack_Analysis.Paths.Vector);
   --  Print the specify path (subprograms plus calls) including local and
   --  accumulated stack consumption.

   ------------------------
   -- Print_Longest_Path --
   ------------------------

   procedure Print_Longest_Path is
   begin
      if Options.Explore_All then
         null;

      else

         --  Select the entry point with the potentially bigest stack
         --  consumption.

         if not Static_Stack_Analysis.List_Of_Entry_Points.Is_Empty
           (Static_Stack_Analysis.Entry_Points)
         then
            Ada.Text_IO.Put_Line ("Longest path:");

            Print_Path
              (Worst_Case_Analyzer.Get_Longest_Path
                 (Static_Stack_Analysis.Entry_Points.Last_Element));
         end if;
      end if;
   end Print_Longest_Path;

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
   begin
      Ada.Integer_Text_IO.Put
        (Integer (Stack_Info.Static_Usage + Stack_Info.Dynamic_Usage +
                  Stack_Info.Unknown_Usage),
         0);

      Ada.Text_IO.Put (" (");

      Ada.Integer_Text_IO.Put (Integer (Stack_Info.Static_Usage), 0);

      Ada.Text_IO.Put (" + ");

      Ada.Integer_Text_IO.Put (Integer (Stack_Info.Dynamic_Usage), 0);

      Ada.Text_IO.Put (" + ");

      Ada.Integer_Text_IO.Put (Integer (Stack_Info.Unknown_Usage), 0);

      Ada.Text_IO.Put (") bytes ");

      case Stack_Info.Frame_Type is
         when Static_Stack_Analysis.Static =>
            Ada.Text_IO.Put ("(static)");

         when Static_Stack_Analysis.Bounded =>
            Ada.Text_IO.Put ("(dynamic,bounded)");

         when Static_Stack_Analysis.Unbounded =>
            Ada.Text_IO.Put ("(dynamic)");

         when Static_Stack_Analysis.Unknown =>
            Ada.Text_IO.Put ("(unknown)");
      end case;
   end Expand_Stack_Usage;

   ----------------
   -- Print_Path --
   ----------------

   procedure Print_Path (Path : in Static_Stack_Analysis.Paths.Vector) is

      procedure Print_Node (Position : in Static_Stack_Analysis.Paths.Cursor);
      --  Print the information about this concrete node (name, location,
      --  stack usage, and subprogram called).

      procedure Print_Node
        (Position : in Static_Stack_Analysis.Paths.Cursor)
      is
         Explored_Item : constant Static_Stack_Analysis.Path_Element :=
           Static_Stack_Analysis.Paths.Element (Position);

         Explored_Node : Static_Stack_Analysis.Node_Class_Access;

         use type Static_Stack_Analysis.List_Of_Nodes.Cursor;
      begin
         --  Print node

         if Explored_Item.Source_Node /=
           Static_Stack_Analysis.List_Of_Nodes.No_Element
         then
            Explored_Node := Static_Stack_Analysis.List_Of_Nodes.Element
              (Explored_Item.Source_Node);

            --  Print subprogram name

            Ada.Text_IO.Put
              (Static_Stack_Analysis.Get_Subprogram_Name
                 (Explored_Node.all).all);

            --  Print location list

            Ada.Text_IO.Put (" at ");

            Static_Stack_Analysis.List_Of_Locations.Iterate
              (Static_Stack_Analysis.Get_Location_List (Explored_Node.all),
               Expand_Location'Access);

            Ada.Text_IO.New_Line;

            --  Print local and accumulated stack usage

            Ada.Text_IO.Put ("  Local stack usage: ");

            Expand_Stack_Usage
              (Static_Stack_Analysis.Get_Stack_Usage (Explored_Node.all));

            Ada.Text_IO.New_Line;

            Ada.Text_IO.Put ("  Accumulated stack usage: ");

            Expand_Stack_Usage (Explored_Node.Accumulated_Stack_Usage);

            Ada.Text_IO.New_Line;
         end if;
      end Print_Node;

   begin
      Static_Stack_Analysis.Paths.Iterate (Path, Print_Node'Access);
   end Print_Path;

end Display;
