------------------------------------------------------------------------------
--                        STATIC STACK ANALYSIS TOOL                        --
--                                                                          --
--                              O P T I O N S                               --
--                                                                          --
--                                 S p e c                                  --
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

with GNAT.Strings;
--  Used for String_Access

package Options is

   Verbose : Boolean := False;
   --  Verbose output

   Explore_All : Boolean := False;
   --  Compute worst case stack usage for every node in the partition

   List_Of_Entry_Points : GNAT.Strings.String_Access := null;
   --  List of entry points to be analyzed

   Output_File : GNAT.Strings.String_Access := null;
   --  Name of the generated call graph file

   Default_Unknown : Natural := 200;
   --  Value used (in bytes) when there is no information about stack usage
   --  for a given subprogram.

   Default_Unbounded : Natural := 100;
   --  Value used (in bytes) when there is an unbounded stack allocation for
   --  a given subprogram.

end Options;
