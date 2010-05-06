------------------------------------------------------------------------------
--                        STATIC STACK ANALYSIS TOOL                        --
--                                                                          --
--                      D I S P A T C H I N G _ C A L L S                   --
--                                                                          --
--                                 B o d y                                  --
--                                                                          --
--                        Copyright (C) 2010, AdaCore                       --
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

with Global_Data;
with Demangle;
with Static_Stack_Analysis; use Static_Stack_Analysis;

package body Dispatching_Calls is

   -----------------------
   -- Local Subprograms --
   -----------------------

   function Get_Overriding_Methods
     (Node : Dispatching_Node) return List_Of_Edges.Vector;
   --  This function returns the list of potential targets for a dispatching
   --  call. The dispatching call is specified using the index in a vtable
   --  used for dispatch, the type whose vtable is used, and the static type
   --  of the expression.

   procedure Propagate_Derived_Classes
     (Position : Static_Stack_Analysis.List_Of_Classes.Cursor);
   --  Include in the traversed classes the list of descendent

   procedure Propagate_Overloaded_Methods
     (Position : Static_Stack_Analysis.List_Of_Virtual_Methods.Cursor);
   --  Include in the traversed methods the list of methods which overload them

   ------------------------------
   -- Create_Class_Hierarchies --
   ------------------------------

   procedure Create_Class_Hierarchies is
   begin
      --  Iterate over all the classes

      Static_Stack_Analysis.List_Of_Classes.Iterate
        (Global_Data.List_Of_Classes, Propagate_Derived_Classes'Access);
   end Create_Class_Hierarchies;

   -------------------------------
   -- Create_Method_Hierarchies --
   -------------------------------

   procedure Create_Method_Hierarchies is
   begin
      --  Iterate over all the methods

      Static_Stack_Analysis.List_Of_Virtual_Methods.Iterate
        (Global_Data.List_Of_Methods, Propagate_Overloaded_Methods'Access);
   end Create_Method_Hierarchies;

   ----------------------------
   -- Get_Overriding_Methods --
   ----------------------------

   function Get_Overriding_Methods
     (Node : Dispatching_Node) return List_Of_Edges.Vector
   is
      Result : List_Of_Edges.Vector := List_Of_Edges.Empty_Vector;

      Base_Method : constant Virtual_Class_Access :=
        Get_Method (Vtable_Loc'(Node.Base_Class, Node.Slot));

      Base_Method_Name : Name;

      Method_Subprogram : Node_Id;
      Target_Ptr        : Node_Class_Access;

      Static_Class : Class_Access renames Node.Static_Class;

      Inserted : Boolean;

      procedure Add_To_Potential_Targets
        (Position : Static_Stack_Analysis.List_Of_Virtual_Methods.Cursor);

      procedure Add_To_Potential_Targets
        (Position : Static_Stack_Analysis.List_Of_Virtual_Methods.Cursor)
      is
         Explored_Method : constant Virtual_Class_Access :=
           List_Of_Virtual_Methods.Element (Position);

         Explored_Method_Name : Name;

      begin
         if
           Static_Class.Derived.Contains (Explored_Method.Vtable_Entry.Class)
         then
            --  The method is overloaded in a class which is a descencent
            --  of the static class used for dispatching, so it is a potential
            --  canditate for dispatching and we add it to the list.

            if Explored_Method /= null and then
              Explored_Method.Symbol_Name /= null
            then
               Explored_Method_Name := Explored_Method.Symbol_Name;
            else
               --  We do not have information about the subprogram associated
               --  to the method. We give it a name line class:slot.

               Explored_Method_Name :=
                 new String'
                   (Explored_Method.Vtable_Entry.Class.Class_Name.all & ':' &
                    Slot_Number'Image (Explored_Method.Vtable_Entry.Slot));
            end if;

            Method_Subprogram := Get_Node (Explored_Method_Name.all);

            if not List_Of_Nodes.Has_Element (Method_Subprogram) then
               --  We need to create an artificial unresolved node

               Target_Ptr := new Unresolved_Node'
                 (Ada_File_Name           => Node.Ada_File_Name,
                  Target_Calls            => List_Of_Edges.Empty_Vector,
                  Accumulated_Stack_Usage => Unknown_Stack_Usage,
                  Location_List           => List_Of_Locations.Empty_Set,
                  Subprogram              => Explored_Method_Name,
                  Demangled               =>
                  new String'
                    (Demangle.Decode
                       (Explored_Method_Name, Node.Ada_File_Name)),
                  Alias                   => null,
                  Under_Analysis          => False,
                  Analysis_Finished       => False,
                  Is_Called               => False,
                  Is_Reachable            => False,
                  Cycles                  => List_Of_Cycles.Empty_Set);

               --  Insert new subprogram descriptor

               List_Of_Nodes.Insert
                 (Global_Data.List_Of_Subprograms,
                  Target_Ptr,
                  Method_Subprogram,
                  Inserted);

               pragma Assert (Inserted);
            end if;

            pragma Assert (List_Of_Nodes.Has_Element (Method_Subprogram));

            --  Mark the potential target of the dispatching call as reachable

            List_Of_Nodes.Element (Method_Subprogram).Is_Called := True;

            Static_Stack_Analysis.List_Of_Edges.Append
              (Result,
               new Static_Stack_Analysis.Edge_Element'(
                 Ada_File_Name  => Node.Ada_File_Name,
                 Target         => Method_Subprogram,
                 Point_Of_Call  => Node.Location_List,
                 Feasible_Call  => True,
                 Under_Analysis => False));
         end if;
      end Add_To_Potential_Targets;

   --  Start of processing for Get_Overriding_Methods
   begin
      --  We need to get the list of methods which override the one defined
      --  in the base class, and from this set we take only those which are
      --  defined by classes derived from the static class.

      --  At least there is the base method

      --  Get the subprogram associated to the base method. If it is not in
      --  the list we need to create an undefined one.

      if Base_Method /= null and then Base_Method.Symbol_Name /= null then
         Base_Method_Name := Base_Method.Symbol_Name;

      else
         --  We do not have information about the subprogram associated to
         --  the method. We give it a name line class:slot.

         Base_Method_Name :=
           new String'(Node.Base_Class.Class_Name.all & ':' &
                       Slot_Number'Image (Node.Slot));
      end if;

      Method_Subprogram := Get_Node (Base_Method_Name.all);

      if not List_Of_Nodes.Has_Element (Method_Subprogram) then
         --  We need to create an artificial unresolved node

         Target_Ptr := new Unresolved_Node'
           (Ada_File_Name           => Node.Ada_File_Name,
            Target_Calls            => List_Of_Edges.Empty_Vector,
            Accumulated_Stack_Usage => Unknown_Stack_Usage,
            Location_List           => List_Of_Locations.Empty_Set,
            Subprogram              => Base_Method_Name,
            Demangled               =>
            new String'
              (Demangle.Decode (Base_Method_Name, Node.Ada_File_Name)),
            Alias                   => null,
            Under_Analysis          => False,
            Analysis_Finished       => False,
            Is_Called               => False,
            Is_Reachable            => False,
            Cycles                  => List_Of_Cycles.Empty_Set);

         --  Insert new subprogram descriptor

         List_Of_Nodes.Insert
           (Global_Data.List_Of_Subprograms,
            Target_Ptr,
            Method_Subprogram,
            Inserted);

         pragma Assert (Inserted);
      end if;

      pragma Assert (List_Of_Nodes.Has_Element (Method_Subprogram));

      --  Mark the potential target of the dispatching call as reachable

      List_Of_Nodes.Element (Method_Subprogram).Is_Called := True;

      Static_Stack_Analysis.List_Of_Edges.Append
        (Result,
         new Static_Stack_Analysis.Edge_Element'(
           Ada_File_Name  => Node.Ada_File_Name,
           Target         => Method_Subprogram,
           Point_Of_Call  => Node.Location_List,
           Feasible_Call  => True,
           Under_Analysis => False));

      --  Now we need to iterate over the list of overriding methods.
      --
      --  When Base_Method is null it means that GNATstack does not have
      --  any information about this method, so the only thing that we can
      --  say is that it is an unresolved call.

      if Base_Method /= null then
         --  We need to use the Redefined_By list that comes from either
         --  the Base_Method or the one in the first base class.
         --  The C++ compiler, when a method is overridden, generates a
         --  pointer to the root of this method (the one defined by the
         --  first base class). The Ada compiler generates a pointer to the
         --  method directly overloaded.
         --  For Example, if we have the hierarchy Parent->Child->Grandchild
         --  and the three classes define a method called Foo, the Ada
         --  compiler generates the following for Grandchild::Foo:
         --  "1:grandchild__foo,1:child__foo"
         --  while the C++ compiler generates the following:
         --  "1:grandchild__foo,1:parent__foo"

         declare
            Overriding_List : List_Of_Virtual_Methods.Set :=
              List_Of_Virtual_Methods.Empty_Set;

            First_Base_Method : Virtual_Class_Access;

         begin
            if List_Of_Virtual_Methods.Is_Empty (Base_Method.Redefined_By) then
               --  If the list of methods overloading the direct base is empty
               --  it means that we may need to verify the method in the
               --  first base method. The reason for this is the different
               --  information generated by Ada and C++. When using Ada, the
               --  Redefined_By field is update throughout the whole class
               --  hierarchy, while in C++ this information is propagated
               --  only to the first base classes.
               --
               --  Note that here, there may be two different first base
               --  classes (the one in field Redefines and the one in field
               --  Redefines_Multiple). We can simply take the field Redefines
               --  (which is always available) because the required
               --  information has been propagated to both.

               First_Base_Method := Get_Method (Base_Method.Redefines);

               if First_Base_Method /= null then
                  Overriding_List := First_Base_Method.Redefined_By;
               end if;

            else
               Overriding_List := Base_Method.Redefined_By;
            end if;

            List_Of_Virtual_Methods.Iterate
              (Overriding_List, Add_To_Potential_Targets'Access);
         end;
      end if;

      return Result;
   end Get_Overriding_Methods;

   -------------------------------
   -- Propagate_Derived_Classes --
   -------------------------------

   procedure Propagate_Derived_Classes
     (Position : Static_Stack_Analysis.List_Of_Classes.Cursor)
   is
      Accumulated_Descendent : Static_Stack_Analysis.List_Of_Classes.Set :=
        Static_Stack_Analysis.List_Of_Classes.Empty_Set;

      Child : constant Class_Access := List_Of_Classes.Element (Position);

      procedure Propagate_To_Parent
        (Position : Static_Stack_Analysis.List_Of_Classes.Cursor);

      procedure Propagate_To_Parent
        (Position : Static_Stack_Analysis.List_Of_Classes.Cursor)
      is
         Parent : constant Class_Access := List_Of_Classes.Element (Position);
      begin
         --  Include the list of descendent classes to the parent

         Parent.Derived.Union (Accumulated_Descendent);

         --  Add this class to the list and continue going upstream

         Accumulated_Descendent.Insert (Parent);

         Static_Stack_Analysis.List_Of_Classes.Iterate
           (Parent.Parents, Propagate_To_Parent'Access);

         --  Remove me from the list

         Accumulated_Descendent.Delete (Parent);
      end Propagate_To_Parent;

   --  Start of processing for Propagate_Derived_Classes
   begin
      --  Add this class to the list of classes to propagate upstream

      Accumulated_Descendent.Insert (Child);

      --  Go up the parent's links

      Static_Stack_Analysis.List_Of_Classes.Iterate
        (Child.Parents, Propagate_To_Parent'Access);
   end Propagate_Derived_Classes;

   ----------------------------------
   -- Propagate_Overloaded_Methods --
   ----------------------------------

   procedure Propagate_Overloaded_Methods
     (Position : Static_Stack_Analysis.List_Of_Virtual_Methods.Cursor)
   is
      Accumulated_Overloaded :
      Static_Stack_Analysis.List_Of_Virtual_Methods.Set :=
        Static_Stack_Analysis.List_Of_Virtual_Methods.Empty_Set;

      Overloaded : constant Virtual_Class_Access :=
        List_Of_Virtual_Methods.Element (Position);

      procedure Propagate_To_Base (Base : Virtual_Class_Access);

      procedure Propagate_To_Base (Base : Virtual_Class_Access) is
      begin
         if Base /= null then
            --  Include the list of overloaded methods to the base

            Base.Redefined_By.Union (Accumulated_Overloaded);

            --  Add this method to the list and continue going upstream
            --  through both the primary and secondary vtables that may be
            --  overridden.

            Accumulated_Overloaded.Insert (Base);

            Propagate_To_Base
              (Static_Stack_Analysis.Get_Method (Base.Redefines));

            Propagate_To_Base
              (Static_Stack_Analysis.Get_Method (Base.Redefines_Multiple));

            --  Remove me from the list

            Accumulated_Overloaded.Delete (Base);
         end if;
      end Propagate_To_Base;

   --  Start of processing of Propagate_Overloaded_Methods
   begin
      --  Add this method to the list of methods to propagate upstream

      Accumulated_Overloaded.Insert (Overloaded);

      --  Go up the bases' links (primary and secondary)

      Propagate_To_Base
        (Static_Stack_Analysis.Get_Method (Overloaded.Redefines));

      Propagate_To_Base
        (Static_Stack_Analysis.Get_Method (Overloaded.Redefines_Multiple));
   end Propagate_Overloaded_Methods;

   -------------------------------
   -- Resolve_Dispatching_Calls --
   -------------------------------

   procedure Resolve_Dispatching_Calls is
      Index : List_Of_Nodes.Cursor :=
        Global_Data.List_Of_Subprograms.First;

      Node : Static_Stack_Analysis.Node_Class_Access;

   begin
      --  Loop for every instance of dispatching call

      while Static_Stack_Analysis.List_Of_Nodes.Has_Element (Index) loop

         Node := Static_Stack_Analysis.List_Of_Nodes.Element (Index);

         if Node.all in Dispatching_Node'Class then
            --  If the node is an artificial dispatching node, we need to
            --  verify whether we have all the potential targets. If the
            --  information is not there yet we compute and store it.

            List_Of_Edges.Append
              (Node.Target_Calls,
               Dispatching_Calls.Get_Overriding_Methods
                 (Dispatching_Node (Node.all)));

         end if;

         Index := Static_Stack_Analysis.List_Of_Nodes.Next (Index);
      end loop;
   end Resolve_Dispatching_Calls;

end Dispatching_Calls;
