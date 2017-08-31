------------------------------------------------------------------------------
--                        STATIC STACK ANALYSIS TOOL                        --
--                                                                          --
--                               P A R S E R                                --
--                                                                          --
--                                 B o d y                                  --
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

--  This file, in particular, is in a transitional state due to an
--  an interruption on Nov. 21, 2013 of the work being done on
--  IC15-033.
--
--  This comment is a quick recording of the status, for the purpose
--  of future guidance on continuing that work. The bigger picture
--  might be to only use the executable file as the source of callgraph
--  information, but the code is structured in a way to easily allow an
--  intermediate implementation which accepts .ci files, .o files
--  or executable files as sources of callgraph info. This would
--  support the original interface wherein .ci files from every
--  compilation are provided, while allowing object files to be
--  used instead.
--
--  In Parse_Arguments, after dealing with switches and options,
--  all the input files are processed. The .ci files are put into
--  one list, and other files are presumed to be object files.
--  In previous versions, the object files were processed by a
--  spawned objdump to create a temporary .ci file which was placed
--  on the second list. The work that is partially done, is towards
--  using packages which process ELF files to get the callgraph
--  info directly from the program section of an ELF file
--  (instead of dumping it to a temp .ci file). The name of the
--  object file will go in the second list in place of the temp .ci
--  extracted from it.
--
--  There are two routines which are called for every file on
--  the 2 lists: Count_Entities and Parse_Input_File. Count_Entities
--  has been split into Count_Entities_CI and Count_Entities_ELF;
--  the former is called for the .ci files on the first list, and
--  the latter for the ELF files in the second list. Both of these
--  routines get the entire contents of the callgraph info (entire
--  file, or entire program section) into a buffer and then call
--  Count_Entities_Buf to process that buffer. This part is done,
--  except for some error checking while processing ELF files.
--
--  The intention is to split Parse_Input_File the same way as
--  Count_Entities, and get rid of the external extraction (spawning
--  objdump) of callgraph info into temp .ci files.

with System.OS_Lib;

with Ada.Containers.Vectors;
with Ada.Directories;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;
with Ada.Text_IO;
with Ada.Exceptions;
with Ada.Characters.Handling;

with GNAT.Regpat;
with GNAT.Command_Line;
with GNAT.Strings;
with GNAT.OS_Lib;

with Elf_Common; use Elf_Common;
with Elf_Files; use Elf_Files;

with GNATCOLL.Mmap; use GNATCOLL.Mmap;

with GNATCOLL.Projects;
with GNATCOLL.VFS;

with Global_Data;
with Static_Stack_Analysis;
with Options;
with Display;
with Version;
with Demangle;

package body Parser is

   use type Static_Stack_Analysis.Location;
   use type GNAT.Regpat.Match_Location;
   use type GNAT.Strings.String_Access;

   ----------------
   -- Local data --
   ----------------

   Parser_Error : exception renames Static_Stack_Analysis.Parser_Error;
   --  Exception to be raised when unexpected data is found

   Ada_File_Name : Static_Stack_Analysis.File_Name := null;
   --  Name of the Ada file originating the .ci file that we are currently
   --  processing.

   Descriptor : Ada.Text_IO.File_Type;
   --  File descriptor for the file being processed. It is places as a global
   --  variable for better warning messages.

   -----------------------
   -- Local subprograms --
   -----------------------

   procedure Usage;
   --  Print how to use the tool

   function Pattern_In_Node
     (Pattern  : String; Position : Static_Stack_Analysis.Node_Id)
      return Boolean;
   --  Look for the pattern in the list of subprograms, including both
   --  mangled and demangled symbol names, in a case-insensitive manner.
   --  Return True if the referenced node describes a subprogram containing
   --  the specified pattern. We avoid the problem of upper/lower case by
   --  transforming both the pattern and the string into lower case values.

   procedure Add_Pattern_Entry (Position : Static_Stack_Analysis.Node_Id);
   --  Add the node to the list of entry points to analyze if its symbol name
   --  contains the pattern specified in Options.Entry_Point_Pattern.

   procedure Get_Stack_Usage_Files (From_File : String);
   --  Get the list of .ci files that are listed in the specified text file

   procedure Print_Usage_And_Exit;
   pragma Inline (Print_Usage_And_Exit);
   --  Print how to get usage information and exit

   procedure Print_Help_And_Exit;
   pragma Inline (Print_Help_And_Exit);
   --  Print detailed help information and exit

   procedure Get_Task_Wrapper (Position : Static_Stack_Analysis.Node_Id);
   --  Get a pointer to this node if it contains the task wrapper (used for
   --  Ada tasking).

   ------------------------
   -- Handle input files --
   ------------------------

   function Equal (Left, Right : GNAT.Strings.String_Access) return Boolean;
   --  Compare two pointers to String. They will be considered equal if both
   --  are null pointers, or else if both contain the same String.

   package List_Of_Files is new
     Ada.Containers.Vectors (Natural, GNAT.Strings.String_Access, Equal);

   Stack_Usage_File_Extension : constant String := "ci";
   --  Extension of the stack usage information files generated by the
   --  compiler.

   function Is_Stack_Usage_Information_File
     (File_Name : GNAT.Strings.String_Access) return Boolean;
   --  Given a file name returns True is the file is a stack usage information
   --  file output by the compiler.

   Input_Files : List_Of_Files.Vector := List_Of_Files.Empty_Vector;
   --  List of input files containing stack usage information (.ci files)

   Input_Tmp_Files : List_Of_Files.Vector := List_Of_Files.Empty_Vector;
   --  List of temporary input files containing stack usage information (.ci
   --  files) that have been extracted from the object files.

   procedure Append_Files_From_Directory
     (Input_Files : in out List_Of_Files.Vector;
      Dir         : String);
   --  Append all stack usage information files contained in a directory to
   --  the list of input files.

   procedure Deallocate_File_Names (Position : List_Of_Files.Cursor);
   --  Deallocate the strings used to store file names

   procedure Remove_Files (Position : List_Of_Files.Cursor);
   --  Remove the list of files

   subtype File_Id is List_Of_Files.Cursor;
   --  Unique identifier for files

   procedure Count_Entities_CI  (File : File_Id);
   procedure Count_Entities_ELF (File : File_Id);
   procedure Count_Entities_Buf (Buf  : GNATCOLL.Mmap.Str_Access;
                                 Last : Integer);
   --  Procedures to get the number of entities to process.
   --  The CI version takes the name of a callgraph info file.
   --  The ELF version takes the name of an ELF file containing
   --    a .ci??? section containing callgraph info.
   --  The BUF version is called by both of the other versions.
   --    Both of the others create a string containing the
   --    ci info, and then call _BUF to do the actual parsing
   --    and counting.

   package Project is

      Env : GNATCOLL.Projects.Project_Environment_Access;
      --  Environment

      procedure Get_Project_Info;
      --  This procedure does an initial parsing of the command-line switches.
      --  The goal is to insert GNATstack switches coming from project files
      --  (if any) and to get stack information from the run-time library:
      --   - Process project-related switches: -P, -X
      --   - Extract the list of GNATstack switches from project files
      --   - Add .ci files coming from the object directories belonging to the
      --     hierarchy of projects
      --  Values from the command line take precedence over those in the
      --  project file.

      function Get_Option return Character;
      function Get_Switch return String;
      function Get_Parameter return String;
      --  Three functions to get the switches from both the project file and
      --  the command line. Enforce preference of values from command line over
      --  project files.

   end Project;

   package body Project is separate;

   --------------------
   -- Count_Entities --
   --------------------

   procedure Count_Entities_CI (File : File_Id) is
      Mfile : Mapped_File;
      File_Contents : GNATCOLL.Mmap.Str_Access;
      File_Len : Integer;
   begin
      Mfile := Open_Read (List_Of_Files.Element (File).all);
      Read (Mfile);
      File_Contents := Data (Mfile);
      File_Len := Last (Mfile);
      Count_Entities_Buf (File_Contents, File_Len);
      Close (Mfile);
   end Count_Entities_CI;

   procedure Count_Entities_ELF (File : File_Id) is
      Bin : Elf_File;
      CI_Index : Elf_Half;
      CI_Section : Mapped_Region;
      CI_Contents : GNATCOLL.Mmap.Str_Access;
      CI_Size : Integer;
   begin
      Open_File (Bin, List_Of_Files.Element (File).all);
      Load_Shdr (Bin);
      CI_Index := Get_Shdr_By_Name (Bin, ".GNU.callgraph");
      CI_Section := Load_Section (Bin, CI_Index);
      CI_Contents := Data (CI_Section);
      CI_Size := Last (CI_Section);
      Count_Entities_Buf (CI_Contents, CI_Size);
      Close_File (Bin);
   end Count_Entities_ELF;

   procedure Count_Entities_Buf (Buf  : GNATCOLL.Mmap.Str_Access;
                                 Last : Integer) is
      Matches : GNAT.Regpat.Match_Array (0 .. 3);
      BOL, EOL : Positive;
   begin
      BOL := 1;
      while BOL <= Last loop
         EOL := BOL;
         loop
            exit when EOL = Last or else Buf (EOL) = ASCII.LF;
            EOL := EOL + 1;
         end loop;

         GNAT.Regpat.Match ("^(node:)|(edge:)|(class)",
                            String (Buf (BOL .. EOL)), Matches);

         if Matches (1) /= GNAT.Regpat.No_Match then
            Global_Data.Expected_Entities (Global_Data.Parse_Subprogram) :=
              Global_Data.Expected_Entities (Global_Data.Parse_Subprogram) + 1;

         elsif Matches (2) /= GNAT.Regpat.No_Match then
            Global_Data.Expected_Entities (Global_Data.Parse_Call) :=
              Global_Data.Expected_Entities (Global_Data.Parse_Call) + 1;

         elsif Matches (3) /= GNAT.Regpat.No_Match then
            Global_Data.Expected_Entities (Global_Data.Class) :=
              Global_Data.Expected_Entities (Global_Data.Class) + 1;
         end if;
         BOL := EOL + 1;
      end loop;
   end Count_Entities_Buf;

   ---------------------------
   -- Deallocate_File_Names --
   ---------------------------

   procedure Deallocate_File_Names (Position : List_Of_Files.Cursor) is
      File_Name : GNAT.Strings.String_Access :=
        List_Of_Files.Element (Position);

   begin
      GNAT.Strings.Free (File_Name);
   end Deallocate_File_Names;

   ------------------
   -- Remove_Files --
   ------------------

   procedure Remove_Files (Position : List_Of_Files.Cursor) is
      File_Name : constant GNAT.Strings.String_Access :=
        List_Of_Files.Element (Position);

      Success : Boolean;

   begin
      System.OS_Lib.Delete_File (File_Name.all, Success);
      pragma Assert (Success);
   end Remove_Files;

   -----------------------
   -- Expected patterns --
   -----------------------

   Entity_Regexp : constant GNAT.Regpat.Pattern_Matcher :=
     GNAT.Regpat.Compile ("^(node:|edge:|class) {([^}]*)$");
   --  Pattern to detect the entities that are analyzed

   Node_Regexp : constant GNAT.Regpat.Pattern_Matcher :=
     GNAT.Regpat.Compile
       ("^node: {" &
        " title: ""([^""]+)""" &
        "( label: ""[^""]*"")?" &
        "( alias: ""([^""]*)"")?" &
        "( shape : \w*)?" &
        "\s*}");
   --  The information that is mandatory for a node is the title which
   --  represents the subprogram symbol.

   Edge_Regexp : constant GNAT.Regpat.Pattern_Matcher :=
     GNAT.Regpat.Compile
       ("^edge: {" &
        "\s*sourcename: ""([^""]*)""" &
        "\s*targetname: ""([^""]*)""" &
        "(\s*label: "".*""| priority: .*)?" &
        "\s*}");
   --  The information that is mandatory for an edge is the symbols associated
   --  to the subprograms acting as caller and callee.

   Class_Regexp : constant GNAT.Regpat.Pattern_Matcher :=
     GNAT.Regpat.Compile
       ("^class {" &
        "\s*classname: ""([^""]*)""" &
        "\s*label: ""([^""]*)""" &
        "(\s*parent: ""([^""]*)"")?" &
        "\s*virtuals: ""([^""]*)""" &
        "\s*}");
   --  The information that is mandatory for a class is its name, location,
   --  set of virtual functions (we represent only the hierarchy of
   --  polymorphic classes and bases), and the list of parents (if any).

   Header_Regexp : constant GNAT.Regpat.Pattern_Matcher :=
     GNAT.Regpat.Compile ("^graph: { title: ""([^""]*)""");
   --  It indicates that it is a compiler-generated file, and not one created
   --  by the user.

   Allowed_Lines_Regexp : constant GNAT.Regpat.Pattern_Matcher :=
     GNAT.Regpat.Compile ("^\s*(}|--|$)");
   --  Ada comments and blank lines are allowed

   Location_Regexp : constant String :=
     "(<no location>)|" &  -- Encoding for no location
     "(<built-in>.*|<internal>.*)|" &  -- Location for built-in functions
     "(((\\\\|[a-zA-Z]:[\\/])?[\w\\/ \.~\-\+]+)" &  -- Normal locations
     ":(\d+)(:\d+)?)";  -- line and possibly column number
   --  Accepted locations are Unix-style (directories separated by slashes),
   --  Windows UNC-style (drive_letter:\path or \\server\path), and
   --  cygwin-style (drive_letter:/path or /path). There is also .extension
   --  for the file, and file location (:line[:column]). Note that sometimes,
   --  on cygwin, locations have a pattern with mixed / and \, such as
   --  /path\file.ext.

   Stack_Regexp : constant String :=
     "(\d+) bytes( \(static\)| \(dynamic\)| \(dynamic,bounded\))?";
   --  At least the size in bytes

   Node_Label_Regexp : constant GNAT.Regpat.Pattern_Matcher :=
     GNAT.Regpat.Compile
       ("^ label: " &
        """((&|\*|\*\*|\+|\-|/|/=|<|<=|>|>=|=|" &  -- Unary operators
        "[\w \(\):,\*\&<>\[\]=~\+\-\|!\{\}\$\?/\^]*)\\n)?" &  -- Demangled name
        "((" & Location_Regexp & ",?)*(\\n)?)?" &
        "(" & Stack_Regexp & ")?" &
        "(\\n\d+ dynamic objects(\\n .*)?)?""$");
   --  Extra information about a node

   Edge_Label_Regexp : constant GNAT.Regpat.Pattern_Matcher :=
     GNAT.Regpat.Compile
       ("^\s*label: ""(" & Location_Regexp & "( \[.+\])?)" & """$");
   --  Extra information about an edge

   Class_Label_Regexp : constant GNAT.Regpat.Pattern_Matcher :=
     GNAT.Regpat.Compile
       ("(([^\\]+)\\n)?(" & Location_Regexp & "( \[.+\])?)$");
   --  Demangled name and location information in classes

   Subprogram_Location_Regexp : constant GNAT.Regpat.Pattern_Matcher :=
     GNAT.Regpat.Compile ("^(" & Location_Regexp & ")(,.+)*$");
   --  Comma-separated list of locations

   Data_Location_Regexp : constant GNAT.Regpat.Pattern_Matcher :=
     GNAT.Regpat.Compile
       ("^\\n ([\w \+\-\[\]\(\)<>]+) (" & Location_Regexp & ")(\\n .+)*$");
   --  Location of an unbounded object

   Front_End_Location_Regexp : constant GNAT.Regpat.Pattern_Matcher :=
     GNAT.Regpat.Compile ("^(" & Location_Regexp & ")( \[.+\])?$");
   --  List of locations using [] for nesting

   Create_Task : constant String := "system__tasking__stages__create_task";
   Create_Ravenscar_Task : constant String :=
     "system__tasking__restricted__stages__create_restricted_task";
   --  Subprograms called to create tasks

   Dispatching_Regexp : constant GNAT.Regpat.Pattern_Matcher :=
     GNAT.Regpat.Compile ("([\-]?\d+):([^:,]+),([^:]+)");
   --  Look for triple slot:base_class,static_class

   Name_Regexp   : constant GNAT.Regpat.Pattern_Matcher :=
     GNAT.Regpat.Compile ("([^,]+)(, .*)?$");
   --  Comma-separated list of names

   Virtual_Set_Regexp  : constant GNAT.Regpat.Pattern_Matcher :=
     GNAT.Regpat.Compile ("([^\\]+)(\\n\s*.+)?$");
   --  The information for each virtual method is separated by \n

   Virtual_Info_Regexp : constant GNAT.Regpat.Pattern_Matcher :=
     GNAT.Regpat.Compile
       ("([\-]?\d+):([^,]+)(,([\-]?\d+):([^,]+))?" &
          "(,([\-]?\d+):([^,]+))?$");
   --  For a given virtual method we have the slot_number:symbol_name,
   --  and possibly the primary and secondary vtables that it overrides.

   ------------------------
   -- Parsing operations --
   ------------------------

   procedure Parse_File_Name (Input : String);
   --  Get the name of the file from which the stack usage information is
   --  derived.

   procedure Parse_Input_File (File : File_Id);
   --  Extract the information from the specified file by parsing every line
   --  in the file.

   procedure Parse_Input_Line (Input : String);
   --  Extract the information from the single line being read from a file

   procedure Parse_Node (Input : String);
   --  Extract the information about a node. The expected format is:
   --  ^node: { title: "symbol_name" label: "LABEL"[ shape : ellipse] }

   function Get_Unique_Symbol_Name (Input : String) return String;
   --  The input String should contain the symbol name generated by the
   --  compiler for a given subprogram. This name is usually, but not always,
   --  the symbol name in the object file. This function removes from the
   --  initial symbol name the file prefix (when not needed, as in the case
   --  of Ada) and the .NNN suffix for nested subprograms (not needed for
   --  having unique identifiers in Ada).

   procedure Parse_Node_Label
     (Input           : String;
      Demangled       : out Static_Stack_Analysis.Name;
      Locations       : out Static_Stack_Analysis.List_Of_Locations.Set;
      Stack           : out Static_Stack_Analysis.Stack_Usage_Info;
      Dynamic_Objects : out Static_Stack_Analysis.List_Of_Locations.Set);
   --  The label contain information about the demangled symbol name,
   --  locations in source files, and stack requirements extracted by the
   --  compiler.
   --  The format of the input String is:
   --  [demangled_name\n][LOC[,LOC]\n][N bytes[ (static|dynamic[,bounded])]]
   --  [M dynamic objects[\n DLOC[\n DLOC]]]

   procedure Parse_Node_Locations
     (Input     : String;
      Demangled : Static_Stack_Analysis.Name;
      Locations : out Static_Stack_Analysis.List_Of_Locations.Set);
   --  Extract the list of locations in source files.
   --  Format: [filename:line[:column][,filename:line[:column]]

   procedure Parse_Front_End_Locations
     (Input     : String;
      Demangled : Static_Stack_Analysis.Name;
      Locations : out Static_Stack_Analysis.List_Of_Locations.Set);
   --  Get the list of locations encoded in the string. It handles the list
   --  of locations encoded by the front end (file.ext:NN:CC). If the location
   --  is within an instantiation, then the instance location is appended,
   --  enclosed in square brackets (which can nest if necessary).
   --  Format: "f1.adb:10:10 [f2.ads:5:4 [f3.ads:43:10]]"

   procedure Parse_Stack_Usage
     (Input : String; Stack : out Static_Stack_Analysis.Stack_Usage_Info);
   --  Extract stack requirements.
   --  Format: N bytes[ (static|dynamic[,bounded])]

   procedure Parse_Shape (Input : String; Local : out Boolean);
   --  Local is set to True if the subprogram is defined in the compilation
   --  unit. For unresolved subprograms it returns False.
   --  Format :  shape : ellipse

   procedure Parse_Edge (Input : String);
   --  Get caller and callee in a subprogram call. It may also contain the
   --  location of the call. Format :
   --  ^edge: { sourcename: "symbol_name"
   --  targetname: "symbol_name|vtable_entry"
   --  [label: "location" ] }

   procedure Parse_Dynamic_Objects
     (Input           : String;
      Dynamic_Objects : out Static_Stack_Analysis.List_Of_Locations.Set);
   --  Extract the list of data locations in source files.
   --  Format: [\n name filename:line[\n name filename:line]]

   procedure Parse_Class (Input : String);
   --  Extract the information related to classes and related methods
   --  Format:
   --  class {
   --   classname: "name"
   --   label: "demangled_name\nfilename:line[:column]"
   --   [parent: "classname_parent1[, classname_parent2]"]
   --   virtuals: "slot_number:symbol_name[,slot_number:overrides_classname]
   --   [\n slot_number:symbol_name[,slot_number:overrides_classname]]"
   --  }

   -----------------------
   -- Add_Pattern_Entry --
   -----------------------

   procedure Add_Pattern_Entry (Position : Static_Stack_Analysis.Node_Id) is
   begin
      --  If the referenced node describes a subprogram containing the pattern
      --  defined in Options.Entry_Point_Pattern we add this subprogram to the
      --  list of potential entry points.

      if Pattern_In_Node (Options.Entry_Point_Pattern.all, Position) then
         --  If we have found the entry point we add it to the list

         Global_Data.Entry_Points.Append (Position);
      end if;
   end Add_Pattern_Entry;

   ---------------------------------
   -- Append_Files_From_Directory --
   ---------------------------------

   procedure Append_Files_From_Directory
     (Input_Files : in out List_Of_Files.Vector;
      Dir         : String)
   is
      use Ada.Directories;

      procedure Callback (Directory_Entry : Directory_Entry_Type);
      --  Subprogram called for each file in the directory.

      --------------
      -- Callback --
      --------------

      procedure Callback (Directory_Entry : Directory_Entry_Type) is
         Fullname : constant GNAT.Strings.String_Access :=
           new String'(Full_Name (Directory_Entry));
      begin
         if Is_Stack_Usage_Information_File (Fullname) then
            --  This dynamically allocated String is later destroyed in
            --  procedure Parse_Arguments.

            List_Of_Files.Append (Input_Files, Fullname);
         end if;
      end Callback;

   begin
      if Exists (Dir)
        and then Kind (Dir) = Directory
      then
         Search
           (Directory => Dir,
            Pattern   => "",
            Process   => Callback'Access);
      end if;
   end Append_Files_From_Directory;

   -----------
   -- Equal --
   -----------

   function Equal (Left, Right : GNAT.Strings.String_Access) return Boolean is
   begin
      --  The two pointers will be considered equal if both are null pointers
      --  or else if both contain the same String.

      return (Left = null and then Right = null)
        or else (Left /= null
                 and then Right /= null
                 and then Left.all = Right.all);
   end Equal;

   ---------------------------
   -- Get_Stack_Usage_Files --
   ---------------------------

   procedure Get_Stack_Usage_Files (From_File : String) is
      Descriptor : Ada.Text_IO.File_Type;

   begin
      Ada.Text_IO.Open (Descriptor, Ada.Text_IO.In_File, From_File);

      --  Parse information line by line

      while not Ada.Text_IO.End_Of_File (Descriptor) loop
         declare
            File_Name : constant GNAT.Strings.String_Access :=
              new String'(Ada.Text_IO.Get_Line (Descriptor));

         begin
            if Is_Stack_Usage_Information_File (File_Name) then
               --  This dynamically allocated String is later destroyed in
               --  procedure Parse_Arguments.

               List_Of_Files.Append (Input_Files, File_Name);
            end if;
         end;
      end loop;

      Ada.Text_IO.Close (Descriptor);

   end Get_Stack_Usage_Files;

   ----------------------
   -- Get_Task_Wrapper --
   ----------------------

   procedure Get_Task_Wrapper (Position : Static_Stack_Analysis.Node_Id) is
   begin
      if Static_Stack_Analysis.List_Of_Nodes.Has_Element
          (Global_Data.Task_Wrapper)
        and then
          GNAT.Regpat.Match
            ("stages__task_wrapper$",
             Static_Stack_Analysis.Get_Subprogram_Name
               (Static_Stack_Analysis.List_Of_Nodes.Element
                  (Position).all).all)
      then
         Global_Data.Task_Wrapper := Position;
      end if;
   end Get_Task_Wrapper;

   -------------------------------------
   -- Is_Stack_Usage_Information_File --
   -------------------------------------

   function Is_Stack_Usage_Information_File
     (File_Name : GNAT.Strings.String_Access) return Boolean is
   begin
      return Ada.Directories.Exists (File_Name.all)
        and then Ada.Directories.Extension (File_Name.all) =
          Stack_Usage_File_Extension;
   end Is_Stack_Usage_Information_File;

   ---------------------
   -- Parse_File_Name --
   ---------------------

   procedure Parse_File_Name (Input : String) is
      Matches : GNAT.Regpat.Match_Array (0 .. 1);

   begin
      --  Get the file name

      GNAT.Regpat.Match (Header_Regexp, Input, Matches);

      if Matches (1) /= GNAT.Regpat.No_Match then
         --  Do not deallocate the previous pointer Ada_File_Name. It will
         --  probably have been copied in nodes and edges to indicate where
         --  they appear.

         Ada_File_Name :=
           new String'(Input (Matches (1).First .. Matches (1).Last));
      end if;
   end Parse_File_Name;

   ---------------------
   -- Parse Arguments --
   ---------------------

   procedure Parse_Arguments is
      Entries : Integer;
      --  Number of entry points defined in the command line

      procedure Print_Version;
      --  Print version number and copyright notice

      procedure Print_Version is
      begin
         Ada.Text_IO.Put      ("GNATstack Pro ");
         Ada.Text_IO.Put_Line (Version.Version_String);
         Ada.Text_IO.Put_Line ("Copyright 2005-2017, AdaCore");
         Ada.Text_IO.New_Line;
      end Print_Version;

   begin
      --  First we get the projects related switches

      Parser.Project.Get_Project_Info;

      --  Get options

      declare
         Predef_Obj_Dirs : GNATCOLL.VFS.File_Array_Access;

      begin
         loop
            case Project.Get_Option is
            when ASCII.NUL =>
               exit;

            -- long option names --
            when '-' =>
               declare
                  Full : constant String := Project.Get_Switch;
               begin
                  --  --version
                  if Full = "-version" and then not Options.Verbose then
                     Print_Version;
                     GNAT.OS_Lib.OS_Exit (1);

                  --  --help
                  elsif Full = "-help" then
                     Print_Help_And_Exit;

                  --  Ignore project related switches (--target, --RTS) because
                  --  they have already been treated.
                  elsif Full = "-target" or else Full = "-RTS" then
                     null;

                  --  Wrong option
                  else
                     raise GNAT.Command_Line.Invalid_Switch;
                  end if;
               end;

            --  Verbose
            when 'v' =>
               Options.Verbose := True;

            --  Help
            when 'h' =>
               Print_Help_And_Exit;

            --  Debug
            when 'g' =>
               Options.Debug := True;

            --  Keep temporary files
            when 'k' =>
               Options.Remove_Temporary_Files := False;

            --  Biggest local stack usage
            when 'l' =>
               declare
               begin
                  Options.Number_Of_Biggest_Frames :=
                    Natural'Value (Project.Get_Parameter);
               exception
                  when Constraint_Error =>
                     raise GNAT.Command_Line.Invalid_Parameter;
               end;

            when 'c' =>
               declare
                  Switch : constant String := Project.Get_Switch;
               begin
                  --  All cycles
                  if Switch = "ca" then
                     Options.Compute_All_Cycles := True;

                  --  Default size for cycles
                  elsif Switch = "c" then
                     declare
                     begin
                        Options.Default_Cycle :=
                          Natural'Value (Project.Get_Parameter);
                     exception
                        when Constraint_Error =>
                           raise GNAT.Command_Line.Invalid_Parameter;
                     end;

                  --  Wrong option
                  else
                     raise GNAT.Command_Line.Invalid_Parameter;
                  end if;
               end;

            --  Warnings
            when 'W' =>
               declare
                  Parameter : constant String := Project.Get_Parameter;
               begin
                  for Index in Parameter'Range loop
                     case Parameter (Index) is
                        --  -Wa
                        when 'a' =>
                           Options.Warnings := (others => True);

                        --  -Wc
                        when 'c' =>
                           Options.Warnings (Options.Cycle) := True;

                        --  -Wu
                        when 'u' =>
                           Options.Warnings (Options.Unbounded) := True;

                        --  -We
                        when 'e' =>
                           Options.Warnings (Options.External) := True;

                        --  -Wi
                        when 'i' =>
                           Options.Warnings (Options.Indirect) := True;

                        --  Wrong warning option
                        when others =>
                           raise GNAT.Command_Line.Invalid_Parameter;
                     end case;
                  end loop;
               end;

            when 'o' =>
               --  Objcopy command
               if Project.Get_Switch = "oc" then
                  GNAT.Strings.Free (Options.Objcopy_Cmd);

                  Options.Objcopy_Cmd := new String'(Project.Get_Parameter);

               --  Ordering
               else
                  declare
                     Parameter : constant String := Project.Get_Parameter;
                  begin
                     --  -oa
                     if Parameter = "a" then
                        Options.Order := Options.Alphabetical;

                     --  -os
                     elsif Parameter = "s" then
                        Options.Order := Options.Stack_Usage;

                     --  Wrong option
                     else
                        raise GNAT.Command_Line.Invalid_Parameter;
                     end if;
                  end;
               end if;

            when 'a' =>
               declare
                  Switch : constant String := Project.Get_Switch;
               begin
                  --  Consider all subprograms as potential entry points
                  if Switch = "a" then
                     Options.Explore_All := True;

                  --  Directory containing the .ci files
                  elsif Switch = "aO" then
                     declare
                        Directory : constant String := Project.Get_Parameter;
                     begin
                        Append_Files_From_Directory (Input_Files, Directory);
                     end;

                  --  Wrong option
                  else
                     raise GNAT.Command_Line.Invalid_Switch;
                  end if;
               end;

            --  Default stack requirements for unknown (external) calls
            when 'u' =>
               declare
               begin
                  Options.Default_Unknown :=
                    Natural'Value (Project.Get_Parameter);
               exception
                  when Constraint_Error =>
                     raise GNAT.Command_Line.Invalid_Parameter;
               end;

            --  Default stack requirements for unbounded (dynamic) calls
            when 'd' =>
               declare
               begin
                  Options.Default_Unbounded :=
                    Natural'Value (Project.Get_Parameter);
               exception
                  when Constraint_Error =>
                     raise GNAT.Command_Line.Invalid_Parameter;
               end;

            when 'p' =>
               declare
                  Switch : constant String := Project.Get_Switch;
               begin
                  --  Display call chain paths
                  if Switch = "p" then
                     Options.Display_Call_Chains := True;

                  --  Progress information
                  elsif Switch = "pi" then
                     Options.Progress_Information := True;

                  --  Wrong option
                  else
                     raise GNAT.Command_Line.Invalid_Switch;
                  end if;
               end;

            --  Do not display progress messages.
            when 'q' =>
               Options.Progress_Information := False;

            --  Do not display any console message (except for progress
            --  information).
            when 'Q' =>
               Options.Very_Quiet := True;

            when 'n' =>
               --  Do not display call chain (paths) for the entry points
               if Project.Get_Switch = "np" then
                  Options.Display_Call_Chains := False;

               --  Wrong option
               else
                  raise GNAT.Command_Line.Invalid_Switch;
               end if;

            --  List of entry points
            when 'e' =>
               GNAT.Strings.Free (Options.List_Of_Entry_Points);

               --  This dynamically allocated String is later destroyed after
               --  being used.

               Options.List_Of_Entry_Points :=
                 new String'(Project.Get_Parameter);

            --  Pattern for subprograms to be considered entry points
            when 'r' =>
               GNAT.Strings.Free (Options.Entry_Point_Pattern);

               --  This dynamically allocated String is later destroyed after
               --  being used.

               Options.Entry_Point_Pattern :=
                 new String'(Project.Get_Parameter);

            when 'f' =>
               declare
                  Switch : constant String := Project.Get_Switch;
               begin
                  --  Output graph file
                  if Switch = "f" then
                     GNAT.Strings.Free (Options.Output_VCG);

                     --  This dynamically allocated String is later destroyed
                     --  after being used.

                     Options.Output_VCG := new String'(Project.Get_Parameter);

                  --  File containing a list of .ci files
                  elsif Switch = "files" then
                     Get_Stack_Usage_Files (Project.Get_Parameter);

                  --  Wrong option
                  else
                     raise GNAT.Command_Line.Invalid_Switch;
                  end if;
               end;

            --  XML output
            when 'x' =>
               Options.Generate_XML_Output := True;

            --  Section name
            when 's' =>
               GNAT.Strings.Free (Options.Section_Name);

               Options.Section_Name := new String'(Project.Get_Parameter);

            --  Resolution of indirect and dispatching calls
            when 't' =>
               declare
                  Parameter : constant String := Project.Get_Parameter;

                  use type Options.Target_Resolution_Options;

               begin
                  for Index in Parameter'Range loop
                     case Parameter (Index) is
                        --  -ta
                        when 'a' =>
                           Options.Target_Resolution := Options.Both;

                        --  -ti
                        when 'i' =>
                           --  Add the indirect calls

                           if Options.Target_Resolution = Options.None or else
                             Options.Target_Resolution = Options.Indirect_Calls
                           then
                              Options.Target_Resolution :=
                                Options.Indirect_Calls;
                           else
                              Options.Target_Resolution := Options.Both;
                           end if;

                        --  -td
                        when 'd' =>
                           --  Add the dispatching calls

                           if Options.Target_Resolution = Options.None or else
                             Options.Target_Resolution =
                               Options.Dispatching_Calls
                           then
                              Options.Target_Resolution :=
                                Options.Dispatching_Calls;
                           else
                              Options.Target_Resolution := Options.Both;
                           end if;

                        --  Wrong resolution option
                        when others =>
                           raise GNAT.Command_Line.Invalid_Parameter;
                     end case;
                  end loop;
               end;

            --  Ignore project related switches (-P <prj>, -X<name>=<val>)
            --  because they have already been treated.
            when 'X' | 'P' =>
               null;

            when others =>
               raise GNAT.Command_Line.Invalid_Switch;
            end case;
         end loop;

         --  Get list of input files

         loop
            declare
               Input_File_Name : constant GNAT.Strings.String_Access :=
                 new String'(GNAT.Command_Line.Get_Argument (True));

            begin
               exit when Input_File_Name'Length = 0;

               --  Skip the file if it does not exist

               if not Ada.Directories.Exists (Input_File_Name.all) then
                  --  File does not exist

                  raise Ada.Text_IO.Name_Error with
                    "File """ & Input_File_Name.all & """ not found";

               elsif Is_Stack_Usage_Information_File (Input_File_Name) then
                  --  This dynamically allocated String will be later
                  --  destroyed after being used.

                  List_Of_Files.Append (Input_Files, Input_File_Name);

               else
                  --  Try to extract the .ci information from an object or
                  --  executable.

                  declare
                     Tmp_Name : constant GNAT.Strings.String_Access :=
                       new String'(Input_File_Name.all & ".ci");

                     Objcopy : constant GNAT.Strings.String_Access :=
                       System.OS_Lib.Locate_Exec_On_Path
                         (Options.Objcopy_Cmd.all);

                     Args : constant System.OS_Lib.Argument_List :=
                       (new String'("-j"), Options.Section_Name,
                        new String'("--set-section-flags"),
                        new String'(Options.Section_Name.all & "=load"),
                        new String'("-O"), new String'("binary"),
                        Input_File_Name, Tmp_Name);

                     Success : Boolean;

                     use type Ada.Directories.File_Size;
                  begin
                     --  Extract the .ci file from the object to a temporary
                     --  file whose name is the name of the object file plus
                     --  a .ci located in the working directory.

                     if Objcopy = null then
                        raise Parser_Error with
                          Options.Objcopy_Cmd.all & " executable not found";
                     else
                        System.OS_Lib.Spawn (Objcopy.all, Args, Success);

                        if Success and then
                          Ada.Directories.Exists (Tmp_Name.all) and then
                          Ada.Directories.Size (Tmp_Name.all) > 0
                        then
                           List_Of_Files.Append (Input_Tmp_Files, Tmp_Name);
                        else
                           raise Parser_Error with
                             "Problem extracting .ci from " &
                             Input_File_Name.all;
                        end if;
                     end if;
                  end;
               end if;
            end;
         end loop;

         if List_Of_Files.Is_Empty (Input_Files) and then
           List_Of_Files.Is_Empty (Input_Tmp_Files)
         then
            Ada.Text_IO.Put_Line
              ("Specify at least one .ci (callgraph information) or .o file");

            Print_Usage_And_Exit;
         end if;

         --  Add .ci files coming from the object directories belonging to the
         --  run-time library

         Predef_Obj_Dirs :=
           new GNATCOLL.VFS.File_Array'(Project.Env.Predefined_Object_Path);

         for OD of Predef_Obj_Dirs.all loop
            Append_Files_From_Directory
              (Input_Files, OD.Display_Full_Name);
         end loop;

         GNATCOLL.VFS.Unchecked_Free (Predef_Obj_Dirs);

      --  Exception handling for the part in charge of parsing the command
      --  line.
      exception
         when GNAT.Command_Line.Invalid_Switch =>
            Ada.Text_IO.Put_Line
              ("unrecognized option '" & Project.Get_Switch & "'");

            Print_Usage_And_Exit;

         when GNAT.Command_Line.Invalid_Parameter =>
            Ada.Text_IO.Put_Line
              ("missing or wrong parameter for '-" &
               Project.Get_Switch & "'");

            Print_Usage_And_Exit;

         when E : others =>
            Ada.Text_IO.Put_Line (Ada.Exceptions.Exception_Message (E));
            GNAT.OS_Lib.OS_Exit (1);
      end;

      if Options.Verbose and then not Options.Very_Quiet then
         Print_Version;
      end if;

      --  Once we know the list of input files we can parse the information
      --  which is within these files.

      if Options.Progress_Information then
         --  Count Entities
         List_Of_Files.Iterate (Input_Files, Count_Entities_CI'Access);
         List_Of_Files.Iterate (Input_Tmp_Files, Count_Entities_ELF'Access);

         --  Approximate the number of subprograms and calls to analyze by
         --  the number of subprograms and calls to parse. This is not
         --  exact because there may be unreachable paths, for example.

         Global_Data.Expected_Entities (Global_Data.Analyze_Subprogram) :=
           Global_Data.Expected_Entities (Global_Data.Parse_Subprogram);

         Global_Data.Expected_Entities (Global_Data.Analyze_Call) :=
           Global_Data.Expected_Entities (Global_Data.Parse_Call);
      end if;

      --  Process the .ci files
      List_Of_Files.Iterate (Input_Files, Parse_Input_File'Access);

      --  Process the .ci files extracted from object files
      List_Of_Files.Iterate (Input_Tmp_Files, Parse_Input_File'Access);

      if Options.Progress_Information then
         --  Make sure that parsing is displayed as finished

         Global_Data.Expected_Entities (Global_Data.Parse_Subprogram) :=
           Global_Data.Entities_Processed (Global_Data.Parse_Subprogram);

         --  -1 because it will be later increased by 1

         Global_Data.Entities_Processed (Global_Data.Parse_Subprogram) :=
           Global_Data.Entities_Processed (Global_Data.Parse_Subprogram) - 1;

         Global_Data.Expected_Entities (Global_Data.Parse_Call) :=
           Global_Data.Entities_Processed (Global_Data.Parse_Call);

         --  Force printing

         Display.Increase_Count (Global_Data.Parse_Subprogram);
      end if;

      --  We do not need this list any more, so we destroy the list of
      --  .ci files. For the list of temporary .ci files (those coming
      --  from .o files) we delete the files unless the option -k was used
      --  to keep temporary files.

      List_Of_Files.Iterate (Input_Files, Deallocate_File_Names'Access);

      List_Of_Files.Clear (Input_Files);

      --  Remove temporary files if needed

      if Options.Remove_Temporary_Files then
         List_Of_Files.Iterate (Input_Tmp_Files, Remove_Files'Access);
      end if;

      List_Of_Files.Iterate (Input_Tmp_Files, Deallocate_File_Names'Access);

      List_Of_Files.Clear (Input_Tmp_Files);

      --  Get the list of subprograms to be considered as entry points

      --  Add the entry points that have been specified in the command line

      if Options.List_Of_Entry_Points /= null then
         --  Create a list of strings containing the separated entry points
         --  that we are looking for.

         --  Get the number of these entries to create an array to store
         --  them separately.

         Entries := 1;

         for Index in Options.List_Of_Entry_Points'Range loop
            if Options.List_Of_Entry_Points (Index) = ',' then
               Entries := Entries + 1;
            end if;
         end loop;

         declare
            Entry_List : array (1 .. Entries) of GNAT.Strings.String_Access;

            Starting_Point : Integer;
            --  Temporal pointer to the beginning of an entry point in the
            --  string which appears in the command line.

            Entry_Number : Integer;
            --  Number of entry which is being handled

            procedure Add_Entry_Point
              (Position : Static_Stack_Analysis.Node_Id);
            --  Add the node to the list of entry points to analyze if its
            --  symbol name corresponds to one of those specified in
            --  Options.List_Of_Entry_Points.

            procedure Add_Entry_Point
              (Position : Static_Stack_Analysis.Node_Id)
            is
            begin
               --  If the referenced node describes a subprogram containing
               --  the pattern defined in Options.List_Of_Entry_Points we add
               --  this subprogram to the list of potential entry points.

               for Index in Entry_List'Range loop
                  if Entry_List (Index) /= null and then
                    Pattern_In_Node (Entry_List (Index).all, Position)
                  then
                     --  If we have found the entry point we add it to the
                     --  list, remove the entry which we are looking for
                     --  (because it has already been found), and exit.

                     GNAT.Strings.Free (Entry_List (Index));
                     Global_Data.Entry_Points.Append (Position);
                     exit;
                  end if;
               end loop;
            end Add_Entry_Point;

         begin
            --  Split the list of entry points

            Starting_Point := Options.List_Of_Entry_Points'First;
            Entry_Number := Entry_List'First;

            for Index in Options.List_Of_Entry_Points'Range loop
               --  Add a "^ ... $" to the regexp to look for the symbol
               --  name, and not for a part of it.

               if Options.List_Of_Entry_Points (Index) = ',' then
                  Entry_List (Entry_Number) :=
                    new String'
                      ("^" &
                       Options.List_Of_Entry_Points
                         (Starting_Point .. Index - 1) &
                       "$");
                  Entry_Number := Entry_Number + 1;
                  Starting_Point := Index + 1;

               elsif Index = Options.List_Of_Entry_Points'Last then
                  Entry_List (Entry_Number) :=
                    new String'
                      ("^" &
                       Options.List_Of_Entry_Points (Starting_Point .. Index) &
                       "$");
               end if;
            end loop;

            pragma Assert (Entry_Number = Entry_List'Last);

            --  Look for the entry points

            Static_Stack_Analysis.List_Of_Nodes.Iterate
              (Global_Data.List_Of_Subprograms, Add_Entry_Point'Access);

            --  Verify whether all entry points were found. Destroy the list
            --  of String once used

            for Index in Entry_List'Range loop
               if Entry_List (Index) /= null then
                  Ada.Text_IO.Put_Line
                    ("Could not find the entry point " &
                     Entry_List (Index)(Entry_List (Index)'First + 1 ..
                                        Entry_List (Index)'Last - 1));
                  GNAT.Strings.Free (Entry_List (Index));
               end if;
            end loop;

            --  Verify that at least one entry point matching the pattern has
            --  been found.

            if Global_Data.Entry_Points.Is_Empty then
               Ada.Text_IO.Put_Line
                 ("Could not find any entry point from the list " &
                  Options.List_Of_Entry_Points.all);

               raise Parser_Error with "No entry point found";
            end if;
         end;

         --  Destroy the String once used

         GNAT.Strings.Free (Options.List_Of_Entry_Points);

      --  Add the entry points matching the pattern
      elsif Options.Entry_Point_Pattern /= null then
         Static_Stack_Analysis.List_Of_Nodes.Iterate
           (Global_Data.List_Of_Subprograms, Add_Pattern_Entry'Access);

         --  Verify that at least one entry point matching the pattern has
         --  been found.

         if Global_Data.Entry_Points.Is_Empty then
            Ada.Text_IO.Put_Line
              ("Could not find any entry point matching the pattern " &
               Options.Entry_Point_Pattern.all);

            raise Parser_Error with "No entry point found";
         end if;

         --  Destroy the String once used

         GNAT.Strings.Free (Options.Entry_Point_Pattern);

      --  Use the mechanism to automatically detect entry points
      else
         Options.Automatic_Entry_Point_Detection := True;
      end if;

      --  Get the task wrapper information in case Ada tasking is used and
      --  the information is available.

      if Global_Data.Ada_Tasking_Used then
         Static_Stack_Analysis.List_Of_Nodes.Iterate
           (Global_Data.List_Of_Subprograms, Get_Task_Wrapper'Access);
      end if;
   end Parse_Arguments;

   ---------------------------
   -- Parse_Dynamic_Objects --
   ---------------------------

   procedure Parse_Dynamic_Objects
     (Input           : String;
      Dynamic_Objects : out Static_Stack_Analysis.List_Of_Locations.Set)
   is
      Matches : GNAT.Regpat.Match_Array (0 .. 10);

      Tmp_Location : Static_Stack_Analysis.Location;

      Ignore   : Static_Stack_Analysis.List_Of_Locations.Cursor;
      Inserted : Boolean;

   begin
      GNAT.Regpat.Match (Data_Location_Regexp, Input, Matches);

      if Matches (0) /= GNAT.Regpat.No_Match then
         --  This dynamically created object will be later destroyed if it
         --  is not used (inserted in the list).

         Tmp_Location.Demangled :=
           new String'(Input (Matches (1).First .. Matches (1).Last));

         if Matches (3) /= GNAT.Regpat.No_Match or else
           Matches (4) /= GNAT.Regpat.No_Match
         then
            --  Matches <no location>, <built-in> or <internal>

            Tmp_Location := Static_Stack_Analysis.Null_Location;

         else
            pragma Assert
              (Matches (5) /= GNAT.Regpat.No_Match and then
               Matches (6) /= GNAT.Regpat.No_Match);

            Tmp_Location.File :=
              new String'(Input (Matches (6).First .. Matches (6).Last));

            pragma Assert (Matches (8) /= GNAT.Regpat.No_Match);

            Tmp_Location.Line_Number :=
              Integer'Value (Input (Matches (8).First .. Matches (8).Last));

            if Matches (9) /= GNAT.Regpat.No_Match then
               --  'First + 1 to skip the ":"

               Tmp_Location.Column_Number :=
                 Integer'Value
                   (Input (Matches (9).First + 1 .. Matches (9).Last));
            else
               Tmp_Location.Column_Number := 0;
            end if;
         end if;

         --  Parse additional locations, if any

         if Matches (10) /= GNAT.Regpat.No_Match then
            Parse_Dynamic_Objects
              (Input (Matches (10).First .. Matches (10).Last),
               Dynamic_Objects);
         end if;

         --  Include the parsed location if it is not already in the list

         if Tmp_Location /= Static_Stack_Analysis.Null_Location then
            Dynamic_Objects.Insert (Tmp_Location, Ignore, Inserted);

            --  Destroy the String that was previously allocated if it is
            --  no longer needed.

            if not Inserted then
               GNAT.Strings.Free
                 (GNAT.Strings.String_Access (Tmp_Location.Demangled));

               GNAT.Strings.Free
                 (GNAT.Strings.String_Access (Tmp_Location.File));
            end if;
         end if;

      else
         raise Parser_Error;
      end if;
   end Parse_Dynamic_Objects;

   ----------------------
   -- Parse_Input_Line --
   ----------------------

   procedure Parse_Input_Line (Input : String) is
   begin
      --  Parsing subprogram
      if GNAT.Regpat.Match (Node_Regexp, Input) then
         Parse_Node (Input);

      --  Parsing call
      elsif GNAT.Regpat.Match (Edge_Regexp, Input) then
         Parse_Edge (Input);

      --  Parsing class representation
      elsif GNAT.Regpat.Match (Class_Regexp, Input) then
         Parse_Class (Input);

      --  Get the Ada file name associated to the file being parsed
      elsif GNAT.Regpat.Match (Header_Regexp, Input) then
         Parse_File_Name (Input);

      --  Skip informative lines
      elsif GNAT.Regpat.Match (Allowed_Lines_Regexp, Input) then
         null;

      --  Skip file termination lines that may appear on Windows
      elsif Input'Length = 1 and then Input (Input'First) = ASCII.SUB then
         null;

      --  Error otherwise
      else
         raise Parser_Error;
      end if;
   end Parse_Input_Line;

   ----------------
   -- Parse_Node --
   ----------------

   procedure Parse_Node (Input : String) is
      use Static_Stack_Analysis;

      Symbol_Name     : Name := null;
      Demangled_Name  : Name := null;
      Alias           : Name := null;

      Stack_Info      : Stack_Usage_Info := Unknown_Stack_Usage;
      Locally_Defined : Boolean := False;

      Node_Ptr        : Node_Class_Access := null;

      Matches         : GNAT.Regpat.Match_Array (0 .. 5);

      Locations_Set   : List_Of_Locations.Set := List_Of_Locations.Empty_Set;

      Dynamic_Objects : List_Of_Locations.Set := List_Of_Locations.Empty_Set;

   begin
      --  The pattern of the input line is:
      --  node: { title: "symbol_name" label: "LABEL"
      --          [ alias: "alias"][ shape : ellipse] }
      --
      --  The symbol_name is the one that is used for distinguising among the
      --  different nodes. It may include the file name to be able to
      --  distinguish static functions.
      --
      --  The format of the String under LABEL is:
      --  "[demangled_name][\nLOC[,LOC]][\nN bytes (static|dynamic[,bounded])]
      --   [M dynamic objects[\n DLOC[\n DLOC]]]"
      --  where:
      --  LOC = file:line:column
      --  N = Natural representing the number of bytes
      --  M = Natural representing the number of dynamic objects defined in
      --      the subprogram
      --  DLOC = object file:line
      --
      --  The alias information indicates the actual symbol name when the
      --  current node is an alias for another symbol.
      --
      --  The shape : ellipse indicates that the node is used but not defined,
      --  which means that it is an unresolved call.
      --
      --  The fields that are mandatory are title and label.

      --  First, we want to get the three different fields (title, label, and
      --  shape) so we can process them later.

      if Options.Progress_Information then
         Display.Increase_Count (Global_Data.Parse_Subprogram);
      end if;

      GNAT.Regpat.Match (Node_Regexp, Input, Matches);

      if Matches (0) = GNAT.Regpat.No_Match then
         raise Parser_Error;

      else
         --  Get the unique symbol name corresponding to the subprogram

         Symbol_Name := new String'
           (Get_Unique_Symbol_Name
              (Input (Matches (1).First .. Matches (1).Last)));

         --  If this is an indirect call then no more information can be
         --  extracted.

         if Symbol_Name.all /= Indirect_Call.all then

            --  Get information from the label

            if Matches (2) /= GNAT.Regpat.No_Match then
               Parse_Node_Label
                 (Input (Matches (2).First .. Matches (2).Last),
                  Demangled_Name,
                  Locations_Set,
                  Stack_Info,
                  Dynamic_Objects);
            else
               Demangled_Name := null;
               Locations_Set := List_Of_Locations.Empty_Set;
               Stack_Info := Unknown_Stack_Usage;
               Stack_Info.Unknown_Usage :=
                 Static_Stack_Analysis.Frame_Size (Options.Default_Unknown);
               Dynamic_Objects := List_Of_Locations.Empty_Set;
            end if;

            --  Get alias information

            if Matches (3) /= GNAT.Regpat.No_Match then
               pragma Assert (Matches (4) /= GNAT.Regpat.No_Match);

               Alias :=
                 new String'(Input (Matches (4).First .. Matches (4).Last));
            end if;

            --  Get information from the shape

            if Matches (5) /= GNAT.Regpat.No_Match then
               Parse_Shape
                 (Input (Matches (5).First .. Matches (5).Last),
                  Locally_Defined);

            else
               --  Nodes are also locally defined if they define their stack
               --  usage.

               Locally_Defined :=
                 Stack_Info.Frame_Type /= Static_Stack_Analysis.Unknown;
            end if;
         end if;
      end if;

      --  Check whether this is an application using Ada tasking

      if not Global_Data.Ada_Tasking_Used and then
        (Symbol_Name.all = Create_Task or else
           Symbol_Name.all = Create_Ravenscar_Task)
      then
         Global_Data.Ada_Tasking_Used := True;
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
            --  Deallocated objects that are no longer needed.

            GNAT.Strings.Free (GNAT.Strings.String_Access (Symbol_Name));
            GNAT.Strings.Free (GNAT.Strings.String_Access (Demangled_Name));

         --  Unresolved
         elsif not Locally_Defined then
            --  If the subprogram is not yet in the list then we insert it.
            --  Otherwise, we simply add the information that may be missing,
            --  which is the alias information.

            if not List_Of_Nodes.Has_Element (Found_Id) then
               --  Insert new unresolved node.

               --  This dynamically created object cannot be deallocated
               --  because it is inserted in a list that may be used at any
               --  time during the analysis.

               Node_Ptr := new Unresolved_Node'
                 (Ada_File_Name           => Ada_File_Name,
                  Target_Calls            => List_Of_Edges.Empty_Vector,
                  Accumulated_Stack_Usage => Unknown_Stack_Usage,
                  Location_List           => Locations_Set,
                  Subprogram              => Symbol_Name,
                  Demangled               =>
                    new String'
                      (Demangle.Decode (Symbol_Name.all, Ada_File_Name)),
                  Alias                   => Alias,
                  Under_Analysis          => False,
                  Analysis_Finished       => False,
                  Is_Called               => False,
                  Is_Reachable            => False,
                  Cycles                  => List_Of_Cycles.Empty_Set);

               --  Insert new subprogram descriptor

               List_Of_Nodes.Insert
                 (Global_Data.List_Of_Subprograms, Node_Ptr);

            --  The only additional information may be the alias, which can
            --  only happen for unresolved nodes.
            elsif Alias /= null then
               --  Get the node that we previously found

               Node_Ptr := List_Of_Nodes.Element (Found_Id);

               --  The alias information must either be missing or equal to
               --  the one we are inserting.

               pragma Assert
                 (Node_Ptr.all in Unresolved_Node'Class and then
                    (Unresolved_Node (Node_Ptr.all).Alias = null or else
                     Unresolved_Node (Node_Ptr.all).Alias.all = Alias.all));

               --  Add the missing alias information

               Unresolved_Node (Node_Ptr.all).Alias := Alias;
            end if;

         --  Explicit node
         else
            --  If the subprogram is not yet in the list then we insert it.
            --  Otherwise, we upgrade the information that we have about the
            --  subprogram.

            if not List_Of_Nodes.Has_Element (Found_Id) then
               --  Insert new explicit node

               --  This dynamically created object cannot be deallocated
               --  because it is inserted in a list that may be used at any
               --  time during the analysis.

               Node_Ptr := new Explicit_Node'
                 (Ada_File_Name           => Ada_File_Name,
                  Target_Calls            => List_Of_Edges.Empty_Vector,
                  Accumulated_Stack_Usage => Unknown_Stack_Usage,
                  Location_List           => Locations_Set,
                  Subprogram              => Symbol_Name,
                  Demangled               =>
                    new String'
                      (Demangle.Decode (Symbol_Name.all, Ada_File_Name)),
                  Dynamic_Objects         => Dynamic_Objects,
                  Stack_Info              => Stack_Info,
                  Under_Analysis          => False,
                  Analysis_Finished       => False,
                  Is_Called               => False,
                  Is_Reachable            => False,
                  Cycles                  => List_Of_Cycles.Empty_Set);

               --  Insert new subprogram descriptor

               List_Of_Nodes.Insert
                 (Global_Data.List_Of_Subprograms, Node_Ptr);

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

                  --  Merge the list of dynamic objects

                  Explicit_Node (Found_Node.all).Dynamic_Objects.Union
                    (Dynamic_Objects);

                  --  Check information about stack usage and update if
                  --  necessary.

                  Explicit_Node (Found_Node.all).Update_Stack_Usage
                    (Stack_Info);

               else
                  --  The node needs to be changed to an explicit node. We
                  --  will include the information that we already had.

                  Node_Ptr := new Explicit_Node'
                    (Ada_File_Name           => Ada_File_Name,
                     Target_Calls            => Found_Node.Target_Calls,
                     Accumulated_Stack_Usage => Unknown_Stack_Usage,
                     Location_List           => Locations_Set,
                     Subprogram              => Symbol_Name,
                     Demangled               =>
                        new String'
                          (Demangle.Decode (Symbol_Name.all, Ada_File_Name)),
                     Dynamic_Objects         => Dynamic_Objects,
                     Stack_Info              => Stack_Info,
                     Under_Analysis          => False,
                     Analysis_Finished       => False,
                     Is_Called               => Found_Node.Is_Called,
                     Is_Reachable            => False,
                     Cycles                  => List_Of_Cycles.Empty_Set);

                  --  Merge the location list

                  Explicit_Node (Node_Ptr.all).Location_List.Union
                    (Get_Location_List (Found_Node.all));

                  --  Merge the list of dynamic objects

                  Explicit_Node (Node_Ptr.all).Dynamic_Objects.Union
                    (Dynamic_Objects);

                  List_Of_Nodes.Replace_Element
                       (Global_Data.List_Of_Subprograms, Found_Id, Node_Ptr);

                  --  Free the old node ???

               end if;
            end if;
         end if;
      end;
   end Parse_Node;

   ----------------------------
   -- Get_Unique_Symbol_Name --
   ----------------------------

   function Get_Unique_Symbol_Name (Input : String) return String is
      Lower_Bound, Upper_Bound : Natural;

   begin
      if Input'Length /= 0 then
         --  This dynamically created object cannot be deallocated because
         --  it is inserted in a list that may be used at any time during
         --  the analysis.

         --  For Ada code we remove the file name prefix and .NNN suffix that
         --  may appear in the form: file.adb:package__proc.1560

         if Demangle.Is_Ada (Ada_File_Name) then
            declare
               Matches : GNAT.Regpat.Match_Array (0 .. 3);

            begin
               --  Remove prefix and suffix if we find it

               GNAT.Regpat.Match ("^(.*:)?([^:]+)(\.\d+)?$", Input, Matches);

               pragma Assert
                 (Matches (0) /= GNAT.Regpat.No_Match and then
                  Matches (2) /= GNAT.Regpat.No_Match);

               Lower_Bound := Matches (2).First;
               Upper_Bound := Matches (2).Last;
            end;

         --  For C/C++ we do not remove the prefix nor the suffix because
         --  they are meaningful in that case.
         else
            Lower_Bound := Input'First;
            Upper_Bound := Input'Last;
         end if;

         return Input (Lower_Bound .. Upper_Bound);
      else
         raise Parser_Error;
      end if;
   end Get_Unique_Symbol_Name;

   ----------------------
   -- Parse_Node_Label --
   ----------------------

   procedure Parse_Node_Label
     (Input           : String;
      Demangled       : out Static_Stack_Analysis.Name;
      Locations       : out Static_Stack_Analysis.List_Of_Locations.Set;
      Stack           : out Static_Stack_Analysis.Stack_Usage_Info;
      Dynamic_Objects : out Static_Stack_Analysis.List_Of_Locations.Set)
   is
      Matches : GNAT.Regpat.Match_Array (0 .. 17);

   begin
      GNAT.Regpat.Match (Node_Label_Regexp, Input, Matches);

      if Matches (0) = GNAT.Regpat.No_Match then
         --  The label cannot be parsed. This is not a major issue, it simply
         --  means that we cannot extract the demangled name, source location
         --  and stack usage information for this subprogram.

         Demangled := null;

         Locations := Static_Stack_Analysis.List_Of_Locations.Empty_Set;

         Stack := Static_Stack_Analysis.Unknown_Stack_Usage;
         Stack.Unknown_Usage :=
           Static_Stack_Analysis.Frame_Size (Options.Default_Unknown);

         Dynamic_Objects :=
           Static_Stack_Analysis.List_Of_Locations.Empty_Set;

         --  Emit a warning if required

         if Options.Debug then
            Ada.Text_IO.Put_Line ("Could not parse the label: " & Input);
         end if;

      else
         --  The following are optional fields

         --  Demangled name

         if Matches (1) /= GNAT.Regpat.No_Match and then
           Matches (2) /= GNAT.Regpat.No_Match
         then
            --  This dynamically allocated String is later destroyed if it is
            --  not used (inserted in the list).

            Demangled :=
              new String'(Input (Matches (2).First .. Matches (2).Last));
         else
            Demangled := null;
         end if;

         --  Subprogram location

         if Matches (3) /= GNAT.Regpat.No_Match and then
           Matches (4) /= GNAT.Regpat.No_Match
         then
            Parse_Node_Locations
              (Input (Matches (4).First .. Matches (4).Last),
               Demangled,
               Locations);
         else
            Locations := Static_Stack_Analysis.List_Of_Locations.Empty_Set;
            GNAT.Strings.Free (GNAT.Strings.String_Access (Demangled));
         end if;

         --  Stack usage

         if Matches (13) /= GNAT.Regpat.No_Match then
            Parse_Stack_Usage
              (Input (Matches (13).First .. Matches (13).Last), Stack);
         else
            Stack := Static_Stack_Analysis.Unknown_Stack_Usage;
            Stack.Unknown_Usage :=
              Static_Stack_Analysis.Frame_Size (Options.Default_Unknown);
         end if;

         --  Dynamic objects

         if Matches (17) /= GNAT.Regpat.No_Match then
            Parse_Dynamic_Objects
              (Input (Matches (17).First .. Matches (17).Last),
               Dynamic_Objects);
         else
            Dynamic_Objects :=
              Static_Stack_Analysis.List_Of_Locations.Empty_Set;
         end if;
      end if;
   end Parse_Node_Label;

   -------------------------
   -- Parse_Node_Location --
   -------------------------

   procedure Parse_Node_Locations
     (Input     : String;
      Demangled : Static_Stack_Analysis.Name;
      Locations : out Static_Stack_Analysis.List_Of_Locations.Set)
   is
      Matches      : GNAT.Regpat.Match_Array (0 .. 9);

      Tmp_Location : Static_Stack_Analysis.Location;

      Ignore       : Static_Stack_Analysis.List_Of_Locations.Cursor;
      New_Location : Boolean := False;

      use type Ada.Text_IO.Positive_Count;
   begin
      GNAT.Regpat.Match (Subprogram_Location_Regexp, Input, Matches);

      if Matches (0) /= GNAT.Regpat.No_Match then

         if Matches (2) = GNAT.Regpat.No_Match and then
           Matches (3) = GNAT.Regpat.No_Match
         then
            --  It matches neither <no location> nor <built-in> nor <internal>

            --  This dynamically created object will be later destroyed if it
            --  is not used (inserted in the list).

            pragma Assert
              (Matches (4) /= GNAT.Regpat.No_Match and then
               Matches (5) /= GNAT.Regpat.No_Match);

            Tmp_Location.File :=
              new String'
                (Input (Matches (5).First .. Matches (5).Last));

            Tmp_Location.Demangled := Demangled;

            pragma Assert (Matches (7) /= GNAT.Regpat.No_Match);

            Tmp_Location.Line_Number :=
              Integer'Value (Input (Matches (7).First .. Matches (7).Last));

            --  The column number is not always present

            if Matches (8) /= GNAT.Regpat.No_Match then
               --  'First + 1 to skip the ":"

               Tmp_Location.Column_Number :=
                 Integer'Value
                   (Input (Matches (8).First + 1 .. Matches (8).Last));
            else
               Tmp_Location.Column_Number := 0;
            end if;

            --  Parse additional locations, if any

            if Matches (9) /= GNAT.Regpat.No_Match then
               Parse_Node_Locations
                 (Input (Matches (9).First .. Matches (9).Last),
                  Demangled,
                  Locations);
            end if;

            --  Include the parsed location if it is not already in the list

            Locations.Insert (Tmp_Location, Ignore, New_Location);

            --  Destroy the String that was previously allocated if it is no
            --  longer needed.

            if not New_Location then
               GNAT.Strings.Free
                 (GNAT.Strings.String_Access (Tmp_Location.File));
            end if;
         end if;

      else
         --  The file location is malformed. This information is not
         --  required for computing stack usage (it is only helpful to
         --  present the results).

         Locations := Static_Stack_Analysis.List_Of_Locations.Empty_Set;

         if Options.Debug then
            Ada.Text_IO.Put_Line
              (Ada.Directories.Simple_Name
                 (Ada.Text_IO.Name (Descriptor)) & ":" &
               Ada.Strings.Fixed.Trim
                 (Ada.Text_IO.Positive_Count'Image
                    (Ada.Text_IO.Line (Descriptor) - 1),
                  Ada.Strings.Both) &
               ": Could not parse the label");
         end if;
      end if;
   end Parse_Node_Locations;

   -------------------------------
   -- Parse_Front_End_Locations --
   -------------------------------

   procedure Parse_Front_End_Locations
     (Input     : String;
      Demangled : Static_Stack_Analysis.Name;
      Locations : out Static_Stack_Analysis.List_Of_Locations.Set)
   is
      Matches      : GNAT.Regpat.Match_Array (0 .. 9);

      Tmp_Location : Static_Stack_Analysis.Location;

      Ignore       : Static_Stack_Analysis.List_Of_Locations.Cursor;
      New_Location : Boolean := False;

      use type Ada.Text_IO.Positive_Count;

   begin
      GNAT.Regpat.Match (Front_End_Location_Regexp, Input, Matches);

      if Matches (0) /= GNAT.Regpat.No_Match then

         if Matches (2) = GNAT.Regpat.No_Match and then
           Matches (3) = GNAT.Regpat.No_Match
         then
            --  It matches neither <no location> nor <built-in>

            --  This dynamically created object will be later destroyed if it
            --  is not used (inserted in the list).

            pragma Assert
              (Matches (4) /= GNAT.Regpat.No_Match and then
               Matches (5) /= GNAT.Regpat.No_Match);

            Tmp_Location.File :=
              new String'
                (Input (Matches (5).First .. Matches (5).Last));

            Tmp_Location.Demangled := Demangled;

            pragma Assert (Matches (7) /= GNAT.Regpat.No_Match);

            Tmp_Location.Line_Number :=
              Integer'Value (Input (Matches (7).First .. Matches (7).Last));

                        --  The column number is not always present

            if Matches (8) /= GNAT.Regpat.No_Match then
               --  'First + 1 to skip the ":"

               Tmp_Location.Column_Number :=
                 Integer'Value
                   (Input (Matches (8).First + 1 .. Matches (8).Last));
            else
               Tmp_Location.Column_Number := 0;
            end if;

            --  Parse additional locations, if any

            if Matches (9) /= GNAT.Regpat.No_Match then
               --  The match is for " [XXX]", so we use 'First + 2 to skip the
               --  " [" and 'Last - 1 to skip the "]".

               Parse_Front_End_Locations
                 (Input (Matches (9).First + 2 .. Matches (9).Last - 1),
                  Demangled,
                  Locations);
            end if;

            --  Include the parsed location if it is not already in the list

            Locations.Insert (Tmp_Location, Ignore, New_Location);

            --  Destroy the String that was previously allocated if it is no
            --  longer needed.

            if not New_Location then
               GNAT.Strings.Free
                 (GNAT.Strings.String_Access (Tmp_Location.File));
            end if;
         end if;

      else
         --  The file location is malformed. This information is not
         --  required for computing stack usage (it is only helpful to
         --  present the results).

         Locations := Static_Stack_Analysis.List_Of_Locations.Empty_Set;

         if Options.Debug then
            Ada.Text_IO.Put_Line
              (Ada.Directories.Simple_Name
                 (Ada.Text_IO.Name (Descriptor)) & ":" &
               Ada.Strings.Fixed.Trim
                 (Ada.Text_IO.Positive_Count'Image
                    (Ada.Text_IO.Line (Descriptor) - 1),
                  Ada.Strings.Both) &
               ": Could not parse the label");
         end if;
      end if;
   end Parse_Front_End_Locations;

   -----------------------
   -- Parse_Stack_Usage --
   -----------------------

   procedure Parse_Stack_Usage
     (Input : String; Stack : out Static_Stack_Analysis.Stack_Usage_Info)
   is
      Matches : GNAT.Regpat.Match_Array (0 .. 2);

   begin
      GNAT.Regpat.Match (Stack_Regexp & "$", Input, Matches);

      if Matches (0) /= GNAT.Regpat.No_Match then
         Stack.Static_Usage :=
           Static_Stack_Analysis.Frame_Size'Value
             (Input (Matches (1).First .. Matches (1).Last));

         if Matches (2) = GNAT.Regpat.No_Match
           or else Input (Matches (2).First .. Matches (2).Last) = " (static)"
         then
            Stack.Frame_Type := Static_Stack_Analysis.Static;
            Stack.Dynamic_Usage := Static_Stack_Analysis.Empty_Value;
            Stack.Unknown_Usage := Static_Stack_Analysis.Empty_Value;
            Stack.Cycle_Usage   := Static_Stack_Analysis.Empty_Value;

         elsif
           Input (Matches (2).First .. Matches (2).Last) = " (dynamic)"
         then
            Stack.Frame_Type := Static_Stack_Analysis.Unbounded;
            Stack.Dynamic_Usage :=
              Static_Stack_Analysis.Frame_Size (Options.Default_Unbounded);
            Stack.Unknown_Usage := Static_Stack_Analysis.Empty_Value;
            Stack.Cycle_Usage   := Static_Stack_Analysis.Empty_Value;

         elsif
           Input (Matches (2).First .. Matches (2).Last) = " (dynamic,bounded)"
         then
            Stack.Frame_Type := Static_Stack_Analysis.Bounded;
            Stack.Dynamic_Usage := Static_Stack_Analysis.Empty_Value;
            Stack.Unknown_Usage := Static_Stack_Analysis.Empty_Value;
            Stack.Cycle_Usage   := Static_Stack_Analysis.Empty_Value;

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

   procedure Parse_Shape (Input : String; Local : out Boolean) is
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

      Matches          : GNAT.Regpat.Match_Array (0 .. 3);
      Loc_Matches      : GNAT.Regpat.Match_Array (0 .. 9);
      Dispatch_Matches : GNAT.Regpat.Match_Array (0 .. 3);

      Source_Id        : Static_Stack_Analysis.Node_Id;
      Target_Id        : Static_Stack_Analysis.Node_Id;

      Source_Ptr       : Static_Stack_Analysis.Node_Class_Access;
      Target_Ptr       : Static_Stack_Analysis.Node_Class_Access;

      Locations_Set    : Static_Stack_Analysis.List_Of_Locations.Set :=
        Static_Stack_Analysis.List_Of_Locations.Empty_Set;

      New_Node         : Boolean := False;

      Source_Name      : Name;
      Target_Name      : Name;

      use type Ada.Text_IO.Positive_Count;

   --  Start of processing for Parse_Edge
   begin
      --  The pattern of the input line is:
      --  edge: { sourcename: "([^"]*)" targetname: "([^"]*)"
      --  ( label: ".*"| priority: .*)?? }

      if Options.Progress_Information then
         Display.Increase_Count (Global_Data.Parse_Call);
      end if;

      --  Get source, target and location

      GNAT.Regpat.Match (Edge_Regexp, Input, Matches);

      if Matches (0) /= GNAT.Regpat.No_Match then
         --  Get the location of this call. If this information is not found
         --  it is not considered a major issue and processing continues.

         if Matches (3) /= GNAT.Regpat.No_Match and then
           GNAT.Regpat.Match
             (Edge_Label_Regexp,
              Input (Matches (3).First .. Matches (3).Last))
         then
            GNAT.Regpat.Match
              (Edge_Label_Regexp,
               Input (Matches (3).First .. Matches (3).Last),
               Loc_Matches);

            pragma Assert
              (Loc_Matches (0) /= GNAT.Regpat.No_Match and then
               Loc_Matches (1) /= GNAT.Regpat.No_Match);

            Parse_Front_End_Locations
              (Input (Loc_Matches (1).First .. Loc_Matches (1).Last),
               null,
               Locations_Set);

         --  Emit warning when the label cannot be processed. Ignore lines
         --  with " priority: .*" or with nothing.
         elsif Options.Debug and then
           ((Matches (3) = GNAT.Regpat.No_Match
                and then
             not GNAT.Regpat.Match
               ("^\s*}\s*$", Input (Matches (2).Last + 2 .. Input'Last)))
               or else
            (Matches (3) /= GNAT.Regpat.No_Match
                and then
             not GNAT.Regpat.Match
               ("^ priority: .*",
                Input (Matches (3).First .. Matches (3).Last))))
         then
            Ada.Text_IO.Put_Line
              (Ada.Directories.Simple_Name
                    (Ada.Text_IO.Name (Descriptor)) & ":" &
               Ada.Strings.Fixed.Trim
                 (Ada.Text_IO.Positive_Count'Image
                    (Ada.Text_IO.Line (Descriptor) - 1),
                  Ada.Strings.Both) &
               ": Could not parse the label");
         end if;

         --  Look for the source node in the list, or create the node if it
         --  does not exist yet.

         Source_Name := new String'
           (Get_Unique_Symbol_Name
              (Input (Matches (1).First .. Matches (1).Last)));

         Source_Id := Get_Node (Source_Name.all);

         if not List_Of_Nodes.Has_Element (Source_Id) then

            Source_Ptr := new Unresolved_Node'
              (Ada_File_Name           => Ada_File_Name,
               Target_Calls            => List_Of_Edges.Empty_Vector,
               Accumulated_Stack_Usage => Unknown_Stack_Usage,
               Location_List           => List_Of_Locations.Empty_Set,
               Subprogram              => Source_Name,
               Demangled               =>
                 new String'
                   (Demangle.Decode (Source_Name.all, Ada_File_Name)),
               Alias                   => null,
               Under_Analysis          => False,
               Analysis_Finished       => False,
               Is_Called               => False,
               Is_Reachable            => False,
               Cycles                  => List_Of_Cycles.Empty_Set);

            Global_Data.List_Of_Subprograms.Insert
              (Source_Ptr, Source_Id, New_Node);

            pragma Assert (New_Node);
         else
            --  Get the node so we can add the new information later on

            Source_Ptr := List_Of_Nodes.Element (Source_Id);

            --  The previously allocated name is not needed in this case

            Free (Source_Name);
         end if;

         --  Look for the target node in the list, or create the node if it
         --  does not exist yet.

         --  The target node may be a regular subprogram, a general indirect
         --  call, or a dispatching call with the format
         --  slot:base_class:static_class.

         GNAT.Regpat.Match
           (Dispatching_Regexp,
            Input (Matches (2).First .. Matches (2).Last),
            Dispatch_Matches);

         --  Target is a dispatching call
         if Dispatch_Matches (0) /= GNAT.Regpat.No_Match then
            declare
               Base_Class_Name : String renames
                 Input
                   (Dispatch_Matches (2).First .. Dispatch_Matches (2).Last);

               Static_Class_Name : String renames
                 Input
                   (Dispatch_Matches (3).First .. Dispatch_Matches (3).Last);

               Slot_String : String renames
                 Input
                   (Dispatch_Matches (1).First .. Dispatch_Matches (1).Last);

               Slot : constant Slot_Number := Slot_Number'Value (Slot_String);

            begin
               --  Check whether there is already a dispatching call node
               --  with the same triple slot:base_class:static_class

               Target_Id :=
                 Get_Node (Base_Class_Name & Slot_String & Static_Class_Name);

               if List_Of_Nodes.Has_Element (Target_Id) then
                  Target_Ptr := List_Of_Nodes.Element (Target_Id);

                  pragma Assert (Target_Ptr.all in Dispatching_Node);

                  declare
                     Node : Dispatching_Node renames
                       Dispatching_Node (Target_Ptr.all);

                  begin
                     --  Add this location

                     Node.Location_List.Union (Locations_Set);

                     --  Verify that the information that we have corresponds
                     --  to the information that is stored.

                     pragma Assert
                       (Node.Slot = Slot
                           and then
                        Node.Base_Class.Class_Name.all = Base_Class_Name
                           and then
                        Node.Static_Class.Class_Name.all = Static_Class_Name);
                  end;

               else
                  --  We need to create the node

                  --  ??? Note that in the location we need to add a demangled
                  --  name to identify the node representing the dispatching
                  --  call. It is not clear how to represent a node which is
                  --  defined by a triple slot:base_class:static_class. We
                  --  leave the demangled field empty for now.

                  Target_Ptr := new Dispatching_Node'
                    (Ada_File_Name           => Ada_File_Name,
                     Location_List           => Locations_Set,
                     Target_Calls            => List_Of_Edges.Empty_Vector,
                     Accumulated_Stack_Usage => Unknown_Stack_Usage,
                     Slot                    => Slot,
                     Base_Class              =>
                       Insert_Class (Symbol  => Base_Class_Name,
                                     Defined => False,
                                     Loc     => List_Of_Locations.Empty_Set),
                     Static_Class            =>
                       Insert_Class (Symbol  => Static_Class_Name,
                                     Defined => False,
                                     Loc     => List_Of_Locations.Empty_Set),
                     Internal_Name           =>
                     new String'
                       (Base_Class_Name & Slot_String & Static_Class_Name),
                     Under_Analysis          => False,
                     Analysis_Finished       => False,
                     Is_Called               => True,
                     Is_Reachable            => False,
                     Cycles                  => List_Of_Cycles.Empty_Set);

                  Global_Data.List_Of_Subprograms.Insert
                    (Target_Ptr, Target_Id, New_Node);

                  pragma Assert (New_Node);
               end if;

               --  Add the location of this dispatching call to the global list
               --  so it is much faster to find it to check for duplicated
               --  indirect calls (generated by the back end when compiling
               --  Ada code).

               Global_Data.Location_All_Dispatching_Calls.Union
                 (Locations_Set);
            end;

         --  Handle indirect calls
         elsif
           Input (Matches (2).First .. Matches (2).Last) = Indirect_Call.all
         then
            --  The compiler may generate for a single dispatching call two
            --  edges:
            --    * One generated by the front end with the dispatching
            --      information:
            --         edge: { sourcename: "caller"
            --                 targetname: "1:tagged_type,tagged_type"
            --                 label: "file.adb:9:7"
            --               }
            --
            --    * One generated by the back end indicating that this is an
            --      indirect call:
            --         edge: { sourcename: "caller"
            --                 targetname: "__indirect_call"
            --                 label: "file.adb:9:7"
            --               }
            --
            --  If this is the case, we ignore the one generated by the back
            --  end because the information is in the edge generated by the
            --  front end, and keeping the one from the back end leads to
            --  GNATstack to think there are two different calls.
            --
            --  Note that the important field is the label containing the
            --  SLOC. In case of inlining, the front-end and the back-end
            --  may emit different sourcename fields. For example, if Caller
            --  calls an inlined procedure (Inlined) which in turn makes a
            --  dispatching call, we will have the following information:
            --    * Front end:
            --         edge: { sourcename: "inlined"
            --                 targetname: "1:tagged_type,tagged_type"
            --                 label: "file.adb:9:7"
            --               }
            --
            --    * Back-end:
            --         edge: { sourcename: "caller"
            --                 targetname: "__indirect_call"
            --                 label: "file.adb:9:7"
            --               }
            --
            --  There is another situation that needs to be considered.
            --  Sometimes, in this case of inlining, the back-end emits a
            --  label containing the file location. Hence, we end up with
            --  information that seems unrelated such as:
            --    * Front end:
            --         edge: { sourcename: "inlined"
            --                 targetname: "1:tagged_type,tagged_type"
            --                 label: "file.adb:9:7"
            --               }
            --
            --    * Back-end:
            --         edge: { sourcename: "caller"
            --                 targetname: "__indirect_call"
            --                 label: "/my/location/file.adb:9:7"
            --               }
            --
            --  Therefore, this file prefix needs to be removed if we want to
            --  determine whether to ignore the information generated by the
            --  back end. Note that the removal of the file location is
            --  handled within the function Location_Is_Dispatching.

            if Demangle.Is_Ada (Ada_File_Name) and then
              Location_Is_Dispatching (Locations_Set)
            then
               --  This edge is the back-end representation of a dispatching
               --  call. Therefore, we need to check whether we have the
               --  required information to resolve this call. Without inlining
               --  there is nothing else to do, because the caller (sourcename)
               --  will be the same in the front-end and back-end:
               --
               --         edge: { sourcename: "caller"
               --                 targetname: "1:tagged_type,tagged_type"
               --                 label: "file.adb:9:7"
               --               }
               --
               --         edge: { sourcename: "caller"
               --                 targetname: "__indirect_call"
               --                 label: "file.adb:9:7"
               --               }
               --
               --  However, in presence of inlining the caller may differ:
               --
               --         edge: { sourcename: "inlined"
               --                 targetname: "1:tagged_type,tagged_type"
               --                 label: "file.adb:9:7"
               --               }
               --
               --         edge: { sourcename: "caller"
               --                 targetname: "__indirect_call"
               --                 label: "[/my/location/]file.adb:9:7"
               --               }
               --
               --  In this case, we need to propagate the dispatching edge
               --  from "inlined" to "caller".

               --  If the node identified by sourcename already contains the
               --  dispatching call information then there is nothing else to
               --  do.

               pragma Assert (Source_Ptr.all in Explicit_Node'Class);

               declare
                  Index : List_Of_Edges.Cursor :=
                    Source_Ptr.Target_Calls.First;

                  Node_Index : List_Of_Nodes.Cursor :=
                    Global_Data.List_Of_Subprograms.First;

                  Call : Edge;

                  Subprogram : Node_Class_Access;

               begin
                  --  Check whether the caller contains already a dispatching
                  --  or indirect call corresponding to this location

                  while List_Of_Edges.Has_Element (Index) loop
                     Call := List_Of_Edges.Element (Index);

                     exit when
                       (List_Of_Nodes.Element (Call.Target).all in
                        Dispatching_Node'Class
                           or else
                        List_Of_Nodes.Element (Call.Target).all in
                        Indirect_Node'Class)
                          and then
                       not Call.Point_Of_Call.Intersection
                          (Locations_Set).Is_Empty;

                     Index := List_Of_Edges.Next (Index);
                  end loop;

                  if List_Of_Edges.Has_Element (Index) then
                     --  Nothing else to do. The information about the
                     --  dispatching call is already there.

                     return;

                  else
                     --  We need to copy the dispatching call information
                     --  (generated by the front-end) into the caller which
                     --  inlines the subprogram performing a dispatching call.

                     --  Look for the corresponding dispatching node which
                     --  matches this location.

                     while List_Of_Nodes.Has_Element (Node_Index) loop
                        Subprogram := List_Of_Nodes.Element (Node_Index);

                        if Subprogram.all in Dispatching_Node'Class and then
                          not Subprogram.Location_List.Intersection
                            (Locations_Set).Is_Empty
                        then
                           Target_Ptr := Subprogram;
                           Target_Id := Node_Index;

                           exit;

                        else
                           Node_Index := List_Of_Nodes.Next (Node_Index);
                        end if;
                     end loop;

                     pragma Assert (List_Of_Nodes.Has_Element (Node_Index));
                  end if;
               end;

            else
               --  This is an indirect (non-dispatching) call

               Target_Name :=
                 new String'
                   (if not Locations_Set.Is_Empty then
                      Indirect_Call.all &
                      Real_Node (Source_Ptr.all).Subprogram.all &
                      Input (Loc_Matches (1).First .. Loc_Matches (1).Last)
                    else
                      Indirect_Call.all &
                      Real_Node (Source_Ptr.all).Subprogram.all);

               --  Try to see whether the indirect node exists

               if Target_Name = null then
                  Target_Id := Static_Stack_Analysis.List_Of_Nodes.No_Element;
               else
                  Target_Id := Get_Node (Target_Name.all);
               end if;

               --  Create the node for the indirect call if it does not exist

               if List_Of_Nodes.Has_Element (Target_Id) then
                  --  If the node is already in the list then there is nothing
                  --  else to do.

                  return;

               else
                  Target_Ptr := new Indirect_Node'
                    (Ada_File_Name           => Ada_File_Name,
                     Location_List           => Locations_Set,
                     Internal_Name           => Target_Name,
                     Target_Calls            => List_Of_Edges.Empty_Vector,
                     Accumulated_Stack_Usage => Unknown_Stack_Usage,
                     Under_Analysis          => False,
                     Analysis_Finished       => False,
                     Is_Called               => True,
                     Is_Reachable            => False,
                     Cycles                  => List_Of_Cycles.Empty_Set);

                  Global_Data.List_Of_Subprograms.Insert
                    (Target_Ptr, Target_Id, New_Node);

                  pragma Assert (New_Node);
                  --  We have previously verified that the node is not in the
                  --  list.

                  --  Now we have created a new node to describe an indirect
                  --  We may have already overridden this indirect call with
                  --  the required information to find the list of actual
                  --  targets. In that case, the caller will already have an
                  --  edge with the same location as the one we are trying to
                  --  insert. What we need to do now is to put user provided
                  --  information under the new node.

                  Move_Indirect_Calls (Source_Ptr, Target_Ptr);
               end if;

            end if;

         --  Regular call (call to neither dispatching nor indirect nodes)
         else
            Target_Name :=
              new String'
                (Get_Unique_Symbol_Name
                     (Input (Matches (2).First .. Matches (2).Last)));

            Target_Id := Get_Node (Target_Name.all);

            if List_Of_Nodes.Has_Element (Target_Id) then
               --  Mark the subprogram as called by another

               Target_Ptr := List_Of_Nodes.Element (Target_Id);

               Target_Ptr.Is_Called := True;

               --  The previously allocated name is not needed in this case

               Free (Target_Name);

            --  This node is considered unresolved for the moment. It can be
            --  later modified if we find more information.
            else
               Target_Ptr := new Unresolved_Node'
                 (Ada_File_Name           => Ada_File_Name,
                  Target_Calls            => List_Of_Edges.Empty_Vector,
                  Accumulated_Stack_Usage => Unknown_Stack_Usage,
                  Location_List           => List_Of_Locations.Empty_Set,
                  Subprogram              => Target_Name,
                  Demangled               =>
                    new String'
                      (Demangle.Decode (Target_Name.all, Ada_File_Name)),
                  Alias                   => null,
                  Under_Analysis          => False,
                  Analysis_Finished       => False,
                  Is_Called               => True,
                  Is_Reachable            => False,
                  Cycles                  => List_Of_Cycles.Empty_Set);

               Global_Data.List_Of_Subprograms.Insert
                 (Target_Ptr, Target_Id, New_Node);

               pragma Assert (New_Node);
            end if;
         end if;

         --  There may be already an edge joining these two subprograms. We
         --  always create a new edge for a new call, which is desirable in
         --  case we want to treat calls in a different way, and it is
         --  mandatory for user-defined information. For example, if there are
         --  two indirect calls from the same subprogram, and these two
         --  indirect calls are resolved to the same target, we want to keep
         --  these two instances separate so that we can later place them
         --  where they belong.

         declare
            Index  : Static_Stack_Analysis.Edge_Id;

            Call   : Static_Stack_Analysis.Edge;

         begin
            Index := Source_Ptr.Target_Calls.First;

            while Static_Stack_Analysis.List_Of_Edges.Has_Element (Index) loop
               Call := Static_Stack_Analysis.List_Of_Edges.Element (Index);

               --  The edge that we are inserting may need to be located at two
               --  different places. It will usually be added as an edge for
               --  the Source node but, in the case of edges added manually by
               --  the user to resolve indirect calls, it will need to be
               --  placed in the node representing the indirect call.
               if
                 Ada_File_Name = null
                   and then
                 Target_Ptr.all in Real_Node'Class
                   and then
                 List_Of_Nodes.Element (Call.Target).all in Indirect_Node'Class
                   and then
                 (Locations_Set.Is_Empty or else
                  Call.Point_Of_Call.Is_Empty or else
                  not Call.Point_Of_Call.Intersection (Locations_Set).Is_Empty)
               then
                  --  ??? Do I need to use Fake_Node'Class?

                  --  Modify the source to be located at the indirect node

                  Source_Ptr := List_Of_Nodes.Element (Call.Target);

                  --  Exit since we have found the location we were looking for

                  exit;
               else
                  Static_Stack_Analysis.List_Of_Edges.Next (Index);
               end if;
            end loop;

            --  Create new edge with the information that we have about the
            --  source and the target.

            pragma Assert (List_Of_Nodes.Has_Element (Target_Id));

            Static_Stack_Analysis.List_Of_Edges.Append
              (Source_Ptr.Target_Calls,
               new Static_Stack_Analysis.Edge_Element'(
                 Ada_File_Name  => Ada_File_Name,
                 Target         => Target_Id,
                 Point_Of_Call  => Locations_Set,
                 Feasible_Call  => True,
                 Under_Analysis => False));

            --  The only possible missing step is the propagation of the edge
            --  to all indirect calls when we add manually an edge without
            --  an specific location. In this case, the manual edge applies to
            --  all indirect calls originating from Source.

            if Ada_File_Name = null and then Locations_Set.Is_Empty then
               Index := Source_Ptr.Target_Calls.First;

               while List_Of_Edges.Has_Element (Index) loop
                  Call := Static_Stack_Analysis.List_Of_Edges.Element (Index);

                  if List_Of_Nodes.Element (Call.Target).all in
                     Indirect_Node'Class
                     --  ??? Do I need to use Fake_Node'Class?
                  then
                     --  Create new edge with the information that we have
                     --  about the source and the target.

                     pragma Assert (List_Of_Nodes.Has_Element (Target_Id));

                     Static_Stack_Analysis.List_Of_Edges.Append
                       (List_Of_Nodes.Element (Call.Target).Target_Calls,
                        new Static_Stack_Analysis.Edge_Element'(
                          Ada_File_Name  => Ada_File_Name,
                          Target         => Target_Id,
                          Point_Of_Call  => Locations_Set,
                          Feasible_Call  => True,
                          Under_Analysis => False));

                  end if;

                  Static_Stack_Analysis.List_Of_Edges.Next (Index);
               end loop;
            end if;
         end;
      else
         raise Parser_Error;
      end if;
   end Parse_Edge;

   -----------------
   -- Parse_Class --
   -----------------

   procedure Parse_Class (Input : String) is
      use Static_Stack_Analysis;

      Match_Class_Info  : GNAT.Regpat.Match_Array (0 .. 5);

      Match_Label       : GNAT.Regpat.Match_Array (0 .. 11);

      This_Class        : Class_Access;

      CName             : Name;
      Demangled         : Name;

      Locations_Set     : List_Of_Locations.Set := List_Of_Locations.Empty_Set;

      Is_Primary_Parent : Boolean := True;

      procedure Get_Parents (Input : String);
      --  Get the list of parents class stored in the comma-separated list
      --  passed as input.

      procedure Get_Virtuals (Input : String);
      --  Get the list of virtual methods for the class

      procedure Get_Parents (Input : String) is
         Match_Parents : GNAT.Regpat.Match_Array (0 .. 2);

         Parent        : Class_Access;

      begin
         GNAT.Regpat.Match (Name_Regexp, Input, Match_Parents);

         if Match_Parents (0) /= GNAT.Regpat.No_Match and then
           Match_Parents (1) /= GNAT.Regpat.No_Match
         then
            --  Sometimes (for private tagged types) the compiler indicates
            --  that a class is its own parent also. We skip this case.

            if CName.all /=
              Input (Match_Parents (1).First .. Match_Parents (1).Last)
            then
               --  Look for the class in the list or insert it if not there yet

               Parent :=
                 Insert_Class
                   (Symbol  =>
                     Input (Match_Parents (1).First .. Match_Parents (1).Last),
                    Defined => False,
                    Loc     => List_Of_Locations.Empty_Set);

               --  Insert the parent in the list of parents for the class being
               --  processed. Use Include instead of Insert because the class
               --  may be in the set already.

               This_Class.Parents.Include (Parent);

               --  The first parent is the primary parent

               if Is_Primary_Parent then

                  if This_Class.Primary_Parent = null then
                     --  Insert the pointer to the first parent if the
                     --  information is not there yet.

                     This_Class.Primary_Parent := Parent;

                  elsif
                    This_Class.Primary_Parent.Class_Name.all /=
                      Input (Match_Parents (1).First .. Match_Parents (1).Last)
                  then
                     --  The information about the primary parent may be
                     --  already there but we make sure it is consistent.

                     raise Parser_Error with "Conflicting primary parent";
                  end if;

                  --  We already have the primary parent

                  Is_Primary_Parent := False;

               end if;

            end if;
         else
            raise Parser_Error with
              "Cannot find class in parent list" & Input;
         end if;

         if Match_Parents (2) /= GNAT.Regpat.No_Match then
            --  Continue extracting parents. Skip the ", ".

            Get_Parents
              (Input (Match_Parents (2).First + 2 .. Match_Parents (2).Last));
         end if;
      end Get_Parents;

      procedure Get_Virtuals (Input : String) is
         Match_Virtual       : GNAT.Regpat.Match_Array (0 .. 2);

         Match_Info          : GNAT.Regpat.Match_Array (0 .. 8);

         Method              : Virtual_Class_Access := null;

      begin
         GNAT.Regpat.Match (Virtual_Set_Regexp, Input, Match_Virtual);

         if Match_Virtual (0) /= GNAT.Regpat.No_Match and then
           Match_Virtual (1) /= GNAT.Regpat.No_Match
         then
            --  Get the information (slot, symbol name, and possibly virtual
            --  bases) for the method.

            GNAT.Regpat.Match
              (Virtual_Info_Regexp,
               Input (Match_Virtual (1).First .. Match_Virtual (1).Last),
               Match_Info);

            if Match_Info (0) /= GNAT.Regpat.No_Match then

               pragma Assert
                 (Match_Info (1) /= GNAT.Regpat.No_Match and then
                  Match_Info (2) /= GNAT.Regpat.No_Match);

               --  Look for the method in the list and create it if it is not
               --  registered yet.

               Method :=
                 Insert_Method
                   (Id => Vtable_Loc'
                             (This_Class,
                              Slot_Number'Value
                                 (Input (Match_Info (1).First ..
                                         Match_Info (1).Last))),
                    Symbol =>
                      Input (Match_Info (2).First .. Match_Info (2).Last));

               --  Add this method to the list of methods belonging to the
               --  class. Use Include instead of Insert because the method
               --  may be in the set already.

                  This_Class.Virtual.Include (Method);

               --  Virtual bases are not mandatory, because they appear only
               --  when we are overriding.

               if Match_Info (3) /= GNAT.Regpat.No_Match then
                  --  This is the virtual base corresponding to this method.
                  --  We need to add this to the list of virtual bases.

                  pragma Assert
                    (Match_Info (4) /= GNAT.Regpat.No_Match and then
                     Match_Info (5) /= GNAT.Regpat.No_Match);

                  --  Store the pair class:slot for the virtual base. Look
                  --  for the ancestor class and create it if it is not
                  --  registered yet.

                  Method.Redefines :=
                    Vtable_Loc'
                      (Insert_Class
                         (Symbol =>
                            Input (Match_Info (5).First ..
                                   Match_Info (5).Last),
                          Defined => False,
                          Loc => List_Of_Locations.Empty_Set),
                       Slot_Number'Value
                         (Input (Match_Info (4).First ..
                                 Match_Info (4).Last)));
               end if;

               --  This second vtable entry will only appear when a class
               --  has multiple base classes, and therefore multiple vtables,
               --  and when the method that is overridden does not come from
               --  the primary base. Redefines_Multiple will contain the
               --  location in the primary vtable.

               if Match_Info (6) /= GNAT.Regpat.No_Match then
                  --  This is the virtual base corresponding to this method.
                  --  We need to add this to the list of virtual bases.

                  pragma Assert
                    (Match_Info (7) /= GNAT.Regpat.No_Match and then
                     Match_Info (8) /= GNAT.Regpat.No_Match);

                  --  Store the pair class:slot for the virtual base. Look
                  --  for the ancestor class and create it if it is not
                  --  registered yet.

                  Method.Redefines_Multiple :=
                    Vtable_Loc'
                      (Insert_Class
                         (Symbol =>
                            Input (Match_Info (8).First ..
                                   Match_Info (8).Last),
                          Defined => False,
                          Loc => List_Of_Locations.Empty_Set),
                       Slot_Number'Value
                         (Input (Match_Info (7).First ..
                                 Match_Info (7).Last)));
               end if;

            else
               raise Parser_Error with
              "Cannot parse the virtual method: " & Input;
            end if;

         --  It may be the case that the class does not define any virtual
         --  method. In this case, the string is empty.
         elsif Input = "" then
            null;

         --  Otherwise there is a problem in the format
         else
            raise Parser_Error with
              "Cannot parse virtual methods in: " & Input;
         end if;

         if Match_Virtual (2) /= GNAT.Regpat.No_Match then
            --  Continue extracting virtual methods. Skip the "\n ".

            Get_Virtuals
              (Input (Match_Virtual (2).First + 3 .. Match_Virtual (2).Last));
         end if;
      end Get_Virtuals;

   --  Start of processing for Parse_Class
   begin
      --  The pattern of the input line is:
      --  class {
      --   classname: "name"
      --   label: "demangled_name\nfilename:line[:column]"
      --   [parent: "classname_parent1[, classname_parent2]"]
      --   virtuals: "slot_number:symbol_name[,slot_number:overrides_classname]
      --   [\n slot_number:symbol_name[,slot_number:overrides_classname]]"
      --  }
      --
      --  The name is the internal encoded (mangled) name of the class. This
      --  is an unique identifier for the class.
      --
      --  The label contains the demangled name of the class plus its file
      --  location.
      --
      --  The line with parent will appear only if the class is derived from
      --  others. In this case, the list of parents (their internal encoded
      --  (mangled) name) will be passed here as a comma-separated list.
      --
      --  The field virtuals contains the information about virtual functions
      --  defined by the task. It is a list of methods, separated by \n, for
      --  which we specify their corresponding position in the primary virtual
      --  table, the symbol name corresponding to the method, and in the case
      --  of being overriding a method, we identify the overridden method
      --  specifying the class identifier to which the overridden method
      --  belongs and its slot in the virtual table.

      if Options.Progress_Information then
         Display.Increase_Count (Global_Data.Class);
      end if;

      GNAT.Regpat.Match (Class_Regexp, Input, Match_Class_Info);

      if Match_Class_Info (0) /= GNAT.Regpat.No_Match then
         --  Get the name of the class and create the element to describe
         --  the class

         pragma Assert (Match_Class_Info (1) /= GNAT.Regpat.No_Match);

         CName := new String'
           (Input (Match_Class_Info (1).First .. Match_Class_Info (1).Last));

         --  Get demangled name and file location

         pragma Assert (Match_Class_Info (2) /= GNAT.Regpat.No_Match);

         GNAT.Regpat.Match
           (Class_Label_Regexp,
            Input (Match_Class_Info (2).First .. Match_Class_Info (2).Last),
            Match_Label);

         if Match_Label (0) /= GNAT.Regpat.No_Match then
            pragma Assert (Match_Label (3) /= GNAT.Regpat.No_Match);

            if Match_Label (1) /= GNAT.Regpat.No_Match and then
              Match_Label (2) /= GNAT.Regpat.No_Match
            then
               --  We have the demangled information

               Demangled :=
                 new String'
                   (Input (Match_Label (2).First .. Match_Label (2).Last));

            else
               --  We need to generate the demangled name

               Demangled :=
                 new String'
                   (Demangle.Decode (CName.all, Ada_File_Name));
            end if;

            pragma Assert (Match_Label (3) /= GNAT.Regpat.No_Match and then
               Match_Label (6) /= GNAT.Regpat.No_Match and then
               Match_Label (7) /= GNAT.Regpat.No_Match and then
               Match_Label (9) /= GNAT.Regpat.No_Match);

            Parse_Front_End_Locations
              (Input (Match_Label (3).First .. Match_Label (3).Last),
               Demangled,
               Locations_Set);

         else
            --  The label is malformed. This information is not required for
            --  computing stack usage (it is only helpful to present the
            --  results).

            Locations_Set := Static_Stack_Analysis.List_Of_Locations.Empty_Set;

            if Options.Debug then
               Ada.Text_IO.Put_Line
                 ("Could not parse label: " &
                  Input
                    (Match_Class_Info (2).First .. Match_Class_Info (2).Last));
            end if;
         end if;

         --  Look for the class and create it if it is not registered yet

         This_Class :=
           Insert_Class
             (Symbol => CName.all, Defined => True, Loc => Locations_Set);

         --  Populate the list of parents, if any

         if Match_Class_Info (3) /= GNAT.Regpat.No_Match then
            --  This is a comma-separated list of class names

            pragma Assert (Match_Class_Info (4) /= GNAT.Regpat.No_Match);

            Get_Parents
              (Input
                 (Match_Class_Info (4).First .. Match_Class_Info (4).Last));
         end if;

         --  Get the list of virtual methods

         pragma Assert (Match_Class_Info (5) /= GNAT.Regpat.No_Match);

         Get_Virtuals
           (Input (Match_Class_Info (5).First .. Match_Class_Info (5).Last));

      else
         raise Parser_Error with
              "Cannot parse class" & Input;
      end if;
   end Parse_Class;

   ----------------------
   -- Parse_Input_File --
   ----------------------

   procedure Parse_Input_File (File : File_Id) is
   begin
      --  We do not know yet the originating Ada file. We cannot deallocate
      --  this name because its value will probably have been copied in
      --  nodes and edges associated to it.

      Ada_File_Name := null;

      Ada.Text_IO.Open
        (Descriptor, Ada.Text_IO.In_File, List_Of_Files.Element (File).all);

      --  Parse information line by line. Note that we can find lines which
      --  are split, so we merge them here. The lines that may need
      --  reconstruction are:
      --    - node: { ... }
      --    - edge: { ... }
      --    - class { ... }

      while not Ada.Text_IO.End_Of_File (Descriptor) loop
         Outer_Loop : declare
            Complete_Line : GNAT.Strings.String_Access :=
              new String'(Ada.Text_IO.Get_Line (Descriptor));

            Reconstructed_Line : Ada.Strings.Unbounded.Unbounded_String :=
              Ada.Strings.Unbounded.Null_Unbounded_String;

         begin
            --  Look for non-terminated node/edge/class lines. In that case
            --  we merge the following lines until we find the end "}".
            if GNAT.Regpat.Match (Entity_Regexp, Complete_Line.all) then
               --  Remove Windows CR character
               if Complete_Line (Complete_Line'Last) = ASCII.CR then
                  Reconstructed_Line :=
                    Ada.Strings.Unbounded.To_Unbounded_String
                      (Complete_Line
                           (Complete_Line'First .. Complete_Line'Last - 1));
               else
                  Reconstructed_Line :=
                    Ada.Strings.Unbounded.To_Unbounded_String
                      (Complete_Line.all);
               end if;

               while not Ada.Text_IO.End_Of_File (Descriptor) loop
                  Inner_Loop : declare
                     Next_Line : constant String :=
                       Ada.Text_IO.Get_Line (Descriptor);

                  begin
                     --  Append a new line until we find the ending "}".
                     --  Remove Windows CR character.
                     if Next_Line (Next_Line'Last) = ASCII.CR then
                        Ada.Strings.Unbounded.Append
                          (Reconstructed_Line,
                           Next_Line (Next_Line'First .. Next_Line'Last - 1));
                     else
                        Ada.Strings.Unbounded.Append
                          (Reconstructed_Line, Next_Line);
                     end if;

                     exit when GNAT.Regpat.Match ("}\s*(--.*)??$", Next_Line);
                  end Inner_Loop;
               end loop;

               GNAT.Strings.Free (Complete_Line);

               Complete_Line := new String'
                 (Ada.Strings.Unbounded.To_String (Reconstructed_Line));
            end if;

            Parse_Input_Line (Complete_Line.all);

            GNAT.Strings.Free (Complete_Line);
         end Outer_Loop;
      end loop;

      Ada.Text_IO.Close (Descriptor);
   exception
      when Parser_Error =>
         Ada.Text_IO.Put_Line
           ("Error parsing file " & List_Of_Files.Element (File).all);

         if Ada.Text_IO.Is_Open (Descriptor) then
            Ada.Text_IO.Close (Descriptor);
         end if;

         raise;
   end Parse_Input_File;

   ---------------------
   -- Pattern_In_Node --
   ---------------------

   function Pattern_In_Node
     (Pattern  : String; Position : Static_Stack_Analysis.Node_Id)
      return Boolean
   is
      Explored_Node : constant Static_Stack_Analysis.Node_Class_Access :=
        Static_Stack_Analysis.List_Of_Nodes.Element (Position);

      use Static_Stack_Analysis;

   begin
      --  Use both the symbol name and the demangled name

      return
        GNAT.Regpat.Match
          (Ada.Characters.Handling.To_Lower (Pattern),
           Ada.Characters.Handling.To_Lower
             (Get_Subprogram_Name (Explored_Node.all).all))
           or else
         GNAT.Regpat.Match
           (Ada.Characters.Handling.To_Lower (Pattern),
            Ada.Characters.Handling.To_Lower
              (Get_Demangled_Name (Explored_Node.all).all));
   end Pattern_In_Node;

   -------------------------
   -- Print_Help_And_Exit --
   -------------------------

   procedure Print_Help_And_Exit is
   begin
      Usage;
      GNAT.OS_Lib.OS_Exit (1);
   end Print_Help_And_Exit;

   --------------------------
   -- Print_Usage_And_Exit --
   --------------------------

   procedure Print_Usage_And_Exit is
   begin
      Ada.Text_IO.Put_Line
        ("Use `gnatstack --help` for more information");
      GNAT.OS_Lib.OS_Exit (1);
   end Print_Usage_And_Exit;

   -----------
   -- Usage --
   -----------

   procedure Usage is
      use Ada.Text_IO;
   begin
      Put_Line ("Usage: gnatstack [args ...] [<.ci files>|<.o files>]");
      New_Line;
      Put_Line ("where possible arguments are:");
      Put_Line ("  -a           use all subprograms as entry points");
      Put_Line ("  -aO dir      search for .ci files in dir");
      Put_Line ("  -ca          extract all cycles");
      Put_Line ("  -c size      use size bytes frame for cycle entry");
      Put_Line ("  -d size      default for unbounded (dynamic) calls");
      Put_Line ("  -e <list>    use specific list of subprograms as entry " &
                               "points (e1,e2,...)");
      Put_Line ("  -f file      output graph file");
      Put_Line ("  -files=file  file containing the list of .ci files");
      Put_Line ("  -g           debug information");
      Put_Line ("  -h or --help display help message");
      Put_Line ("  -k           keep temporary files");
      Put_Line ("  -l n         print the n subprograms requiring the " &
                               "biggest local stack usage");
      Put_Line ("  -np          do not display paths for entry points");
      Put_Line ("  -oc=exec     name of the objcopy executable");
      Put_Line ("  -o={a,s}     order for displaying call graphs");
      Put_Line ("      a        alphabetical");
      Put_Line ("      s        stack usage (default)");
      Put_Line ("  -p           display paths for entry points (default)");
      Put_Line ("  -pi          display progress information");
      Put_Line ("  -P=project   load the given project");
      Put_Line ("  -q           quiet: do not display progress information " &
                               "(default)");
      Put_Line ("  -Q           very quiet: do not display any console " &
                               "message (except progress information)");
      Put_Line ("  -r <reg-exp> use all subprograms matching reg-exp as " &
                               "entry points");
      Put_Line ("  --RTS=rt     use the specified run-time library");
      Put_Line ("  -s=section   name of the section where the .ci is " &
                               "in the object");
      Put_Line ("  -txx         print targets for indirect and dispatching " &
                               "calls");
      Put_Line ("    i          only for indirect calls");
      Put_Line ("    d          only for dispatching calls");
      Put_Line ("    a          for both indirect and dispatching calls");
      Put_Line ("  --target=tgt computing stack usage for the specified " &
                                "target (program prefix of the toolchain)");
      Put_Line ("  -u size      default for unknown (external) calls");
      Put_Line ("  -v           verbose");
      Put_Line ("  --version    version information");
      Put_Line ("  -Wxx         enable warnings, xx = list of parameters:");
      Put_Line ("    a          turn on all optional warnings");
      Put_Line ("    c          turn on warnings for cycles");
      Put_Line ("    u          turn on warnings for unbounded frames");
      Put_Line ("    e          turn on warnings for external calls");
      Put_Line ("    i          turn on warnings for indirect calls");
      Put_Line ("  -x           generate the XML output");
      Put_Line ("  -Xname=val   Set project variable name to val");
      New_Line;
      Put_Line ("  <files>      list of call-graph, object, executable " &
                               "files (a.ci b.o c ...)");
   end Usage;

end Parser;
