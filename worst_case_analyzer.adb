------------------------------------------------------------------------------
--                        STATIC STACK ANALYSIS TOOL                        --
--                                                                          --
--                   W O R S T _ C A S E _ A N A L Y Z E R                  --
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

with Options;
--  Used for Verbose
--           Explore_All

with Ada.Text_IO;
--  Used for Put_Line

package body Worst_Case_Analyzer is

   use type Static_Stack_Analysis.Stack_Usage_Info;

   -------------------
   -- Ordered edges --
   -------------------

   package Ordered_Edges is
     new Static_Stack_Analysis.List_Of_Edges.Generic_Sorting
       (Static_Stack_Analysis.Stack_Usage_Order);

   ----------------------
   -- Local procedures --
   ----------------------

   procedure Compute_Worst_Case
     (Position : in Static_Stack_Analysis.List_Of_Entry_Points.Cursor);
   --  Compute the worst case stack usage starting from the indicated entry
   --  point.

   procedure Compute_Worst_Case (Position : in Static_Stack_Analysis.Edge_Id);
   --  Compute the worst case stack usage starting from the indicated call

   procedure Compute_Worst_Case (Position : in Static_Stack_Analysis.Node_Id);
   --  Compute the worst case stack usage starting from the indicated
   --  subprogram.

   procedure Add_Entry_Point (Position : in Static_Stack_Analysis.Node_Id);
   --  Add the node to the list of entry points to analyze if it contains a
   --  subprogram that is part of the application code.

   ---------------------
   -- Add_Entry_Point --
   ---------------------

   procedure Add_Entry_Point (Position : in Static_Stack_Analysis.Node_Id) is
      Explored_Node : constant Static_Stack_Analysis.Node_Class_Access :=
        Static_Stack_Analysis.List_Of_Nodes.Element (Position);

   begin
      if Explored_Node.all in Static_Stack_Analysis.Explicit_Node'Class then
         Static_Stack_Analysis.Entry_Points.Append (Position);
      end if;
   end Add_Entry_Point;

   ------------------------
   -- Compute_Worst_Case --
   ------------------------

   procedure Compute_Worst_Case
     (Position : in Static_Stack_Analysis.List_Of_Entry_Points.Cursor)
   is
   begin
      --  Analyze the indicated node

      Compute_Worst_Case
        (Static_Stack_Analysis.List_Of_Entry_Points.Element (Position));
   end Compute_Worst_Case;

   procedure Compute_Worst_Case
     (Position : in Static_Stack_Analysis.Edge_Id)
   is
   begin
      --  Analyze the node to which this call points

      Compute_Worst_Case
        (Static_Stack_Analysis.List_Of_Edges.Element (Position).Target);
   end Compute_Worst_Case;

   procedure Compute_Worst_Case
     (Position : in Static_Stack_Analysis.Node_Id)
   is
      Explored_Node : constant Static_Stack_Analysis.Node_Class_Access :=
        Static_Stack_Analysis.List_Of_Nodes.Element (Position);

   begin
      --  Check against cycles

      if Explored_Node.Under_Analysis then
         --  Cycle detected

         if Options.Verbose then
            Ada.Text_IO.Put_Line ("Cycle detected");
         end if;

         --  Break the cycle in the worst case computation. Assume that the
         --  cycle is executed only once.

         return;

      else
         --  Mark it under analysis

         Explored_Node.Under_Analysis := True;
      end if;

      if Explored_Node.Accumulated_Stack_Usage =
         Static_Stack_Analysis.Unknown_Stack_Usage
      then
         --  For a given node we need to explore all the possible target calls
         --  (getting their accumulated stack usage) and then order these calls
         --  according to to the previously computed value.

         --  Iterate

         Static_Stack_Analysis.List_Of_Edges.Iterate
           (Explored_Node.Target_Calls, Compute_Worst_Case'Access);

         --  Sort

         Ordered_Edges.Sort (Explored_Node.Target_Calls);

         --  Update info

         if Static_Stack_Analysis.List_Of_Edges.Is_Empty
           (Explored_Node.Target_Calls)
         then
            Explored_Node.Accumulated_Stack_Usage :=
              Static_Stack_Analysis.Get_Stack_Usage (Explored_Node.all);

         else
            Explored_Node.Accumulated_Stack_Usage :=
              Static_Stack_Analysis."+"
                (Static_Stack_Analysis.Get_Stack_Usage (Explored_Node.all),
                 Static_Stack_Analysis.Get_Accumulated_Stack_Usage
                   (Static_Stack_Analysis.List_Of_Nodes.Element
                      (Static_Stack_Analysis.List_Of_Edges.First_Element
                         (Explored_Node.Target_Calls).Target).all));
         end if;
      end if;

      --  Mark the end of the analysis for this node

      Explored_Node.Under_Analysis := False;
   end Compute_Worst_Case;

   ----------------------
   -- Get_Longest_Path --
   ----------------------

   function Get_Longest_Path
     (Target : Static_Stack_Analysis.Node_Id)
      return Static_Stack_Analysis.Paths.Vector
   is
      Node : constant Static_Stack_Analysis.Node_Class_Access :=
        Static_Stack_Analysis.List_Of_Nodes.Element (Target);

   begin
      if Static_Stack_Analysis.List_Of_Edges.Is_Empty (Node.Target_Calls) then
         return
           Static_Stack_Analysis.Paths.To_Vector
             (New_Item => Static_Stack_Analysis.Path_Element'
                  (Target, Static_Stack_Analysis.List_Of_Edges.No_Element),
              Length   => 1);

      else
         --  The longest path is the one in the last position of the sorted
         --  list.

         return Static_Stack_Analysis.Paths."&"
           (Static_Stack_Analysis.Path_Element'
              (Target,
               Static_Stack_Analysis.List_Of_Edges.Last (Node.Target_Calls)),
            Get_Longest_Path
              (Static_Stack_Analysis.List_Of_Edges.First_Element
                 (Node.Target_Calls).Target));
      end if;
   end Get_Longest_Path;

   -------------------------
   -- Worst_Case_Analysis --
   -------------------------

   procedure Worst_Case_Analysis is
   begin
      if Options.Explore_All then
         --  Explore every node that contains subprograms defined within the
         --  application

         Static_Stack_Analysis.List_Of_Nodes.Iterate
           (Static_Stack_Analysis.List_Of_Subprograms, Add_Entry_Point'Access);
      end if;

      --  Explore every entry point

      Static_Stack_Analysis.List_Of_Entry_Points.Iterate
        (Static_Stack_Analysis.Entry_Points, Compute_Worst_Case'Access);
   end Worst_Case_Analysis;

end Worst_Case_Analyzer;
