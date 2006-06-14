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

   function "+" (Left, Right : Stack_Usage_Info) return Stack_Usage_Info is
   begin
      return (Stack_Usage'Max (Left.Frame_Type, Right.Frame_Type),
              Left.Static_Usage + Right.Static_Usage,
              Left.Dynamic_Usage + Right.Dynamic_Usage,
              Left.Unknown_Usage + Right.Unknown_Usage);
   end "+";

   ---------
   -- "<" --
   ---------

   function "<" (Left, Right : Stack_Usage_Info) return Boolean is
   begin
      return Left.Static_Usage + Left.Dynamic_Usage + Left.Unknown_Usage <
             Right.Static_Usage + Right.Dynamic_Usage + Right.Unknown_Usage;
   end "<";

   function "<" (Left, Right : Node_Class_Access) return Boolean is
   begin
      --  Compare the associated symbol names

      return Get_Subprogram_Name (Left.all).all <
        Get_Subprogram_Name (Right.all).all;
   end "<";

   function "<" (Left, Right : Location) return Boolean is
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

      return Node_Keys.Find (List_Of_Subprograms, Subprogram);
   end Get_Node;

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
      return Unknown_Stack_Usage;
   end Get_Stack_Usage;

   function Get_Stack_Usage
     (Target : Unresolved_Node) return Stack_Usage_Info is
      pragma Unreferenced (Target);
   begin
      return Stack_Usage_Info'
        (Frame_Type    => Unknown,
         Static_Usage  => 0,
         Dynamic_Usage => 0,
         Unknown_Usage => Frame_Size (Options.Default_Unknown));
   end Get_Stack_Usage;

   -------------------------
   -- Get_Subprogram_Name --
   -------------------------

   function Get_Subprogram_Name
     (Target : Real_Node) return Subprogram_Name is
   begin
      return Target.Subprogram;
   end Get_Subprogram_Name;

   function Get_Subprogram_Name
     (Target : Fake_Node) return Subprogram_Name is
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

      elsif
        Target.Stack_Info.Frame_Type = Stack_Usage.Frame_Type then
         --  Both values have the same amount of information so we take the
         --  worst case.

         Target.Stack_Info.Static_Usage := Frame_Size'Max
           (Target.Stack_Info.Static_Usage, Stack_Usage.Static_Usage);

         Target.Stack_Info.Dynamic_Usage := Frame_Size'Max
           (Target.Stack_Info.Dynamic_Usage, Stack_Usage.Dynamic_Usage);

         Target.Stack_Info.Unknown_Usage := Frame_Size'Max
           (Target.Stack_Info.Unknown_Usage, Stack_Usage.Unknown_Usage);
      end if;

   end Update_Stack_Usage;

end Static_Stack_Analysis;
