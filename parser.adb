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

with Options;
--  Used for Verbose
--           Explore_All
--           Default_Unknown
--           Default_Unbounded
--           List_Of_Entry_Points
--           Output_File

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

   ------------------------
   -- Handle input files --
   ------------------------

   function Equal (Left, Right : GNAT.Strings.String_Access) return Boolean;
   --  Compare two pointers to String. They will be considered equal if both
   --  are null pointers, or else if both contain the same String.

   package List_Of_Files is new
     Ada.Containers.Vectors (Natural, GNAT.Strings.String_Access, Equal);

   Input_Files : List_Of_Files.Vector := List_Of_Files.Empty_Vector;
   --  List of input files containing

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
   --  Format : ellipse

   procedure Parse_Edge (Input : String);
   --  Get caller and callee in a subprogram call.
   --  Format : ^edge: { sourcename: "symbol_name" targetname: "symbol_name"

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
         case GNAT.Command_Line.Getopt ("h v a u: d: e: o:") is
            when ASCII.NUL =>
               exit;

            when 'v' =>
               Options.Verbose := True;

            when 'a' =>
               Options.Explore_All := True;

            when 'u' =>
               Options.Default_Unknown :=
                 Natural'Value (GNAT.Command_Line.Parameter);

            when 'd' =>
               Options.Default_Unbounded :=
                 Natural'Value (GNAT.Command_Line.Parameter);

            when 'e' =>
               Options.List_Of_Entry_Points :=
                 new String'(GNAT.Command_Line.Parameter);

            when 'o' =>
               Options.Output_File :=
                 new String'(GNAT.Command_Line.Parameter);

            when others =>
               Usage;
               GNAT.OS_Lib.OS_Exit (1);
         end case;
      end loop;

      --  Get list of entry files

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

      --  Get the list of subprograms to be considered as entry points

      if Options.List_Of_Entry_Points /= null then
         Parse_Entry_Points (Options.List_Of_Entry_Points.all);
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

      Locations_Set   : List_Of_Locations.Set :=
        List_Of_Locations.Empty_Set;

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
            --  This is an indirect call. We cannot get any more information

            null;

         --  Unresolved
         elsif not Locally_Defined
           and then not List_Of_Nodes.Has_Element (Found_Id)
         then
            --  Insert new unresolved node

            Node_Ptr := new Unresolved_Node'
              (Target_Calls            => List_Of_Edges.Empty_Vector,
               Accumulated_Stack_Usage => Unknown_Stack_Usage,
               Location_List           => Locations_Set,
               Subprogram              => Symbol_Name,
               Under_Analysis          => False);

            List_Of_Nodes.Insert (List_Of_Subprograms, Node_Ptr);

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
                  Under_Analysis          => False);

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
                     Under_Analysis          => False);

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
         Symbol :=
           new String'(Input);
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

         elsif Input (Matches (2).First .. Matches (2).Last) =
               " (dynamic)"
         then
            Stack.Frame_Type := Static_Stack_Analysis.Unbounded;
            Stack.Dynamic_Usage :=
              Static_Stack_Analysis.Frame_Size (Options.Default_Unbounded);
            Stack.Unknown_Usage := 0;

         elsif Input (Matches (2).First .. Matches (2).Last) =
               " (dynamic,bounded)"
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
      Local := Input = "ellipse";
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

      Name       : Subprogram_Name;

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

            Name := new String'(Input (Matches (1).First .. Matches (1).Last));

            Source_Ptr := new Unresolved_Node'
              (Target_Calls            => List_Of_Edges.Empty_Vector,
               Accumulated_Stack_Usage => Unknown_Stack_Usage,
               Location_List           => List_Of_Locations.Empty_Set,
               Subprogram              => Name,
               Under_Analysis          => False);

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

            Name := new String'(Input (Matches (2).First .. Matches (2).Last));

            Target_Ptr := new Unresolved_Node'
              (Target_Calls            => List_Of_Edges.Empty_Vector,
               Accumulated_Stack_Usage => Unknown_Stack_Usage,
               Location_List           => List_Of_Locations.Empty_Set,
               Subprogram              => Name,
               Under_Analysis          => False);

            List_Of_Subprograms.Insert (Target_Ptr, Target_Id, Inserted);

            pragma Assert (Inserted);
         end if;

         --  Now we create the edge with the information that we have about the
         --  source and the target.

         Static_Stack_Analysis.List_Of_Edges.Append
           (Source_Ptr.Target_Calls, (Target_Id, Null_Location, True));

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
      Put_Line ("  -h          display help message");
      New_Line;
      Put_Line ("  -v          verbose");
      New_Line;
      Put_Line ("  -u size     default for unknown (external) calls");
      New_Line;
      Put_Line ("  -d size     default for unbounded (dynamic) calls");
      New_Line;
      Put_Line ("  -a          analyze all subprograms");
      New_Line;
      Put_Line ("  -e <list>   list of entry points (e1,e2,...)");
      New_Line;
      Put_Line ("  -o file     output file");
      New_Line;
      Put_Line ("  <files>     list of .ci files (c1.ci c2.ci ...)");
      New_Line;
   end Usage;

end Parser;
