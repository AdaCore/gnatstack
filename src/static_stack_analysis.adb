------------------------------------------------------------------------------
--                        STATIC STACK ANALYSIS TOOL                        --
--                                                                          --
--                 S T A T I C _ S T A C K _ A N A L Y S I S                --
--                                                                          --
--                                 B o d y                                  --
--                                                                          --
--                     Copyright (C) 2005-2010, AdaCore                     --
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

with Ada.Characters.Handling;

with Global_Data;
with Options;

package body Static_Stack_Analysis is

   -----------
   -- Local --
   -----------

   function Node_Key (Element : Node_Class_Access) return String;
   --  Returns the name of the subprogram associated to the specified node

   package Node_Keys is new
     List_Of_Nodes.Generic_Keys (String, Node_Key);
   --  Package used to find a subprogram by its symbol name

   function Subprogram_Key (Element : Node_Class_Access) return String;
   --  Returns the name of the subprogram associated to the specified node
   --  in lower case.

   package Subprogram_Keys is new
     List_Of_Nodes.Generic_Keys (String, Subprogram_Key);
   --  Package used to find a subprogram by its symbol name

   function Demangled_Key (Element : Node_Class_Access) return String;
   --  Returns the demangled name of the subprogram associated to the
   --  specified node in lower case.

   package Demangled_Keys is new
     List_Of_Nodes.Generic_Keys (String, Demangled_Key);
   --  Package used to find a subprogram by its demangled name

   function Class_Name_Key (Element : Class_Access) return String;
   --  Returns the mangled name of the class

   package Class_Keys is new
     List_Of_Classes.Generic_Keys (String, Class_Name_Key);
   --  Package used to find a class by its mangled name

   function Vtable_Key (Element : Virtual_Class_Access) return Vtable_Loc;
   --  Returns the pair class:slot of the method

   package Method_Keys is new
     List_Of_Virtual_Methods.Generic_Keys (Vtable_Loc, Vtable_Key);
   --  Package used to find a method by its pair class:slot

   ---------
   -- "+" --
   ---------

   function "+" (Left, Right : Frame_Size) return Frame_Size is
      function Normalize (Stack_Usage : Frame_Size) return Integer;
      --  Function for removing Empty_Value and Unspecified_Value

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
      --  Empty_Value and Unspecified_Value.

      function Local_Add (Left, Right : Frame_Size) return Frame_Size is
      begin
         if Left = Empty_Value then
            return Right;
         elsif Right = Empty_Value then
            return Left;
         elsif Left = Unspecified_Value or else Right = Unspecified_Value then
            return Unspecified_Value;
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

   function "<" (Left, Right : Vtable_Loc) return Boolean is
   begin
      if Left.Class = null then
         return Right.Class /= null;

      elsif Right.Class = null then
         return False;

      elsif Left.Class.Class_Name = null then
         return Right.Class.Class_Name /= null;

      elsif Right.Class.Class_Name = null then
         return False;

      --  Order by the name of the class defining the method

      elsif Left.Class.Class_Name.all /= Right.Class.Class_Name.all then
         return Left.Class.Class_Name.all < Right.Class.Class_Name.all;

      --  For methods defined by the same class, we use the slot number to
      --  determine the order.

      else
         return Left.Slot < Right.Slot;
      end if;
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

   function "=" (Left, Right : Cycle) return Boolean is
      Left_Index  : Paths.Cursor := Left.Path.First;
      Right_Index : Paths.Cursor := Right.Path.First;

      use type Ada.Containers.Count_Type;

   begin
      if Left.Path.Length = Right.Path.Length then
         while Paths.Has_Element (Left_Index)
           and then Paths.Has_Element (Right_Index)
           and then Paths.Element (Left_Index) = Paths.Element (Right_Index)
         loop
            Paths.Next (Left_Index);
            Paths.Next (Right_Index);
         end loop;

         --  If we have reached the end of both paths and all elements are
         --  the same then the paths are exactly the same.

         return (not Paths.Has_Element (Left_Index) and then
                 not Paths.Has_Element (Right_Index));
      else
         return False;
      end if;
   end "=";

   ------------------------
   -- Alphabetical_Order --
   ------------------------

   function Alphabetical_Order (Left, Right : Location) return Boolean is
   begin
      --  Compare first the file name, then the subprogram name, and finally
      --  the line number.

      if Left.File = null then
         return Right.File /= null;

      elsif Right.File = null then
         return False;

      elsif Left.File.all /= Right.File.all then
         return Left.File.all < Right.File.all;

      elsif Left.Demangled = null and then Right.Demangled /= null then
         return True;

      elsif Right.Demangled = null then
         return False;

      elsif Left.Demangled.all /= Right.Demangled.all then
         return Left.Demangled.all < Right.Demangled.all;

      else
         return Left.Line_Number < Right.Line_Number;
      end if;
   end Alphabetical_Order;

   function Alphabetical_Order
     (Left, Right : Node_Class_Access) return Boolean is
   begin
      if Left = null then
         return Right /= null;

      elsif Right = null then
         return False;

      else
         return Get_Subprogram_Name (Left.all).all <
           Get_Subprogram_Name (Right.all).all;
      end if;
   end Alphabetical_Order;

   function Alphabetical_Order (Left, Right : Cycle) return Boolean is
      Left_Index  : Paths.Cursor := Left.Path.First;
      Right_Index : Paths.Cursor := Right.Path.First;
   begin
      --  Look for the first different subprogram

      while Paths.Has_Element (Left_Index)
        and then Paths.Has_Element (Right_Index)
        and then Paths.Element (Left_Index).Source_Node =
                 Paths.Element (Right_Index).Source_Node
      loop
         Static_Stack_Analysis.Paths.Next (Left_Index);
         Static_Stack_Analysis.Paths.Next (Right_Index);
      end loop;

      if not Paths.Has_Element (Left_Index) then
         return Paths.Has_Element (Right_Index);

      elsif not Paths.Has_Element (Right_Index) then
         return False;

      --  Compare the subprogram names
      else
         return Alphabetical_Order
           (List_Of_Nodes.Element (Paths.Element (Left_Index).Source_Node),
            List_Of_Nodes.Element (Paths.Element (Right_Index).Source_Node));
      end if;
   end Alphabetical_Order;

   function Alphabetical_Order (Left, Right : Class_Access) return Boolean is
   begin
      if Left = null then
         return Right /= null;

      elsif Right = null then
         return False;

      else
         return Left.Class_Name.all < Right.Class_Name.all;
      end if;
   end Alphabetical_Order;

   function Alphabetical_Order
     (Left, Right : Virtual_Class_Access) return Boolean is
   begin
      if Left = null then
         return Right /= null;

      elsif Right = null then
         return False;

      --  Use the class:slot pair for ordering

      else
         return Left.Vtable_Entry < Right.Vtable_Entry;
      end if;
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

   function Equal (Left, Right : Path_Element) return Boolean is
      use type Node_Id;
      use type Edge_Id;

   begin
      return Left.Source_Node = Right.Source_Node
        and then Left.Call_To = Right.Call_To;
   end Equal;

   function Equal (Left, Right : Class_Access) return Boolean is
   begin
      return (Left = null and then Right = null)
        or else (Left /= null
                 and then Right /= null
                 and then Left.all = Right.all);
   end Equal;

   function Equal (Left, Right : Virtual_Class_Access) return Boolean is
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

   ---------------
   -- Get_Class --
   ---------------

   function Get_Class (Class_Name : String) return Class_Access is
   begin
      --  Use the mangled name as the key to find in the list

      if Class_Keys.Contains (Global_Data.List_Of_Classes, Class_Name) then
         return Class_Keys.Element
           (Global_Data.List_Of_Classes, Class_Name);
      else
         return null;
      end if;
   end Get_Class;

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

   ------------------------
   -- Get_Indirect_Calls --
   ------------------------

   function Get_Indirect_Calls
     (Target : Explicit_Node) return List_Of_Locations.Set
   is
      List_Of_Indirect_Calls : List_Of_Locations.Set :=
        List_Of_Locations.Empty_Set;

      procedure Extract_Indirect_Calls (Position : Edge_Id);
      --  If the referenced call is an indirect call then insert its location
      --  within the set to be returned.

      procedure Extract_Indirect_Calls (Position : Edge_Id) is
         Call : constant Edge := List_Of_Edges.Element (Position);

      begin
         if List_Of_Nodes.Element (Call.Target).all in Fake_Node'Class then
            List_Of_Indirect_Calls.Union (Call.Point_Of_Call);
         end if;
      end Extract_Indirect_Calls;

   begin
      Target.Target_Calls.Iterate (Extract_Indirect_Calls'Access);
      return List_Of_Indirect_Calls;
   end Get_Indirect_Calls;

   function Get_Indirect_Calls
     (Target : Unresolved_Node) return List_Of_Locations.Set is
      pragma Unreferenced (Target);
   begin
      return List_Of_Locations.Empty_Set;
   end Get_Indirect_Calls;

   function Get_Indirect_Calls
     (Target : Fake_Node) return List_Of_Locations.Set is
      pragma Unreferenced (Target);
   begin
      return List_Of_Locations.Empty_Set;
   end Get_Indirect_Calls;

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

   ---------------
   -- Get_Match --
   ---------------

   function Get_Match (Subprogram : String) return Node_Id is
      Found : Node_Id;

   begin
      --  Use the symbol name as the key to find in the list

      Found :=
        Subprogram_Keys.Find
          (Global_Data.List_Of_Subprograms,
           Ada.Characters.Handling.To_Lower (Subprogram));

      if List_Of_Nodes.Has_Element (Found) then
         return Found;

      else
         --  Try to match the demangled name

         return
           Demangled_Keys.Find
             (Global_Data.List_Of_Subprograms,
              Ada.Characters.Handling.To_Lower (Subprogram));
      end if;
   end Get_Match;

   ---------------
   -- Get_Method --
   ---------------

   function Get_Method (Id : Vtable_Loc) return Virtual_Class_Access is
   begin
      --  Use the class:slot pair as the key to find in the list

      if Method_Keys.Contains (Global_Data.List_Of_Methods, Id) then
         return Method_Keys.Element (Global_Data.List_Of_Methods, Id);
      else
         return null;
      end if;
   end Get_Method;

   ---------------------
   -- Get_Stack_Usage --
   ---------------------

   function Get_Stack_Usage
     (Target : Explicit_Node) return Stack_Usage_Info is
   begin
      return Target.Stack_Info;
   end Get_Stack_Usage;

   function Get_Stack_Usage
     (Target : Fake_Node) return Stack_Usage_Info is
      pragma Unreferenced (Target);
   begin
      return Stack_Usage_Info'
        (Frame_Type    => Unknown,
         Static_Usage  => Empty_Value,
         Dynamic_Usage => Empty_Value,
         Unknown_Usage => Frame_Size (Options.Default_Unknown),
         Cycle_Usage   => Empty_Value);
   end Get_Stack_Usage;

   function Get_Stack_Usage
     (Target : Unresolved_Node) return Stack_Usage_Info is
      pragma Unreferenced (Target);
   begin
      return Stack_Usage_Info'
        (Frame_Type    => Unknown,
         Static_Usage  => Empty_Value,
         Dynamic_Usage => Empty_Value,
         Unknown_Usage => Frame_Size (Options.Default_Unknown),
         Cycle_Usage   => Empty_Value);
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

   ------------------------
   -- Get_Demangled_Name --
   ------------------------

   function Get_Demangled_Name
     (Target : Real_Node) return Name is
   begin
      return Target.Demangled;
   end Get_Demangled_Name;

   function Get_Demangled_Name
     (Target : Fake_Node) return Name is
      pragma Unreferenced (Target);
   begin
      return Indirect_Call;
   end Get_Demangled_Name;

   ------------------
   -- Insert_Class --
   ------------------

   function Insert_Class
     (Symbol : String; Defined : Boolean; Loc : Location := Null_Location)
      return Class_Access
   is
      This_Class : Class_Access := Get_Class (Symbol);

   begin
      if This_Class = null then
         --  Create the object to store the class information

         This_Class := new Class'
           (Class_Name => new String'(Symbol),
            Class_Loc  => Loc,
            Parents    => List_Of_Classes.Empty_Set,
            Derived    => List_Of_Classes.Empty_Set,
            Virtual    => List_Of_Virtual_Methods.Empty_Set,
            Inherited  => List_Of_Inherited_Methods.Empty_Vector);

         --  Insert in the list

         List_Of_Classes.Insert
           (Global_Data.List_Of_Classes, This_Class);

      else
         --  The class has already been registered. If the class in being
         --  defined now (Defined = True) then it should contain only the
         --  class name information, and the location must either be null
         --  or the same as we are inserting.

         pragma Assert
           (not Defined or else
              (This_Class.Class_Name.all = Symbol and then
                 (This_Class.Class_Loc = Null_Location or else
                  This_Class.Class_Loc = Loc)));

         --  Update the location if needed

         if This_Class.Class_Loc = Null_Location then
            This_Class.Class_Loc := Loc;
         end if;

      end if;

      return This_Class;
   end Insert_Class;

   -------------------
   -- Insert_Method --
   -------------------

   function Insert_Method
     (Id : Vtable_Loc; Symbol : String) return Virtual_Class_Access
   is
      Method : Virtual_Class_Access := Get_Method (Id);

   begin
      if Method = null then
         --  The method is not yet in the list so we create it

         Method := new Virtual'
           (Method_Name  => null,
            Dispatcher   => null,
            Symbol_Name  => new String'(Symbol),
            Vtable_Entry => Id,
            Redefines    => Null_Vtable_Loc,
            Redefined_By => List_Of_Virtual_Methods.Empty_Set);

         --  Insert in the list

         List_Of_Virtual_Methods.Insert
           (Global_Data.List_Of_Methods, Method);

      else
         --  The method has already been registered. It should contain
         --  at least the owner class and slot number. The symbol name must be
         --  either void or the same as we are inserting.

         pragma Assert
           (Method.Vtable_Entry = Id and then
              (Method.Symbol_Name = null or else
               Method.Symbol_Name.all = Symbol));

         --  Update the symbol name if needed

         if Method.Symbol_Name = null then
            Method.Symbol_Name := new String'(Symbol);
         end if;

      end if;

      return Method;
   end Insert_Method;

   --------------
   -- Node_Key --
   --------------

   function Node_Key (Element : Node_Class_Access) return String is
   begin
      --  We avoid the problem of upper/lower case by transforming into lower
      --  case values.

      return Get_Subprogram_Name (Element.all).all;
   end Node_Key;

   --------------------
   -- Subprogram_Key --
   --------------------

   function Subprogram_Key (Element : Node_Class_Access) return String is
   begin
      --  We avoid the problem of upper/lower case by transforming into lower
      --  case values.

      return Ada.Characters.Handling.To_Lower
        (Get_Subprogram_Name (Element.all).all);
   end Subprogram_Key;

   -------------------
   -- Demangled_Key --
   -------------------

   function Demangled_Key (Element : Node_Class_Access) return String is
   begin
      --  We avoid the problem of upper/lower case by transforming into lower
      --  case values.

      return Ada.Characters.Handling.To_Lower
        (Get_Demangled_Name (Element.all).all);
   end Demangled_Key;

   --------------------
   -- Class_Name_Key --
   --------------------

   function Class_Name_Key (Element : Class_Access) return String is
   begin
      return Element.Class_Name.all;
   end Class_Name_Key;

   ----------------
   -- Vtable_Key --
   ----------------

   function Vtable_Key (Element : Virtual_Class_Access) return Vtable_Loc is
   begin
      return Element.Vtable_Entry;
   end Vtable_Key;

   ---------------
   -- Normalize --
   ---------------

   procedure Normalize (Target : Cycle) is
      The_First  : Paths.Cursor := Target.Path.First;
      Index      : Paths.Cursor := Paths.Next (The_First);

      First_Name : Name :=
        Get_Subprogram_Name
          (List_Of_Nodes.Element (Paths.Element (The_First).Source_Node).all);
      Index_Name : Name := null;

      Counter : Ada.Containers.Count_Type;

      use type Paths.Cursor;
      use type Ada.Containers.Count_Type;

   begin
      --  Look for the first in alphabetical order

      while Paths.Has_Element (Index) loop

         Index_Name :=
           Get_Subprogram_Name
             (List_Of_Nodes.Element (Paths.Element (Index).Source_Node).all);

         if Index_Name.all < First_Name.all then
            The_First := Index;
            First_Name := Index_Name;
         end if;

         Paths.Next (Index);
      end loop;

      --  Rearrange the list.

      --  Move the item in the first position to the last

      Index := Target.Path.First;
      Counter := 0;

      while Index /= The_First loop
         Target.Path.Append (Paths.Element (Index));
         Counter := Counter + 1;
         Paths.Next (Index);
      end loop;

      --  Remove those that have been relocated

      Target.Path.Delete_First (Counter);
   end Normalize;

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

         Target.Stack_Info.Unknown_Usage := Frame_Size'Max
           (Target.Stack_Info.Unknown_Usage, Stack_Usage.Unknown_Usage);

         Target.Stack_Info.Cycle_Usage := Frame_Size'Max
           (Target.Stack_Info.Cycle_Usage, Stack_Usage.Cycle_Usage);
      end if;

   end Update_Stack_Usage;

end Static_Stack_Analysis;
