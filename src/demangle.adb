------------------------------------------------------------------------------
--                        STATIC STACK ANALYSIS TOOL                        --
--                                                                          --
--                             D E M A N G L E                              --
--                                                                          --
--                                 B o d y                                  --
--                                                                          --
--                     Copyright (C) 2006-2022, AdaCore                     --
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

--  The information about Ada/C++ encodings is extracted from libiberty

with GNAT.Regpat;

with Interfaces.C.Strings;
with Ada.Directories;
with Ada.Characters.Handling; use Ada.Characters.Handling;
with Ada.Strings.Fixed;       use Ada.Strings.Fixed;

package body Demangle is

   use type GNAT.Regpat.Match_Location;

   -----------------------
   -- Expected patterns --
   -----------------------

   File_Regexp : constant GNAT.Regpat.Pattern_Matcher :=
     GNAT.Regpat.Compile
       ("((\\\\|[a-zA-Z]:[\\/])?[\w\\/ \.~\-\+]+)" &  --  file name
        ":"                                        &  --  separator
        "([\w\*\&<>\[\]=~\+\-\|!\{\}\$\?\./\^]+)$");    --  symbol name
   --  Accepted locations are Unix-style (directories separated by slashes),
   --  Windows UNC-style (drive_letter:\path or \\server\path), and
   --  cygwin-style (drive_letter:/path or /path). There is also .extension
   --  for the file, and file location (:line[:column]). Note that
   --  sometimes, on cygwin, locations have a pattern with mixed / and \,
   --  such as /path\file.ext.

   ----------------
   -- Ada_Decode --
   ----------------

   function Ada_Decode (Symbol_Name : String) return String is
      function Ada_Demangle
        (Mangled : Interfaces.C.char_array)
         return Interfaces.C.Strings.chars_ptr;
      pragma Import (C, Ada_Demangle, "ada_demangle");
      --  Function provided by libiberty to demangle Ada code

      Demangled : Interfaces.C.Strings.chars_ptr;

      use type Interfaces.C.Strings.chars_ptr;

   begin
      --  Try to demangle the symbol name

      Demangled := Ada_Demangle (Interfaces.C.To_C (Symbol_Name));

      if Demangled = Interfaces.C.Strings.Null_Ptr then
         --  Return the symbol name because it could not be demangled

         return Symbol_Name;
      else
         return Interfaces.C.Strings.Value (Demangled);
      end if;
   end Ada_Decode;

   ------------------
   -- Cplus_Decode --
   ------------------

   function Cplus_Decode (Symbol_Name : String) return String is

      function Cplus_Demangle
        (Mangled : Interfaces.C.char_array; Options : Integer)
         return Interfaces.C.Strings.chars_ptr;
      pragma Import (C, Cplus_Demangle, "cplus_demangle");
      --  Function provided by libiberty to demangle C++ code

      DMGL_PARAMS  : constant := 2**0; -- Include function args
      DMGL_ANSI    : constant := 2**1; -- Include const, volatile, etc.
      DMGL_VERBOSE : constant := 2**3; -- Include implementation details

      Options      : constant := DMGL_PARAMS + DMGL_ANSI + DMGL_VERBOSE;
      --  Options from demangle.h

      Demangled : Interfaces.C.Strings.chars_ptr;

      use type Interfaces.C.Strings.chars_ptr;

   begin
      --  Try to demangle the symbol name

      Demangled := Cplus_Demangle (Interfaces.C.To_C (Symbol_Name), Options);

      if Demangled = Interfaces.C.Strings.Null_Ptr then
         --  Return the symbol name because it could not be demangled

         return Symbol_Name;
      else
         return Interfaces.C.Strings.Value (Demangled);
      end if;
   end Cplus_Decode;

   ------------
   -- Decode --
   ------------

   function Decode
     (Symbol_Name : String;
      File : Static_Stack_Analysis.File_Name)
      return String
   is
      Name_First : Integer;
      --  Index to point to the beginning of the subprogram name (removing the
      --  file information).

      Matches : GNAT.Regpat.Match_Array (0 .. 3);

   begin
      --  Remove file information (look for the ":" separator between file
      --  name and subprogram name).

      GNAT.Regpat.Match (File_Regexp, Symbol_Name, Matches);

      if Matches (0) /= GNAT.Regpat.No_Match then
         pragma Assert (Matches (3) /= GNAT.Regpat.No_Match);

         Name_First := Matches (3).First;
      else
         Name_First := Symbol_Name'First;
      end if;

      if Is_Ada (File, Symbol_Name) then
         return Ada_Decode (Symbol_Name (Name_First .. Symbol_Name'Last));
      else
         --  If not Ada code, try to decode it assuming it is C++

         return Cplus_Decode (Symbol_Name (Name_First .. Symbol_Name'Last));
      end if;
   end Decode;

   ------------
   -- Is_Ada --
   ------------

   function Is_Ada
     (File        : Static_Stack_Analysis.File_Name;
      Symbol_Name : String := "")
      return Boolean
   is
      Matches : GNAT.Regpat.Match_Array (0 .. 3);

   begin
      --  Symbol names for static C subprograms contain the file name (like
      --  /path/file.c:func), so this is used as a first criterion to determine
      --  whether it comes from a C file.

      --  Look for the ":" separator between file name and subprogram name

      GNAT.Regpat.Match (File_Regexp, Symbol_Name, Matches);

      if Matches (0) /= GNAT.Regpat.No_Match and then
        Tail (Symbol_Name (Matches (1).First .. Matches (1).Last), 2) = ".c"
      then
         return False;

      --  Detected very conservatively by simply looking at the file extension
      --  and considering it an Ada source file if it is not a C source file.
      else
         declare
            use type Static_Stack_Analysis.File_Name;

            File_Extension : constant String :=
              (if File = null then ""
               else Ada.Directories.Extension (File.all));

         begin
            return File_Extension'Length < 1 or else
              To_Lower (File_Extension (File_Extension'First)) /= 'c';
         end;
      end if;
   end Is_Ada;
end Demangle;
