------------------------------------------------------------------------------
--                        STATIC STACK ANALYSIS TOOL                        --
--                                                                          --
--                             D E M A N G L E                              --
--                                                                          --
--                                 B o d y                                  --
--                                                                          --
--                     Copyright (C) 2006-2010, AdaCore                     --
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

--  The information about Ada encodings is extracted from exp_dbug.ads

with GNAT.Regpat;
--  Used for Match

with Interfaces.C.Strings;

package body Demangle is

   use type GNAT.Regpat.Match_Location;

   type String_Access is access all String;

   type Operator_Pair is record
      Source : String_Access;
      Target : String_Access;
   end record;
   --  Type that contains pairs corresponding to encoded operator names (in
   --  the field Source) and their Ada counterpart (in the field Target).

   Conversion_Table : constant array (Positive range <>) of Operator_Pair :=
     (Operator_Pair'(new String'("Oabs"),      new String'("""abs""")),
      Operator_Pair'(new String'("Oand"),      new String'("""and""")),
      Operator_Pair'(new String'("Omod"),      new String'("""mod""")),
      Operator_Pair'(new String'("Onot"),      new String'("""not""")),
      Operator_Pair'(new String'("Oor"),       new String'("""or""")),
      Operator_Pair'(new String'("Orem"),      new String'("""rem""")),
      Operator_Pair'(new String'("Oxor"),      new String'("""xor""")),
      Operator_Pair'(new String'("Oeq"),       new String'("""=""")),
      Operator_Pair'(new String'("One"),       new String'("""/=""")),
      Operator_Pair'(new String'("Olt"),       new String'("""<""")),
      Operator_Pair'(new String'("Ole"),       new String'("""<=""")),
      Operator_Pair'(new String'("Ogt"),       new String'(""">""")),
      Operator_Pair'(new String'("Oge"),       new String'(""">=""")),
      Operator_Pair'(new String'("Oadd"),      new String'("""+""")),
      Operator_Pair'(new String'("Osubtract"), new String'("""-""")),
      Operator_Pair'(new String'("Oconcat"),   new String'("""&""")),
      Operator_Pair'(new String'("Omultiply"), new String'("""*""")),
      Operator_Pair'(new String'("Odivide"),   new String'("""/""")),
      Operator_Pair'(new String'("Oexpon"),    new String'("""**""")));
   --  Table used for translating encoded operator names

   ----------------
   -- Ada_Decode --
   ----------------

   function Ada_Decode (Symbol_Name : String) return String is
      Length : Integer := Symbol_Name'Length;

      Buffer : String (1 .. Length * 2);

      Matches : GNAT.Regpat.Match_Array (0 .. 1);

      Match_Lead_File : GNAT.Regpat.Match_Array (0 .. 1);

      Match_Operator : GNAT.Regpat.Match_Array (0 .. 2);

   begin
      --  Check for encoded indirect calls

      if Symbol_Name = Static_Stack_Analysis.Indirect_Call.all then
         return "*indirect call";
      end if;

      Buffer (1 .. Length) := Symbol_Name;

      --  Remove the leading file information when is there. It may happen
      --  in the case of local (static) subprograms. The file name is
      --  separated by ':' such as "file.ext:symbol_name".

      GNAT.Regpat.Match ("^.*:(.*)$", Buffer (1 .. Length), Match_Lead_File);

      if Match_Lead_File (0) /= GNAT.Regpat.No_Match then
         --  Keep only the local symbol name

         Length := Match_Lead_File (1).Last - Match_Lead_File (1).First + 1;
         Buffer (1 .. Length) :=
           Buffer (Match_Lead_File (1).First .. Match_Lead_File (1).Last);
      end if;

      --  Check for library level subprogram

      if GNAT.Regpat.Match ("^_ada_", Buffer (1 .. Length)) then
         Buffer (1 .. Length - 5) := Buffer (6 .. Length);

         Length := Length - 5;
      end if;

      --  Remove sequence number for symbols generated by the compiler .nn

      GNAT.Regpat.Match ("(\.[0-9]+)$", Buffer (1 .. Length), Matches);

      if Matches (0) /= GNAT.Regpat.No_Match then
         Length := Matches (1).First - 1;
      end if;

      --  Check for task body

      if GNAT.Regpat.Match ("TKB$", Buffer (1 .. Length)) then
         Length := Length - 3;
      elsif GNAT.Regpat.Match ("B$", Buffer (1 .. Length)) then
         Length := Length - 1;
      end if;

      --  Check for body-nested entity: X[bn]

      if GNAT.Regpat.Match ("X$", Buffer (1 .. Length)) then
         Length := Length - 1;
      elsif GNAT.Regpat.Match ("X(b|n)$", Buffer (1 .. Length)) then
         Length := Length - 2;
      end if;

      --  Change instance of TK__ (object declared inside a task) to __

      loop
         GNAT.Regpat.Match ("(TK__)", Buffer (1 .. Length), Matches);
         exit when Matches (0) = GNAT.Regpat.No_Match;

         Buffer (1 .. Length - 2) :=
           Buffer (1 .. Matches (1).First - 1) &
           "__" &
           Buffer (Matches (1).Last + 1 .. Length);

         Length := Length - 2;
      end loop;

      --  Check for overloading: name terminated by $nn or __nn.

      GNAT.Regpat.Match ("(\$[0-9]+)", Buffer (1 .. Length), Matches);

      if Matches (0) /= GNAT.Regpat.No_Match then
         Length := Matches (1).First - 1;
      end if;

      GNAT.Regpat.Match
        ("(__[0-9]+)(_[0-9]+)*$", Buffer (1 .. Length), Matches);

      if Matches (0) /= GNAT.Regpat.No_Match then
         Length := Matches (1).First - 1;
      end if;

      --  Change all "__" to ".". Do not change "__" if it at the beginning
      --  of the symbol name.

      loop
         GNAT.Regpat.Match ("[^\^](__)", Buffer (1 .. Length), Matches);
         exit when Matches (0) = GNAT.Regpat.No_Match;

         Buffer (1 .. Length - 1) :=
           Buffer (1 .. Matches (1).First - 1) &
           "." &
           Buffer (Matches (1).Last + 1 .. Length);

         Length := Length - 1;
      end loop;

      --   Checks for operator names. They appear always after a ".", and they
      --   may be either the last part of the String, such as X.Oconcat (note
      --   that overload markers have already been removed), or before block
      --   information, such as X.Oconcat.B71b._clean.2759.

      for Index in Conversion_Table'Range loop
         GNAT.Regpat.Match
           ("\.(" & Conversion_Table (Index).Source.all & ")($|\.)",
            Buffer (1 .. Length),
            Match_Operator);

         if Match_Operator (0) /= GNAT.Regpat.No_Match then
            declare
               Old_Length : constant Integer := Length;
            begin
               Length := Length -
                 (Conversion_Table (Index).Source.all'Length -
                  Conversion_Table (Index).Target.all'Length);

               Buffer (1 .. Length) :=
                 Buffer (1 .. Match_Operator (1).First - 1) &
               Conversion_Table (Index).Target.all &
               Buffer (Match_Operator (1).Last + 1 .. Old_Length);
            end;

            exit;
         end if;
      end loop;

      --  Return the decoded string

      return Buffer (1 .. Length);
   end Ada_Decode;

   ------------------
   -- Cplus_Decode --
   ------------------

   function Cplus_Decode (Symbol_Name : String) return String is

      function Cplus_Demangle
        (Mangled : Interfaces.C.char_array; Options : Integer)
         return Interfaces.C.Strings.chars_ptr;
      pragma Import (C, Cplus_Demangle, "cplus_demangle");
      --  Function provided by libiberty

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

      File_Regexp : constant String :=
        "((\\\\|[a-zA-Z]:[\\/])?[\w\\/ \.~\-\+]+)" &
        ":" &  -- separator between file name and symbol name
        "([\w\*\&<>\[\]=~\+\-\|!\{\}\$\?/\^]+)$";  --  symbol name
      --  Accepted locations are Unix-style (directories separated by slashes),
      --  Windows UNC-style (drive_letter:\path or \\server\path), and
      --  cygwin-style (drive_letter:/path or /path). There is also .extension
      --  for the file, and file location (:line[:column]). Note that
      --  sometimes, on cygwin, locations have a pattern with mixed / and \,
      --  such as /path\file.ext.

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

      if Is_Ada (File) then
         return Demangle.Ada_Decode
           (Symbol_Name (Name_First .. Symbol_Name'Last));
      else
         --  If not Ada code, try to decode it assuming it is C++

         return Demangle.Cplus_Decode
           (Symbol_Name (Name_First .. Symbol_Name'Last));
      end if;
   end Decode;

   ------------
   -- Is_Ada --
   ------------

   function Is_Ada (File : Static_Stack_Analysis.File_Name) return Boolean is
      use type Static_Stack_Analysis.File_Name;

   begin
      --  Detected very conservatively by simply looking at the file
      --  extension and considering it an Ada source file if its extension
      --  is ".ad?".
      return File /= null
        and then File'Length >= 4
        and then File (File'Last - 3 .. File'Last - 1) = ".ad";
   end Is_Ada;
end Demangle;
