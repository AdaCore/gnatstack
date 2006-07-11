------------------------------------------------------------------------------
--                        STATIC STACK ANALYSIS TOOL                        --
--                                                                          --
--                               P A R S E R                                --
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

with Static_Stack_Analysis;
--  Used for Get_Node
--           List_Of_Nodes
--           List_Of_Edges
--           List_Of_Locations
--           Entry_Points
--           Unknown_Stack_Usage

with Call_Graph_Cycles;
--  Used for Extract_Cycles

with Options;
--  Used for Verbose
--           Explore_All
--           Default_Unknown
--           Default_Unbounded
--           List_Of_Entry_Points
--           Output_VCG
--           Order

with Ada.Containers.Vectors;

with Ada.Text_IO;
--  Used for Open
--           Close
--           End_Of_File
--           Get_Line
--           Put_Line
--           New_Line

with GNAT.Regpat;
--  Used for Match

with GNAT.Command_Line;
--  Used for Getopt
--           Get_Argument
--           Parameter

with GNAT.Strings;
--  Used for String_Access

with GNAT.OS_Lib;
--  Used for OS_Exit

with Ada.Unchecked_Deallocation;

package body Parser is

   use type Static_Stack_Analysis.Node_Id;
   use type Static_Stack_Analysis.Stack_Usage_Info;
   use type Static_Stack_Analysis.Location;
   use type GNAT.Regpat.Match_Location;

   ----------------
   -- Local data --
   ----------------

   Parser_Error : exception;
   --  Exception to be raised when unexpected data is found

   -----------------------
   -- Local subprograms --
   -----------------------

   procedure Usage;
   --  Print how to use the tool

   procedure Add_Ada_Entry_Points
     (Position : in Static_Stack_Analysis.Node_Id);
   --  Add the entry points corresponding to the main procedure and the task
   --  entry points.

   procedure Add_Local_Entry (Position : in Static_Stack_Analysis.Node_Id);
   --  Add the node to the list of entry points to analyze if it contains a
   --  subprogram that is part of the application code.

   procedure Add_Pattern_Entry (Position : in Static_Stack_Analysis.Node_Id);
   --  Add the node to the list of entry points to analyze if its symbol name
   --  contains the pattern specified in Options.Entry_Point_Pattern.

   procedure Free is new
     Ada.Unchecked_Deallocation (String, GNAT.OS_Lib.String_Access);

   ------------------------
   -- Handle input files --
   ------------------------

   function Equal (Left, Right : GNAT.Strings.String_Access) return Boolean;
   --  Compare two pointers to String. They will be considered equal if both
   --  are null pointers, or else if both contain the same String.

   package List_Of_Files is new
     Ada.Containers.Vectors (Natural, GNAT.Strings.String_Access, Equal);

   Input_Files : List_Of_Files.Vector := List_Of_Files.Empty_Vector;
   --  List of input files containing stack usage information (.ci files)

   subtype File_Id is List_Of_Files.Cursor;
   --  Unique identifier for files

   -----------------------
   -- Expected patterns --
   -----------------------

   Node_Regexp : constant String :=
     "^node: {" &
     " title: " & '"' & "([^" & '"' & "]+)" & '"' &
     " label: " & '"' & "([^" & '"' & "]+)" & '"' & "(" &
     " shape : (.+)*" & ")??" & " }";
   --  Pattern: ^node: { title: "([^"]+)" label: "([^"]+)" (shape : (.+)*)?? }

   Edge_Regexp : constant String :=
     "^edge: { sourcename: " & '"' & "([^" & '"' & "]+)" & '"' &
     " targetname: " & '"' & "([^" & '"' & "]+)" & '"';
   --  Pattern: ^edge: { sourcename: "([^"]+)" targetname: "([^"]+)"

   Label_Regexp : constant String :=
     "^([^\\:]+)??(\\n)??([^\\]+)??(\\n)??([0-9]+ bytes" &
     "( \(static\)| \(dynamic\)| \(dynamic,bounded\))??)??$";
   --  Pattern: (([^\\:]+)??(\\n)??(([^\\]+)??(\\n)??([0-9]+ bytes
   --           ( \(static\)| \(dynamic\)| \(dynamic,bounded\))??)??$

   No_Location_Regexp : constant String := "^<no location>$";
   --  Pattern : ^<no location>$

   Location_Regexp : constant String :=
     "^([^:,]+):([0-9]+):*([0-9]+)*,*(.+)*$";
   --  Pattern: ^([^:,]+):([0-9]+):*([0-9]+)*,*(.+)*$

   Stack_Regexp : constant String :=
     "^([0-9]+)+ bytes( \(static\)| \(dynamic\)| \(dynamic,bounded\))??$";
   --  Pattern: ^([0-9]+)+ bytes( \(static| \(dynamic| \(dynamic,bounded\))??$

   Entry_Regexp : constant String :=
     "^([^:,]+),*(.+)*$";
   --  Pattern: ^([^:,]+),*(.+)*$

   ------------------------
   -- Parsing operations --
   ------------------------

   procedure Parse_Entry_Points (Input : String);
   --  Get the list of entry points to be analyzed. The format of the input
   --  String is: [e1[,e2]]

   procedure Parse_Input_File (File : File_Id);
   --  Extract the information from the specified file by parsing every line
   --  in the file.

   procedure Parse_Input_Line (Input : String);
   --  Extract the information from the single line being read from a file

   procedure Parse_Node (Input : String);
   --  Extract the information about a node. The expected format is:
   --  ^node: { title: "symbol_name" label: "LABEL"[ shape : ellipse] }

   procedure Parse_Title
     (Input : in String; Symbol : out Static_Stack_Analysis.Subprogram_Name);
   --  The input String should contain the symbol name

   procedure Parse_Label
     (Input     : in String;
      Demangled : out Static_Stack_Analysis.Subprogram_Name;
      Locations : out Static_Stack_Analysis.List_Of_Locations.Set;
      Stack     : out Static_Stack_Analysis.Stack_Usage_Info);
   --  The label contain information about the demangled symbol name,
   --  locations in source files, and stack requirements extracted by the
   --  compiler.
   --  The format of the input String is:
   --  [demangled_name\n][LOC[,LOC]\n][N bytes[ (static|dynamic[,bounded])]]

   procedure Parse_Locations
     (Input     : in String;
      Demangled : in Static_Stack_Analysis.Subprogram_Name;
      Locations : out Static_Stack_Analysis.List_Of_Locations.Set);
   --  Extract the list of locations in source files.
   --  Format: [filename:line:[column][,filename:line:[column]]

   procedure Parse_Stack_Usage
     (Input : in String; Stack : out Static_Stack_Analysis.Stack_Usage_Info);
   --  Extract stack requirements.
   --  Format: N bytes[ (static|dynamic[,bounded])]

   procedure Parse_Shape (Input : in String; Local : out Boolean);
   --  Local is set to True if the subprogram is defined in the compilation
   --  unit. For unresolved subprograms it returns False.
   --  Format :  shape : ellipse

   procedure Parse_Edge (Input : String);
   --  Get caller and callee in a subprogram call.
   --  Format : ^edge: { sourcename: "symbol_name" targetname: "symbol_name"

   --------------------------
   -- Add_Ada_Entry_Points --
   --------------------------

   procedure Add_Ada_Entry_Points
     (Position : in Static_Stack_Analysis.Node_Id)
   is
      Subprogram : constant Static_Stack_Analysis.Subprogram_Name :=
        Static_Stack_Analysis.Get_Subprogram_Name
          (Static_Stack_Analysis.List_Of_Nodes.Element (Position).all);

   begin
      --  If the referenced node describes a subprogram containing the pattern
      --  defined in Options.Entry_Point_Pattern we add this subprogram to the
      --  list of potential entry points.

      if Subprogram.all = "main"
        or else GNAT.Regpat.Match ("B", Subprogram.all)
      then
         Static_Stack_Analysis.Entry_Points.Append (Position);
      end if;
   end Add_Ada_Entry_Points;

   ---------------------
   -- Add_Local_Entry --
   ---------------------

   procedure Add_Local_Entry (Position : in Static_Stack_Analysis.Node_Id) is
      Explored_Node : constant Static_Stack_Analysis.Node_Class_Access :=
        Static_Stack_Analysis.List_Of_Nodes.Element (Position);

   begin
      --  Consider only explicit nodes as potential entry points, which means
      --  excluding external subprograms and indirect (including dispatching)
      --  calls.

      if Explored_Node.all in Static_Stack_Analysis.Explicit_Node'Class then
         Static_Stack_Analysis.Entry_Points.Append (Position);
      end if;
   end Add_Local_Entry;

   -----------------------
   -- Add_Pattern_Entry --
   -----------------------

   procedure Add_Pattern_Entry (Position : in Static_Stack_Analysis.Node_Id) is
      Explored_Node : constant Static_Stack_Analysis.Node_Class_Access :=
        Static_Stack_Analysis.List_Of_Nodes.Element (Position);

      Matches : GNAT.Regpat.Match_Array (0 .. 1);

   begin
      --  If the referenced node describes a subprogram containing the pattern
      --  defined in Options.Entry_Point_Pattern we add this subprogram to the
      --  list of potential entry points.

      GNAT.Regpat.Match
        (Options.Entry_Point_Pattern.all,
         Static_Stack_Analysis.Get_Subprogram_Name (Explored_Node.all).all,
         Matches);

      if Matches (0) /= GNAT.Regpat.No_Match then
         Static_Stack_Analysis.Entry_Points.Append (Position);
      end if;
   end Add_Pattern_Entry;

   -----------
   -- Equal --
   -----------

   function Equal (Left, Right : GNAT.Strings.String_Access) return Boolean is
      use type GNAT.Strings.String_Access;

   begin
      --  The two pointers will be considered equal if both are null pointers
      --  or else if both contain the same String.

      return (Left = null and then Right = null)
        or else (Left /= null
                 and then Right /= null
                 and then Left.all = Right.all);
   end Equal;

   ---------------------
   -- Parse Arguments --
   ---------------------

   procedure Parse_Arguments is
      use type GNAT.Strings.String_Access;

   begin
      --  Get options

      loop
         case GNAT.Command_Line.Getopt ("h v ca W! o= a u: d: e: r: g:") is
            when ASCII.NUL =>
               exit;

            --  Verbose
            when 'v' =>
               Options.Verbose := True;

            --  All cycles
            when 'c' =>
               if GNAT.Command_Line.Full_Switch = "ca" then
                  Options.Compute_All_Cycles := True;
               else
                  Ada.Text_IO.Put_Line
                    ("Unknown option: " & GNAT.Command_Line.Full_Switch);
                  Usage;
                  GNAT.OS_Lib.OS_Exit (1);
               end if;

            --  Warnings
            when 'W' =>
               declare
                  Parameter : constant String := GNAT.Command_Line.Parameter;
               begin
                  for Index in Parameter'Range loop
                     case Parameter (Index) is
                        when 'a' =>
                           Options.Warnings := (others => True);

                        when 'c' =>
                           Options.Warnings (Options.Cycle) := True;

                        when 'u' =>
                           Options.Warnings (Options.Unbounded) := True;

                        when 'e' =>
                           Options.Warnings (Options.External) := True;

                        when 'i' =>
                           Options.Warnings (Options.Indirect) := True;

                        when others =>
                           Ada.Text_IO.Put_Line ("Bad warning (-W) option");
                           Usage;
                           GNAT.OS_Lib.OS_Exit (1);
                     end case;
                  end loop;
               end;

            --  Ordering
            when 'o' =>
               declare
                  Parameter : constant String := GNAT.Command_Line.Parameter;
               begin
                  if Parameter = "a" then
                        Options.Order := Options.Alphabetical;
                  elsif Parameter = "s" then
                        Options.Order := Options.Stack_Usage;
                  else
                        Ada.Text_IO.Put_Line ("Bad order (-o) option");
                        Usage;
                        GNAT.OS_Lib.OS_Exit (1);
                  end if;
               end;

            --  Consider all subprograms as potential entry points
            when 'a' =>
               Options.Explore_All := True;

            --  Default stack requirements for unknown (external) calls
            when 'u' =>
               Options.Default_Unknown :=
                 Natural'Value (GNAT.Command_Line.Parameter);

            --  Default stack requirements for unbounded (dynamic) calls
            when 'd' =>
               Options.Default_Unbounded :=
                 Natural'Value (GNAT.Command_Line.Parameter);

            --  List of entry points
            when 'e' =>
               Free (Options.List_Of_Entry_Points);
               Options.List_Of_Entry_Points :=
                 new String'(GNAT.Command_Line.Parameter);

            --  Pattern for subprograms to be considered entry points
            when 'r' =>
               Free (Options.Entry_Point_Pattern);
               Options.Entry_Point_Pattern :=
                 new String'(GNAT.Command_Line.Parameter);

            --  Output graph file
            when 'g' =>
               Free (Options.Output_VCG);
               Options.Output_VCG :=
                 new String'(GNAT.Command_Line.Parameter);

            when others =>
               Usage;
               GNAT.OS_Lib.OS_Exit (1);
         end case;
      end loop;

      --  Get list of input files

      loop
         declare
            Input_File_Name : constant GNAT.Strings.String_Access :=
              new String'(GNAT.Command_Line.Get_Argument
                          (Do_Expansion => True));
         begin
            exit when Input_File_Name'Length = 0;

            List_Of_Files.Append (Input_Files, Input_File_Name);
         end;
      end loop;

      --  Once we know the list of input files we can parse the information
      --  which is within these files.

      if List_Of_Files.Is_Empty (Input_Files) then
         Ada.Text_IO.Put_Line
           ("Specify at least one .ci (callgraph information) file");

         Ada.Text_IO.New_Line;

         Usage;

         GNAT.OS_Lib.OS_Exit (1);

      else
         List_Of_Files.Iterate (Input_Files, Parse_Input_File'Access);
      end if;

      --  Extract the cycles in the call graph

      Call_Graph_Cycles.Extract_Cycles;

      --  Get the list of subprograms to be considered as entry points

      --  Automatic entry points (main procedure and task entry points)

      Static_Stack_Analysis.List_Of_Nodes.Iterate
           (Static_Stack_Analysis.List_Of_Subprograms,
            Add_Ada_Entry_Points'Access);

      --  Entry points specified by hand

      if Options.List_Of_Entry_Points /= null then
         --  Add the entry points that have been specified in the command line

         Parse_Entry_Points (Options.List_Of_Entry_Points.all);

      elsif Options.Entry_Point_Pattern /= null then
         --  Add the entry points matching the pattern

         Static_Stack_Analysis.List_Of_Nodes.Iterate
           (Static_Stack_Analysis.List_Of_Subprograms,
            Add_Pattern_Entry'Access);

      elsif Options.Explore_All then
         --  Explore every node that contains subprograms defined within the
         --  application.

         Static_Stack_Analysis.List_Of_Nodes.Iterate
           (Static_Stack_Analysis.List_Of_Subprograms, Add_Local_Entry'Access);
      end if;

   exception
      when GNAT.Command_Line.Invalid_Switch =>
         Ada.Text_IO.Put_Line
           ("Invalid Switch " & GNAT.Command_Line.Full_Switch);

         Usage;

         GNAT.OS_Lib.OS_Exit (1);

      when GNAT.Command_Line.Invalid_Parameter =>
         Ada.Text_IO.Put_Line
           ("No parameter for " & GNAT.Command_Line.Full_Switch);

         Usage;

         GNAT.OS_Lib.OS_Exit (1);
   end Parse_Arguments;

   ------------------------
   -- Parse_Entry_Points --
   ------------------------

   procedure Parse_Entry_Points (Input : String) is
      Matches    : GNAT.Regpat.Match_Array (0 .. 2);

      Found_Id : Static_Stack_Analysis.Node_Id;

   begin
      GNAT.Regpat.Match (Entry_Regexp, Input, Matches);

      if Matches (0) /= GNAT.Regpat.No_Match then
         Found_Id := Static_Stack_Analysis.Get_Node
           (Input (Matches (1).First .. Matches (1).Last));

         if Static_Stack_Analysis.List_Of_Nodes.Has_Element (Found_Id) then
            --  Add the entry point to the list

            Static_Stack_Analysis.Entry_Points.Append (Found_Id);

         else
            --  The entry point does not exist

            raise Parser_Error with "The entry point does not exist";
         end if;

         --  Get next entry point

         if Matches (2) /= GNAT.Regpat.No_Match then
            Parse_Entry_Points (Input (Matches (2).First .. Matches (2).Last));
         end if;

      else
         raise Parser_Error;
      end if;

   end Parse_Entry_Points;

   ----------------
   -- Parse_Line --
   ----------------

   procedure Parse_Input_Line (Input : String) is
   begin
      if GNAT.Regpat.Match (Node_Regexp, Input) then
         Parse_Node (Input);

      elsif GNAT.Regpat.Match (Edge_Regexp, Input) then
         Parse_Edge (Input);

      elsif Options.Verbose then
         Ada.Text_IO.Put_Line ("Skipping: " & Input);
      end if;

   exception
      when Parser_Error =>
         Ada.Text_IO.Put_Line ("Error parsing:");
         Ada.Text_IO.Put_Line (Input);
   end Parse_Input_Line;

   ----------------
   -- Parse_Node --
   ----------------

   procedure Parse_Node (Input : String) is
      use Static_Stack_Analysis;

      Symbol_Name     : Subprogram_Name := null;
      Demangled_Name  : Subprogram_Name := null;
      Stack_Info      : Stack_Usage_Info := Unknown_Stack_Usage;
      Locally_Defined : Boolean := False;

      Node_Ptr        : Node_Class_Access := null;

      Matches         : GNAT.Regpat.Match_Array (0 .. 3);

      Locations_Set   : List_Of_Locations.Set := List_Of_Locations.Empty_Set;

   begin
      --  The pattern of the input line is:
      --  node: { title: "symbol_name" label: "LABEL"[ shape : ellipse] }
      --
      --  The symbol_name is the one that is used for distinguising among the
      --  different nodes.
      --
      --  The format of the String under LABEL is:
      --  "[demangled_name][\nLOC[,LOC]][\nN bytes (static|dynamic[,bounded])]"
      --  where:
      --  LOC = file:line:column
      --  N = Natural representing the number of bytes
      --
      --  The shape : ellipse indicates that the node is used but not defined,
      --  which means that it is an unresolved call.
      --
      --  The fields that are mandatory are title and label.

      --  First, we want to get the three different fields (title, label, and
      --  shape) so we can process them later.

      GNAT.Regpat.Match (Node_Regexp, Input, Matches);

      if Matches (0) = GNAT.Regpat.No_Match then
         raise Parser_Error;

      else

         --  Get the symbol name corresponding to the subprogram

         Parse_Title
           (Input (Matches (1).First .. Matches (1).Last), Symbol_Name);

         --  If this is an indirect call then no more information can be
         --  extracted.

         if Symbol_Name.all /= Indirect_Call.all then

            --  Get information from the label

            Parse_Label
              (Input (Matches (2).First .. Matches (2).Last),
               Demangled_Name,
               Locations_Set,
               Stack_Info);

            --  Get information from the shape

            if Matches (3) /= GNAT.Regpat.No_Match then
               Parse_Shape
                 (Input (Matches (3).First .. Matches (3).Last),
                  Locally_Defined);
            else
               Locally_Defined := True;
            end if;
         end if;
      end if;

      --  Check whether the node is already in the list. We use the symbol
      --  name as the unique identifier.

      declare
         Found_Id   : constant Node_Id := Get_Node (Symbol_Name.all);
         Found_Node : Node_Class_Access := null;

      begin
         --  Indirect call
         if Symbol_Name.all = Indirect_Call.all then
            --  This is an indirect call. We cannot get any more information.
            --  These nodes are there only for supporting edges representing
            --  indirect calls. The indirect nodes are created when analyzing
            --  the edges, so we do not need to create any node here.

            null;

         --  Unresolved
         elsif not Locally_Defined then
            --  If the subprogram is not yet in the list then we insert it.
            --  Otherwise, we do nothing because there is no information to
            --  add.

            if not List_Of_Nodes.Has_Element (Found_Id) then
               --  Insert new unresolved node

               Node_Ptr := new Unresolved_Node'
                 (Target_Calls            => List_Of_Edges.Empty_Vector,
                  Accumulated_Stack_Usage => Unknown_Stack_Usage,
                  Location_List           => Locations_Set,
                  Subprogram              => Symbol_Name,
                  Under_Analysis          => False,
                  Cycle_Analysis_Finished         => False,
                  Cycles                  => List_Of_Cycles.Empty_Vector);

               List_Of_Nodes.Insert (List_Of_Subprograms, Node_Ptr);
            end if;

         --  Explicit node
         else
            --  If the subprogram is not yet in the list then we insert it.
            --  Otherwise, we upgrade the information that we have about the
            --  subprogram.

            if not List_Of_Nodes.Has_Element (Found_Id) then
               --  Insert new explicit node

               Node_Ptr := new Explicit_Node'
                 (Target_Calls            => List_Of_Edges.Empty_Vector,
                  Accumulated_Stack_Usage => Unknown_Stack_Usage,
                  Location_List           => Locations_Set,
                  Subprogram              => Symbol_Name,
                  Stack_Info              => Stack_Info,
                  Under_Analysis          => False,
                  Cycle_Analysis_Finished         => False,
                  Cycles                  => List_Of_Cycles.Empty_Vector);

               List_Of_Nodes.Insert (List_Of_Subprograms, Node_Ptr);

            else
               --  The node is already in the list. We have to check whether we
               --  have new information to insert.

               Found_Node := List_Of_Nodes.Element (Found_Id);

               if Found_Node.all in Explicit_Node'Class then
                  --  Check the different fields

                  --  There are some fields that cannot be changed when
                  --  analyzing a node: Target_Calls and
                  --  Accumulated_Stack_Usage.

                  --  Merge the location list

                  Explicit_Node (Found_Node.all).Location_List.Union
                    (Locations_Set);

                  --  Check information about stack usage and update if
                  --  necessary.

                  Explicit_Node (Found_Node.all).Update_Stack_Usage
                    (Stack_Info);

               else
                  --  The node needs to be changed to an explicit node. We
                  --  will include the information that we already had.

                  Node_Ptr := new Explicit_Node'
                    (Target_Calls            => Found_Node.Target_Calls,
                     Accumulated_Stack_Usage => Unknown_Stack_Usage,
                     Location_List           => Locations_Set,
                     Subprogram              => Symbol_Name,
                     Stack_Info              => Stack_Info,
                     Under_Analysis          => False,
                     Cycle_Analysis_Finished         => False,
                     Cycles                  => List_Of_Cycles.Empty_Vector);

                  --  Merge the location list

                  Explicit_Node (Node_Ptr.all).Location_List.Union
                    (Get_Location_List (Found_Node.all));

                  List_Of_Nodes.Replace_Element
                       (List_Of_Subprograms, Found_Id, Node_Ptr);

                  --  Free the old node ???

               end if;
            end if;
         end if;
      end;
   end Parse_Node;

   -----------------
   -- Parse_Title --
   -----------------

   procedure Parse_Title
     (Input : in String; Symbol : out Static_Stack_Analysis.Subprogram_Name)
   is
   begin
      if Input'Length /= 0 then
         Symbol := new String'(Input);
      else
         raise Parser_Error;
      end if;
   end Parse_Title;

   -----------------
   -- Parse_Label --
   -----------------

   procedure Parse_Label
     (Input     : in String;
      Demangled : out Static_Stack_Analysis.Subprogram_Name;
      Locations : out Static_Stack_Analysis.List_Of_Locations.Set;
      Stack     : out Static_Stack_Analysis.Stack_Usage_Info)
   is
      Matches : GNAT.Regpat.Match_Array (0 .. 6);

   begin
      GNAT.Regpat.Match (Label_Regexp, Input, Matches);

      if Matches (0) = GNAT.Regpat.No_Match then
         raise Parser_Error;

      else
         --  The following are optional fields

         if Matches (1) /= GNAT.Regpat.No_Match then
            Demangled :=
              new String'(Input (Matches (1).First .. Matches (1).Last));
         else
            Demangled := null;
         end if;

         if Matches (3) /= GNAT.Regpat.No_Match then
            Parse_Locations
              (Input (Matches (3).First .. Matches (3).Last),
               Demangled,
               Locations);
         else
            Locations := Static_Stack_Analysis.List_Of_Locations.Empty_Set;
         end if;

         if Matches (5) /= GNAT.Regpat.No_Match then
            Parse_Stack_Usage
              (Input (Matches (5).First .. Matches (5).Last), Stack);
         else
            Stack := Static_Stack_Analysis.Unknown_Stack_Usage;
            Stack.Unknown_Usage :=
              Static_Stack_Analysis.Frame_Size (Options.Default_Unknown);
         end if;
      end if;
   end Parse_Label;

   --------------------
   -- Parse_Location --
   --------------------

   procedure Parse_Locations
     (Input     : in String;
      Demangled : in Static_Stack_Analysis.Subprogram_Name;
      Locations : out Static_Stack_Analysis.List_Of_Locations.Set)
   is
      Matches : GNAT.Regpat.Match_Array (0 .. 4);

      Tmp_Location  : Static_Stack_Analysis.Location;

   begin
      --  Check for no location specified

      GNAT.Regpat.Match (No_Location_Regexp, Input, Matches);

      if Matches (0) /= GNAT.Regpat.No_Match then
         Locations := Static_Stack_Analysis.List_Of_Locations.Empty_Set;

      else
         GNAT.Regpat.Match (Location_Regexp, Input, Matches);

         if Matches (0) /= GNAT.Regpat.No_Match then

            Tmp_Location.File :=
              new String'(Input (Matches (1).First .. Matches (1).Last));

            Tmp_Location.Demangled := Demangled;

            Tmp_Location.Line_Number :=
              Integer'Value (Input (Matches (2).First .. Matches (2).Last));

            --  The column number is not always present

            if Matches (3) /= GNAT.Regpat.No_Match then
               Tmp_Location.Column_Number :=
                 Integer'Value (Input (Matches (3).First .. Matches (3).Last));
            else
               Tmp_Location.Column_Number := 0;
            end if;

            --  Parse additional locations, if any

            if Matches (4) /= GNAT.Regpat.No_Match then
               Parse_Locations
                 (Input (Matches (4).First .. Matches (4).Last),
                  Demangled,
                  Locations);
            end if;

            --  Include the parsed location if it is not already in the list

            Locations.Include (Tmp_Location);

         else
            raise Parser_Error;
         end if;

      end if;
   end Parse_Locations;

   -----------------------
   -- Parse_Stack_Usage --
   -----------------------

   procedure Parse_Stack_Usage
     (Input : in String; Stack : out Static_Stack_Analysis.Stack_Usage_Info)
   is
      Matches : GNAT.Regpat.Match_Array (0 .. 2);

   begin
      GNAT.Regpat.Match (Stack_Regexp, Input, Matches);

      if Matches (0) /= GNAT.Regpat.No_Match then
         Stack.Static_Usage :=
           Static_Stack_Analysis.Frame_Size'Value
             (Input (Matches (1).First .. Matches (1).Last));

         if Matches (2) = GNAT.Regpat.No_Match
           or else Input (Matches (2).First .. Matches (2).Last) = " (static)"
         then
            Stack.Frame_Type := Static_Stack_Analysis.Static;
            Stack.Dynamic_Usage := 0;
            Stack.Unknown_Usage := 0;

         elsif
           Input (Matches (2).First .. Matches (2).Last) = " (dynamic)"
         then
            Stack.Frame_Type := Static_Stack_Analysis.Unbounded;
            Stack.Dynamic_Usage :=
              Static_Stack_Analysis.Frame_Size (Options.Default_Unbounded);
            Stack.Unknown_Usage := 0;

         elsif
           Input (Matches (2).First .. Matches (2).Last) = " (dynamic,bounded)"
         then
            Stack.Frame_Type := Static_Stack_Analysis.Bounded;
            Stack.Dynamic_Usage := 0;
            Stack.Unknown_Usage := 0;

         else
            raise Parser_Error;
         end if;

      else
         raise Parser_Error;
      end if;
   end Parse_Stack_Usage;

   -----------------
   -- Parse_Shape --
   -----------------

   procedure Parse_Shape (Input : in String; Local : out Boolean) is
   begin
      --  The mark 'ellipse' indicates an external subprogram, i.e., not
      --  locally defined.

      Local := Input /= " shape : ellipse";
   end Parse_Shape;

   ----------------
   -- Parse_Edge --
   ----------------

   procedure Parse_Edge (Input : String) is
      use Static_Stack_Analysis;

      Matches    : GNAT.Regpat.Match_Array (0 .. 2);

      Source_Id  : Static_Stack_Analysis.Node_Id;
      Target_Id  : Static_Stack_Analysis.Node_Id;

      Source_Ptr : Static_Stack_Analysis.Node_Class_Access;
      Target_Ptr : Static_Stack_Analysis.Node_Class_Access;

      Inserted   : Boolean;

   begin
      --  The pattern of the input line is:
      --  edge: { sourcename: "([^"]+)" targetname: "([^"]+)" }

      --  Get source and target

      GNAT.Regpat.Match (Edge_Regexp, Input, Matches);

      if Matches (0) /= GNAT.Regpat.No_Match then
         --  Look for the source node in the list, or create the node if it
         --  does not exist yet.

         Source_Id := Get_Node (Input (Matches (1).First .. Matches (1).Last));

         if not List_Of_Nodes.Has_Element (Source_Id) then
            Source_Ptr := new Unresolved_Node'
              (Target_Calls            => List_Of_Edges.Empty_Vector,
               Accumulated_Stack_Usage => Unknown_Stack_Usage,
               Location_List           => List_Of_Locations.Empty_Set,
               Subprogram              =>
                 new String'(Input (Matches (1).First .. Matches (1).Last)),
               Under_Analysis          => False,
               Cycle_Analysis_Finished => False,
               Cycles                  => List_Of_Cycles.Empty_Vector);

            List_Of_Subprograms.Insert (Source_Ptr, Source_Id, Inserted);

            pragma Assert (Inserted);
         else
            --  Get the node so we can add the new information later on

            Source_Ptr := List_Of_Nodes.Element (Source_Id);
         end if;

         --  Look for the source node in the list, or create the node if it
         --  does not exist yet.

         Target_Id := Get_Node (Input (Matches (2).First .. Matches (2).Last));

         if not List_Of_Nodes.Has_Element (Target_Id) then

            --  Create an indirect node for an indirect call
            if
              Input (Matches (2).First .. Matches (2).Last) = Indirect_Call.all
            then
               Target_Ptr := new Indirect_Node'
                 (Target_Calls            => List_Of_Edges.Empty_Vector,
                  Accumulated_Stack_Usage => Unknown_Stack_Usage,
                  Under_Analysis          => False,
                  Cycle_Analysis_Finished => False,
                  Cycles                  => List_Of_Cycles.Empty_Vector);

            --  This node is considered unresolved for the moment. It can be
            --  later modified if we find more information.
            else
               Target_Ptr := new Unresolved_Node'
                 (Target_Calls            => List_Of_Edges.Empty_Vector,
                  Accumulated_Stack_Usage => Unknown_Stack_Usage,
                  Location_List           => List_Of_Locations.Empty_Set,
                  Subprogram              =>
                    new String'(Input (Matches (2).First .. Matches (2).Last)),
                  Under_Analysis          => False,
                  Cycle_Analysis_Finished => False,
                  Cycles                  => List_Of_Cycles.Empty_Vector);
            end if;

            List_Of_Subprograms.Insert (Target_Ptr, Target_Id, Inserted);

            pragma Assert (Inserted);
         end if;

         --  Now we need to check whether there is already an edge joining
         --  these two subprograms. We add the new location if the node exists,
         --  or create a new edge otherwise.

         declare
            Index : Static_Stack_Analysis.Edge_Id :=
              Source_Ptr.Target_Calls.First;

            Call : Static_Stack_Analysis.Edge;

         begin
            while Static_Stack_Analysis.List_Of_Edges.Has_Element (Index) loop
               Call := Static_Stack_Analysis.List_Of_Edges.Element (Index);

               if Static_Stack_Analysis."=" (Call.Target, Target_Id) then
                  --  Add new location. We do not have yet the information ???

                  exit;

               else
                  Static_Stack_Analysis.List_Of_Edges.Next (Index);
               end if;
            end loop;

            if not Static_Stack_Analysis.List_Of_Edges.Has_Element (Index) then
               --  Create new edge with the information that we have about the
               --  source and the target.

               Static_Stack_Analysis.List_Of_Edges.Append
                 (Source_Ptr.Target_Calls,
                  new Static_Stack_Analysis.Edge_Element'(
                    Target         => Target_Id,
                    Point_Of_Call  => List_Of_Locations.Empty_Set,
                    Feasible_Call  => True,
                    Under_Analysis => False));
            end if;
         end;
      else
         raise Parser_Error;
      end if;
   end Parse_Edge;

   ----------------------
   -- Parse_Input_File --
   ----------------------

   procedure Parse_Input_File (File : File_Id) is
      Descriptor : Ada.Text_IO.File_Type;
   begin
      Ada.Text_IO.Open
        (Descriptor, Ada.Text_IO.In_File, List_Of_Files.Element (File).all);

      --  Parse information line by line

      while not Ada.Text_IO.End_Of_File (Descriptor) loop
         Parse_Input_Line (Ada.Text_IO.Get_Line (Descriptor));
      end loop;

      Ada.Text_IO.Close (Descriptor);
   end Parse_Input_File;

   -----------
   -- Usage --
   -----------

   procedure Usage is
      use Ada.Text_IO;
   begin
      Put_Line ("Usage: ssat [args ...] <files>");
      New_Line;
      Put_Line ("where possible arguments are:");
      New_Line;
      Put_Line ("  -h           display help message");
      New_Line;
      Put_Line ("  -v           verbose");
      New_Line;
      Put_Line ("  -ca          extract all cycles");
      New_Line;
      Put_Line ("  -Wxx         enable warnings, xx = list of parameters:");
      Put_Line ("    a          turn on all optional warnings");
      Put_Line ("    c          turn on warnings for cycles");
      Put_Line ("    u          turn on warnings for unbounded frames");
      Put_Line ("    e          turn on warnings for external calls");
      Put_Line ("    i          turn on warnings for indirect calls");
      New_Line;
      Put_Line ("  -o={a,s}     order for displaying call graphs");
      Put_Line ("  -o=a         alphabetical");
      Put_Line ("  -o=s         stack usage (default)");
      New_Line;
      Put_Line ("  -u size      default for unknown (external) calls");
      New_Line;
      Put_Line ("  -d size      default for unbounded (dynamic) calls");
      New_Line;
      Put_Line ("  -a           analyze all subprograms");
      Put_Line ("  -e <list>    list of entry points (e1,e2,...)");
      Put_Line ("  -r <reg-exp> analyze subprograms matching the pattern");
      New_Line;
      Put_Line ("  -g file      output graph file");
      New_Line;
      Put_Line ("  <files>      list of .ci files (c1.ci c2.ci ...)");
      New_Line;
   end Usage;

end Parser;
