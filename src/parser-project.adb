------------------------------------------------------------------------------
--                        STATIC STACK ANALYSIS TOOL                        --
--                                                                          --
--                       P A R S E R . P R O J E C T                        --
--                                                                          --
--                                 B o d y                                  --
--                                                                          --
--                     Copyright (C) 2014-2021, AdaCore                     --
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

with Ada.Text_IO;
with Ada.Strings.Unbounded;

with GNAT.Command_Line;
with GNAT.Strings;

with Options;

separate (Parser)
package body Project is

   ----------------
   -- Local data --
   ----------------

   Valid_Options : constant String :=
     "a aO: ca c: d: e: f: files= g h -help k l: np o= oc= p pi P: q Q r: " &
     "-RTS= s= t! -subdirs=: -target= u: v -version W! x X! -list-categories";

   --  Accepted switches
   Tree : GNATCOLL.Projects.Project_Tree;
   --  Descriptor for the project tree

   Project_Opts_Finished : Boolean := True;
   --  Variable indicating whether we have options from the project file to
   --  take into account.

   Parser : GNAT.Command_Line.Opt_Parser;
   --  Parser for options extracted from the project files

   -----------------------
   -- Local subprograms --
   -----------------------

   procedure Parse_Options;
   --  Parse the command line options to get the options we want: -X, -P,
   --  --target, --RTS

   procedure Parse_Project_File;
   --  Process project file hierarchy

   ----------------
   -- Get_Option --
   ----------------

   function Get_Option return Character is
   begin
      --  Command line
      if Project_Opts_Finished then
         return GNAT.Command_Line.Getopt (Valid_Options);

      --  Project file
      else
         declare
            Project_Opt : constant Character :=
              GNAT.Command_Line.Getopt (Valid_Options, True, Parser);
         begin
            if Project_Opt = ASCII.NUL then
               Project_Opts_Finished := True;

               --  Reinitialize the command line arguments because we will need
               --  to parse them again.

               GNAT.Command_Line.Initialize_Option_Scan
                 (Stop_At_First_Non_Switch => True);

               return GNAT.Command_Line.Getopt (Valid_Options);
            else
               return Project_Opt;
            end if;
         end;
      end if;
   end Get_Option;

   ----------------
   -- Get_Switch --
   ----------------

   function Get_Switch return String is
   begin
      if Project_Opts_Finished then
         return GNAT.Command_Line.Full_Switch;
      else
         return GNAT.Command_Line.Full_Switch (Parser);
      end if;
   end Get_Switch;

   -------------------
   -- Get_Parameter --
   -------------------

   function Get_Parameter return String is
   begin
      if Project_Opts_Finished then
         return GNAT.Command_Line.Parameter;
      else
         return GNAT.Command_Line.Parameter (Parser);
      end if;
   end Get_Parameter;

   ----------------------
   -- Get_Project_Info --
   ----------------------

   procedure Get_Project_Info is
   begin
      --  Parse command-line to get options needed to handle projects (-X, -P,
      --  --target, --RTS)
      Parse_Options;

      --  Parse options in package Stack from project file
      Parse_Project_File;
   end Get_Project_Info;

   -------------------
   -- Parse_Options --
   -------------------

   procedure Parse_Options is
      Opt : Character;
   begin
      loop
         Opt := GNAT.Command_Line.Getopt (Valid_Options);
         case Opt is
            when ASCII.NUL =>
               exit;

            --  -Xname=val switch
            when 'X' =>
               declare
                  Arg       : constant String := GNAT.Command_Line.Parameter;
                  Name_Last : Positive;

               begin
                  Name_Last := Arg'First;

                  while Name_Last < Arg'Last
                    and then Arg (Name_Last + 1) /= '='
                  loop
                     Name_Last := Name_Last + 1;
                  end loop;

                  if Name_Last < Arg'Last - 2 then
                     GNATCOLL.Projects.Change_Environment
                       (Env.all,
                        Arg (Arg'First .. Name_Last),
                        Arg (Name_Last + 2 .. Arg'Last));

                  --  Wrong switch
                  else
                     raise GNAT.Command_Line.Invalid_Parameter with
                       "Expected: -Xname=val, found: " & Arg;
                  end if;
               end;

            --  -P switch
            when 'P' =>
               Options.Project :=
                 new String'(GNAT.Command_Line.Parameter);

            -- long option names --
            when '-' =>
               declare
                  Full : constant String := Project.Get_Switch;
               begin
                  --  --target
                  if  Full = "-target" then
                     Options.Target := new String'(Project.Get_Parameter);

                  --  --RTS
                  elsif  Full = "-RTS" then
                     Options.Runtime := new String'(Project.Get_Parameter);
                  end if;
               end;

            --  Ignore other switches (those not related to projects)
            when others =>
               null;
         end case;
      end loop;

      --  Reinitialize the command line arguments because we will need to
      --  parse them again.

      GNAT.Command_Line.Initialize_Option_Scan
        (Stop_At_First_Non_Switch => True);
   end Parse_Options;

   ------------------------
   -- Parse_Project_File --
   ------------------------

   procedure Parse_Project_File is
   begin
      --  Parse the project tree

      if Options.Project = null then
         Tree.Load_Empty_Project
           (Env            => Env,
            Name           => "default",
            Recompute_View => False);

      else
         declare
            use GNATCOLL.Projects;
            use GNATCOLL.VFS;
            use type GNAT.Strings.String_List_Access;

            Tgt : GNAT.Strings.String_Access renames Options.Target;
            Rt : GNAT.Strings.String_Access renames Options.Runtime;

            GNATstack_Switches : constant Attribute_Pkg_List :=
              Build (Package_Name => "Stack", Attribute_Name => "Switches");

            Project_Switches : GNAT.Strings.String_List_Access;
            --  Arguments extracted from project files

            Path : Virtual_File := Create (+Options.Project.all);

            Obj_Dirs : File_Array_Access;

         begin
            --  Override target and run time attributes if they have been set
            --  from --target and --RTS command line switches.

            Env.Set_Target_And_Runtime
              (Target  => (if Tgt = null then "" else Tgt.all),
               Runtime => (if  Rt = null then "" else Rt.all));

            --  Look for the project file

            if not Path.Is_Regular_File then
               Path := Create (+Options.Project.all & ".gpr");

               if not Path.Is_Regular_File then
                  raise Ada.Text_IO.Name_Error with
                    "Project """ & Options.Project.all & """ not found";
               end if;
            end if;

            Tree.Load (Path, Env);

            --  Get switches from the Stack section in project files

            Project_Switches :=
              Tree.Root_Project.Attribute_Value (GNATstack_Switches);

            if Project_Switches /= null then
               GNAT.Command_Line.Initialize_Option_Scan
                 (Parser, Project_Switches);

               --  There are project options to process

               Project_Opts_Finished := False;
            end if;

            --  Get the 'Object_Dir' attribute value.
            Options.Obj_Dir := Object_Dir (Tree.Root_Project);

            --  Get .ci files from the object directories declared in project
            --  files. Get both object and ALI paths for all imported projects.

            Obj_Dirs := new File_Array'
              (Tree.Root_Project.Object_Path
                 (Recursive => True, Including_Libraries => True));

            for OD of Obj_Dirs.all loop
               Append_Files_From_Directory
                 (Input_Files, OD.Display_Full_Name);
            end loop;

            Unchecked_Free (Obj_Dirs);

            --  Get the .ci files coming from the run-time library. They are
            --  located within the "obj" directory located besides the "adalib"
            --  directory from the runtime.

            for OD of Tree.Root_Project.Get_Environment.Predefined_Object_Path
            loop
               if Is_Directory (Create (+OD.Display_Full_Name & "/../obj"))
               then
                  Append_Files_From_Directory
                    (Input_Files, OD.Display_Full_Name & "/../obj");
               end if;
            end loop;

         exception
            when GNATCOLL.Projects.Invalid_Project =>
               raise GNATCOLL.Projects.Invalid_Project with
                 "Error: invalid project file: '"
                 & Path.Display_Full_Name & "'";
         end;
      end if;
   end Parse_Project_File;

begin
   --  Initialize the environment

   GNATCOLL.Projects.Initialize (Env);
end Project;
