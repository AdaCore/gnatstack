------------------------------------------------------------------------------
--                        STATIC STACK ANALYSIS TOOL                        --
--                                                                          --
--                 S T A T I C _ S T A C K _ A N A L Y S I S                --
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

with Global_Data;
--  Used for List_Of_Subprograms

with Options;
--  Used for Default_Unknown

package body Static_Stack_Analysis is

   -----------
   -- Local --
   -----------

   function Key (Element : Node_Class_Access) return String;
   --  Returns the name of the subprogram associated to the specified node

   package Node_Keys is new List_Of_Nodes.Generic_Keys (String, Key);
   --  Package used to find a subprogram by its symbol name

   ---------
   -- "+" --
   ---------

   function "+" (Left, Right : Frame_Size) return Frame_Size is
      function Normalize (Stack_Usage : Frame_Size) return Integer;
      --  Function for removing No_Value

      function Normalize (Stack_Usage : Frame_Size) return Integer is
      begin
         return Integer'Max (Integer (Stack_Usage), 0);
      end Normalize;

   begin
      return Frame_Size (Normalize (Left) + Normalize (Right));
   end "+";

   function "+" (Left, Right : Stack_Usage_Info) return Stack_Usage_Info is
      function Local_Add (Left, Right : Frame_Size) return Frame_Size;
      --  Function for adding the different fields fo Stack_Usage_Info. It is
      --  different from the normal addition because we want to keep the
      --  No_Value.

      function Local_Add (Left, Right : Frame_Size) return Frame_Size is
      begin
         if Left = No_Value then
            return Right;
         elsif Right = No_Value then
            return Left;
         else
            return Left + Right;
         end if;
      end Local_Add;

   begin
      return Stack_Usage_Info'
        (Frame_Type    => Stack_Usage'Max (Left.Frame_Type, Right.Frame_Type),
         Static_Usage  => Local_Add (Left.Static_Usage, Right.Static_Usage),
         Dynamic_Usage => Local_Add (Left.Dynamic_Usage, Right.Dynamic_Usage),
         Unknown_Usage => Local_Add (Left.Unknown_Usage, Right.Unknown_Usage),
         Cycle_Usage   => Local_Add (Left.Cycle_Usage, Right.Cycle_Usage));
   end "+";

   ---------
   -- "<" --
   ---------

   function "<" (Left, Right : Stack_Usage_Info) return Boolean is
   begin
      return Left.Static_Usage + Left.Dynamic_Usage +
             Left.Unknown_Usage + Left.Cycle_Usage <
             Right.Static_Usage + Right.Dynamic_Usage +
             Right.Unknown_Usage + Right.Cycle_Usage;
   end "<";

   ---------
   -- "=" --
   ---------

   function "=" (Left, Right : Location) return Boolean is
   begin
      return ((Left.File = null and then Right.File = null)
                or else (Left.File /= null
                  and then Right.File /= null
                  and then Left.File.all = Right.File.all))
        and then ((Left.Demangled = null and then Right.Demangled = null)
                    or else (Left.Demangled /= null
                      and then Right.Demangled /= null
                      and then Left.Demangled.all = Right.Demangled.all))
        and then Left.Line_Number = Right.Line_Number
        and then Left.Column_Number = Right.Column_Number;
   end "=";

   function "=" (Left, Right : Node_Id) return Boolean is
   begin
      return Static_Stack_Analysis.List_Of_Nodes.Has_Element (Left)
        and then  Static_Stack_Analysis.List_Of_Nodes.Has_Element (Right)
        and then Static_Stack_Analysis.List_Of_Nodes.Element (Left) =
                 Static_Stack_Analysis.List_Of_Nodes.Element (Right);
   end "=";

   ------------------------
   -- Alphabetical_Order --
   ------------------------

   function Alphabetical_Order (Left, Right : Location) return Boolean is
   begin
      return Left.File.all < Right.File.all
        or else (Left.File.all = Right.File.all
                   and then Left.Demangled.all < Right.Demangled.all)
        or else (Left.File.all = Right.File.all
                   and then Left.Demangled.all = Right.Demangled.all
                   and then Left.Line_Number < Right.Line_Number)
        or else (Left.File.all = Right.File.all
                   and then Left.Demangled.all = Right.Demangled.all
                   and then Left.Line_Number = Right.Line_Number
                   and then Left.Column_Number < Right.Column_Number);
   end Alphabetical_Order;

   function Alphabetical_Order
     (Left, Right : Node_Class_Access) return Boolean is
   begin
      return Get_Subprogram_Name (Left.all).all <
        Get_Subprogram_Name (Right.all).all;
   end Alphabetical_Order;

   -----------
   -- Equal --
   -----------

   function Equal (Left, Right : Node_Class_Access) return Boolean is
   begin
      return (Left = null and then Right = null)
        or else (Left /= null
                 and then Right /= null
                 and then Left.all = Right.all);
   end Equal;

   ---------------------------------
   -- Get_Accumulated_Stack_Usage --
   ---------------------------------

   function Get_Accumulated_Stack_Usage
     (Target : Node) return Stack_Usage_Info is
   begin
      return Target.Accumulated_Stack_Usage;
   end Get_Accumulated_Stack_Usage;

   -------------------------
   -- Get_Dynamic_Objects --
   -------------------------

   function Get_Dynamic_Objects
     (Target : Explicit_Node) return List_Of_Locations.Set is
   begin
      return Target.Dynamic_Objects;
   end Get_Dynamic_Objects;

   function Get_Dynamic_Objects
     (Target : Unresolved_Node) return List_Of_Locations.Set is
      pragma Unreferenced (Target);
   begin
      return List_Of_Locations.Empty_Set;
   end Get_Dynamic_Objects;

   function Get_Dynamic_Objects
     (Target : Fake_Node) return List_Of_Locations.Set is
      pragma Unreferenced (Target);
   begin
      return List_Of_Locations.Empty_Set;
   end Get_Dynamic_Objects;

   -----------------------
   -- Get_Location_List --
   -----------------------

   function Get_Location_List
     (Target : Real_Node) return List_Of_Locations.Set is
   begin
      return Target.Location_List;
   end Get_Location_List;

   function Get_Location_List
     (Target : Fake_Node) return List_Of_Locations.Set is
      pragma Unreferenced (Target);
   begin
      return List_Of_Locations.Empty_Set;
   end Get_Location_List;

   --------------
   -- Get_Node --
   --------------

   function Get_Node (Subprogram : String) return Node_Id is
   begin
      --  Use the symbol name as the key to find in the list

      return Node_Keys.Find (Global_Data.List_Of_Subprograms, Subprogram);
   end Get_Node;

   ---------------------
   -- Get_Stack_Usage --
   ---------------------

   function Get_Stack_Usage
     (Target : Explicit_Node) return Stack_Usage_Info is
   begin
      if Static_Stack_Analysis.List_Of_Cycles.Is_Empty (Target.Cycles) then
         return Target.Stack_Info;

      else
         --  ??? It simply indicates that there is a cycle, but we need to
         --  find the way for accounting the stack requirements imposed by
         --  the cycles.

         return Stack_Usage_Info'
           (Frame_Type    => Target.Stack_Info.Frame_Type,
            Static_Usage  => Target.Stack_Info.Static_Usage,
            Dynamic_Usage => Target.Stack_Info.Dynamic_Usage,
            Unknown_Usage => Target.Stack_Info.Unknown_Usage,
            Cycle_Usage   => 0);
      end if;
   end Get_Stack_Usage;

   function Get_Stack_Usage
     (Target : Fake_Node) return Stack_Usage_Info is
      pragma Unreferenced (Target);
   begin
      return Stack_Usage_Info'
        (Frame_Type    => Unknown,
         Static_Usage  => No_Value,
         Dynamic_Usage => No_Value,
         Unknown_Usage => Frame_Size (Options.Default_Unknown),
         Cycle_Usage   => No_Value);
   end Get_Stack_Usage;

   function Get_Stack_Usage
     (Target : Unresolved_Node) return Stack_Usage_Info is
      pragma Unreferenced (Target);
   begin
      return Stack_Usage_Info'
        (Frame_Type    => Unknown,
         Static_Usage  => No_Value,
         Dynamic_Usage => No_Value,
         Unknown_Usage => Frame_Size (Options.Default_Unknown),
         Cycle_Usage   => No_Value);
   end Get_Stack_Usage;

   -------------------------
   -- Get_Subprogram_Name --
   -------------------------

   function Get_Subprogram_Name
     (Target : Real_Node) return Name is
   begin
      return Target.Subprogram;
   end Get_Subprogram_Name;

   function Get_Subprogram_Name
     (Target : Fake_Node) return Name is
      pragma Unreferenced (Target);
   begin
      return Indirect_Call;
   end Get_Subprogram_Name;

   ---------
   -- Key --
   ---------

   function Key (Element : Node_Class_Access) return String is
   begin
      return Get_Subprogram_Name (Element.all).all;
   end Key;

   -----------------------
   -- Stack_Usage_Order --
   -----------------------

   function Stack_Usage_Order
     (Left, Right : Node_Class_Access) return Boolean is
   begin
      return Get_Accumulated_Stack_Usage (Right.all) <
             Get_Accumulated_Stack_Usage (Left.all);
   end Stack_Usage_Order;

   function Stack_Usage_Order (Left, Right : Node_Id) return Boolean is
   begin
      return Stack_Usage_Order
        (List_Of_Nodes.Element (Left), List_Of_Nodes.Element (Right));
   end Stack_Usage_Order;

   function Stack_Usage_Order (Left, Right : Edge) return Boolean is
   begin
      --  Compare the weigth of the subprograms to wich we are pointing to

      return Stack_Usage_Order (Left.Target, Right.Target);
   end Stack_Usage_Order;

   ------------------------
   -- Update_Stack_Usage --
   ------------------------

   procedure Update_Stack_Usage
     (Target : in out Explicit_Node; Stack_Usage : Stack_Usage_Info) is
   begin
      --  Values in Frame_Type are ordered by uncertainty so we take the
      --  data with more information (less uncertainty).

      if Target.Stack_Info.Frame_Type > Stack_Usage.Frame_Type then
         Target.Stack_Info := Stack_Usage;

      elsif Target.Stack_Info.Frame_Type = Stack_Usage.Frame_Type then
         --  Both values have the same amount of information so we take the
         --  worst case.

         Target.Stack_Info.Static_Usage := Frame_Size'Max
           (Target.Stack_Info.Static_Usage, Stack_Usage.Static_Usage);

         Target.Stack_Info.Dynamic_Usage := Frame_Size'Max
           (Target.Stack_Info.Dynamic_Usage, Stack_Usage.Dynamic_Usage);

         --  There cannot an unknown part for a explicit node

         Target.Stack_Info.Unknown_Usage := No_Value;

         Target.Stack_Info.Cycle_Usage := Frame_Size'Max
           (Target.Stack_Info.Cycle_Usage, Stack_Usage.Cycle_Usage);
      end if;

   end Update_Stack_Usage;

end Static_Stack_Analysis;
