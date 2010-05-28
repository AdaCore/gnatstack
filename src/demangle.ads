------------------------------------------------------------------------------
--                        STATIC STACK ANALYSIS TOOL                        --
--                                                                          --
--                             D E M A N G L E                              --
--                                                                          --
--                                 S p e c                                  --
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

with Static_Stack_Analysis;

package Demangle is
   function Ada_Decode (Symbol_Name : String) return String;
   --  Return the Ada name from the encoded form. It transforms a symbol name
   --  (such as pck__proc) into its Ada counterpart (pck.proc). It also
   --  handles library level subprogram, overloaded subprograms, task bodies,
   --  and operators.

   function Cplus_Decode (Symbol_Name : String) return String;
   --  Return the demangled name corresponding to the symbol name for C++. It
   --  transforms a symbol name (such as _Z4proci) into its corresponding C++
   --  (proc(int)).

   function Is_Ada (File : Static_Stack_Analysis.File_Name) return Boolean;
   --  This function returns True if the node represents an Ada subprogram

   function Decode
     (Symbol_Name : String;
      File : Static_Stack_Analysis.File_Name)
      return String;
   --  Return the Ada/C++ name from the encoded form
end Demangle;
