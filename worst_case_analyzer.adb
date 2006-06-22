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

with Ada.Text_IO;
--  Used for Put_Line

with Ada.Unchecked_Deallocation;

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

   procedure Add_Node_To_Path
     (Cycle : in Static_Stack_Analysis.Cycle;
      Node  : in Static_Stack_Analysis.Node_Id);
   --  This procedure adds the specified node to the cycle and annotates the
   --  node belonging to this cycle to mark that the node is part of the cycle.

   procedure Compute_Worst_Case
     (Position : in Static_Stack_Analysis.List_Of_Entry_Points.Cursor);
   --  Compute the worst case stack usage starting from the indicated entry
   --  point.

   procedure Compute_Worst_Case (Position : in Static_Stack_Analysis.Edge_Id);
   --  Compute the worst case stack usage starting from the indicated call

   procedure Compute_Worst_Case (Position : in Static_Stack_Analysis.Node_Id);
   --  Compute the worst case stack usage starting from the indicated
   --  subprogram.

   function Already_Detected_Cycle
     (Cycle : Static_Stack_Analysis.Cycle) return Boolean;
   --  Check whether the cycle is already within the list of detected cycles

   procedure Free is new
     Ada.Unchecked_Deallocation
       (Static_Stack_Analysis.Cycle_Element, Static_Stack_Analysis.Cycle);

   ----------------------
   -- Add_Node_To_Path --
   ----------------------

   procedure Add_Node_To_Path
     (Cycle : in Static_Stack_Analysis.Cycle;
      Node  : in Static_Stack_Analysis.Node_Id)
   is
      use type Static_Stack_Analysis.Edge_Id;
      use type Static_Stack_Analysis.Node_Id;

      Explored_Node : constant Static_Stack_Analysis.Node_Class_Access :=
        Static_Stack_Analysis.List_Of_Nodes.Element (Node);

      Next_Node : Static_Stack_Analysis.Node_Id;

      Found : Boolean := False;

      Index : Static_Stack_Analysis.Edge_Id;

      procedure Is_Under_Analysis (Target : Static_Stack_Analysis.Edge);

      procedure Is_Under_Analysis (Target : Static_Stack_Analysis.Edge) is
      begin
         Found := Target.Under_Analysis;
      end Is_Under_Analysis;

   begin
      --  Get the edge that is under analysis

      Index := Explored_Node.Target_Calls.First;

      loop
         Static_Stack_Analysis.List_Of_Edges.Query_Element
           (Index, Is_Under_Analysis'Access);

         exit when Found;

         Static_Stack_Analysis.List_Of_Edges.Next (Index);

         pragma Assert
           (Static_Stack_Analysis.List_Of_Edges.Has_Element (Index));
      end loop;

      --  Add the node to the path

      Cycle.Path.Append (Static_Stack_Analysis.Path_Element'
          (Source_Node => Node,
           Call_To     => Index));

      --  Add next node to the path, if not already in the list

      Next_Node := Static_Stack_Analysis.List_Of_Edges.Element (Index).Target;

      if Next_Node /= Cycle.Path.First_Element.Source_Node then
         Add_Node_To_Path (Cycle, Next_Node);
      end if;
   end Add_Node_To_Path;

   ----------------------------
   -- Already_Detected_Cycle --
   ----------------------------

   function Already_Detected_Cycle
     (Cycle : Static_Stack_Analysis.Cycle) return Boolean
   is
      use type Static_Stack_Analysis.List_Of_Nodes.Set;

      Found : Boolean := False;
      --  Set to True if the cycle is already in the list

      Reference_Set : Static_Stack_Analysis.List_Of_Nodes.Set :=
        Static_Stack_Analysis.List_Of_Nodes.Empty_Set;
      --  Set of subprograms belonging to the cycle that we are studying

      Index : Static_Stack_Analysis.Paths.Cursor;

      procedure Check_Cycle
        (Position : Static_Stack_Analysis.List_Of_Cycles.Cursor);
      --  Compare the indicated cycle (the set of subprograms that make up the
      --  callgraph cycle) against the reference one(Reference_Set). If they
      --  are the same then it means that the cycle has already been detected
      --  and it must not be added again to the list of known cycles.

      procedure Check_Cycle
        (Position : Static_Stack_Analysis.List_Of_Cycles.Cursor)
      is
         Explored_Path : constant Static_Stack_Analysis.Paths.Vector :=
           Static_Stack_Analysis.List_Of_Cycles.Element (Position).Path;

         Explored_Set : Static_Stack_Analysis.List_Of_Nodes.Set :=
           Static_Stack_Analysis.List_Of_Nodes.Empty_Set;

      begin
         if not Found then
            --  Get the set of subprograms that make up the callgraph cycle
            --  that we want to compare.

            Index := Explored_Path.First;

            while Static_Stack_Analysis.Paths.Has_Element (Index) loop
               Static_Stack_Analysis.List_Of_Nodes.Insert
                 (Explored_Set,
                  Static_Stack_Analysis.List_Of_Nodes.Element
                    (Static_Stack_Analysis.Paths.Element (Index).Source_Node));

               Static_Stack_Analysis.Paths.Next (Index);
            end loop;

            --  Compare the generated set with the reference one

            if Explored_Set = Reference_Set then
               Found := True;
            end if;
         end if;
      end Check_Cycle;

   begin
      --  The cycle may have already been detected in a different order. That
      --  is the reason why we use the set of nodes belonging to the path
      --  (in alphabetical order) to compare.

      Index := Cycle.Path.First;

      while Static_Stack_Analysis.Paths.Has_Element (Index) loop
         Static_Stack_Analysis.List_Of_Nodes.Insert
           (Reference_Set,
            Static_Stack_Analysis.List_Of_Nodes.Element
              (Static_Stack_Analysis.Paths.Element (Index).Source_Node));

         Static_Stack_Analysis.Paths.Next (Index);
      end loop;

      --  Compare the detected cycle against the list of already detected
      --  cycles.

      Static_Stack_Analysis.Cycles.Iterate (Check_Cycle'Access);

      return Found;
   end Already_Detected_Cycle;

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

      if Explored_Node.Under_Analysis then
         --  Cycle detected. It may be a new or an already detected cycle

         declare
            New_Cycle : Static_Stack_Analysis.Cycle :=
              new Static_Stack_Analysis.Cycle_Element'
                (Id         => 0,
                 Path       => Static_Stack_Analysis.Paths.Empty_Vector,
                 Iterations => 1);

            procedure Mark_Nodes
              (Position : Static_Stack_Analysis.Paths.Cursor);
            --  Mark the referenced node as belonging to the detected cycle

            procedure Mark_Nodes
              (Position : Static_Stack_Analysis.Paths.Cursor)
            is
               Element : constant Static_Stack_Analysis.Node_Class_Access :=
                 Static_Stack_Analysis.List_Of_Nodes.Element
                   (Static_Stack_Analysis.Paths.Element
                        (Position).Source_Node);

            begin
               Static_Stack_Analysis.Node (Element.all).Cycles.Append
                    (New_Cycle);
            end Mark_Nodes;

         begin
            if Options.Verbose then
               Ada.Text_IO.Put_Line ("Cycle detected");
            end if;

            --  Now we need to extract and identify this cycle. We need to
            --  follow the path marked by the Under_Analysis flag.

            --  Add current node (and all the subprograms that make up the
            --  cycle) to the path information.

               Add_Node_To_Path (New_Cycle, Position);

            --  Add the new cycle to the list of detected cycles

            if Already_Detected_Cycle (New_Cycle) then
               New_Cycle.Path.Clear;

               Free (New_Cycle);

            else
               --  Add cycle

               Static_Stack_Analysis.Cycles.Append (New_Cycle);

               --  Update Id

               New_Cycle.Id := Static_Stack_Analysis.Cycles.Last_Index;

               --  Mark the nodes as belonging to this cycle

               New_Cycle.Path.Iterate (Mark_Nodes'Access);
            end if;

            --  Break the cycle in the worst case computation. Assume that the
            --  cycle is executed only once.

            return;
         end;
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
