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

package body Worst_Case_Analyzer is

   use type Static_Stack_Analysis.Stack_Usage_Info;

   -------------------
   -- Ordered edges --
   -------------------

   package Ordered_Edges is
     new Static_Stack_Analysis.List_Of_Edges.Generic_Sorting
       (Static_Stack_Analysis.Stack_Usage_Order);
   --  Edges (calls to subprograms) are ordered according to stack usage

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
      Explored_Edge : constant Static_Stack_Analysis.Edge :=
        Static_Stack_Analysis.List_Of_Edges.Element (Position);

   begin
      --  Mark it under analysis

      Explored_Edge.Under_Analysis := True;

      --  Analyze the node to which this call points

      Compute_Worst_Case (Explored_Edge.Target);

      --  Mark the end of the analysis for this edge

      Explored_Edge.Under_Analysis := False;
   end Compute_Worst_Case;

   procedure Compute_Worst_Case
     (Position : in Static_Stack_Analysis.Node_Id)
   is
      Explored_Node : constant Static_Stack_Analysis.Node_Class_Access :=
        Static_Stack_Analysis.List_Of_Nodes.Element (Position);

   begin
      --  Check against cycles

      --  Break the cycle in the worst case computation. Assume that the
      --  cycle is executed only once.

      if not Explored_Node.Under_Analysis then
         --  Mark it under analysis

         Explored_Node.Under_Analysis := True;

         if Explored_Node.Accumulated_Stack_Usage =
           Static_Stack_Analysis.Unknown_Stack_Usage
         then
            --  For a given node we need to explore all the possible target
            --  calls (getting their accumulated stack usage) and then order
            --  these calls according to to the previously computed value.

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

      end if;
   end Compute_Worst_Case;

   ----------------------
   -- Get_Longest_Path --
   ----------------------

   procedure Get_Longest_Path
     (Path   : in out Static_Stack_Analysis.Paths.Vector;
      Target : in Static_Stack_Analysis.Node_Id)
   is
      use type Static_Stack_Analysis.Edge_Id;

      Node : constant Static_Stack_Analysis.Node_Class_Access :=
        Static_Stack_Analysis.List_Of_Nodes.Element (Target);

      Call : constant Static_Stack_Analysis.Edge_Id :=
        Static_Stack_Analysis.List_Of_Edges.First (Node.Target_Calls);
      --  The longest path is the one in the first position of the sorted list

   begin
      --  Stop if we find a cycle

      if not Node.Under_Analysis then
         --  Mark node under analysis

         Node.Under_Analysis := True;

         --  Add this node to the path

         Path.Append (Static_Stack_Analysis.Path_Element'(Target, Call));

         --  Add subsequent calls to the path. Cycles must be handled

         if Static_Stack_Analysis.List_Of_Edges.Has_Element (Call) then
            Get_Longest_Path
              (Path,
               Static_Stack_Analysis.List_Of_Edges.Element (Call).Target);
         end if;

         --  Mark the end of the analysis for this node

         Node.Under_Analysis := False;
      end if;
   end Get_Longest_Path;

   -------------------------
   -- Worst_Case_Analysis --
   -------------------------

   procedure Worst_Case_Analysis is
   begin
      --  Explore every entry point

      Static_Stack_Analysis.List_Of_Entry_Points.Iterate
        (Static_Stack_Analysis.Entry_Points, Compute_Worst_Case'Access);
   end Worst_Case_Analysis;

end Worst_Case_Analyzer;
