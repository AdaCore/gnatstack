------------------------------------------------------------------------------
--                        STATIC STACK ANALYSIS TOOL                        --
--                                                                          --
--                     C A L L _ G R A P H _ C Y C L E S                    --
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

with Static_Stack_Analysis;
--  Used for Cycle
--           Cycle_Element
--           Node_Id

with Ada.Text_IO;
--  Used for Put_Line

with Ada.Unchecked_Deallocation;

package body Call_Graph_Cycles is

   ----------------------
   -- Local procedures --
   ----------------------

   procedure Analyze_Cycles (Position : in Static_Stack_Analysis.Edge_Id);
   --  Check whether this call is already part of the path being analyzed (and
   --  hence it is part of a call graph cycle).

   procedure Analyze_Cycles (Position : in Static_Stack_Analysis.Node_Id);
   --  Check whether this subprogram is already part of the path being analyzed
   --  (and hence it is part of a call graph cycle).

   procedure Add_Node_To_Path
     (Cycle : in Static_Stack_Analysis.Cycle;
      Node  : in Static_Stack_Analysis.Node_Id);
   --  This procedure adds the specified node to the cycle and annotates the
   --  node belonging to this cycle to mark that the node is part of the cycle.

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
                           (Source_Node => Node, Call_To => Index));

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

   --------------------
   -- Analyze_Cycles --
   --------------------

   procedure Analyze_Cycles (Position : in Static_Stack_Analysis.Node_Id) is
      Explored_Node : constant Static_Stack_Analysis.Node_Class_Access :=
        Static_Stack_Analysis.List_Of_Nodes.Element (Position);

   begin
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
         end;

      else
         --  Mark it under analysis

         Explored_Node.Under_Analysis := True;

         --  Explore all the possible target calls

         Static_Stack_Analysis.List_Of_Edges.Iterate
           (Explored_Node.Target_Calls, Analyze_Cycles'Access);

         --  Mark the end of the analysis for this node

         Explored_Node.Under_Analysis := False;
      end if;
   end Analyze_Cycles;

   procedure Analyze_Cycles (Position : in Static_Stack_Analysis.Edge_Id) is
      Explored_Edge : constant Static_Stack_Analysis.Edge :=
        Static_Stack_Analysis.List_Of_Edges.Element (Position);

   begin
      --  Mark it under analysis

      Explored_Edge.Under_Analysis := True;

      --  Analyze the node to which this call points

      Analyze_Cycles (Explored_Edge.Target);

      --  Mark the end of the analysis for this edge

      Explored_Edge.Under_Analysis := False;
   end Analyze_Cycles;

   --------------------
   -- Extract_Cycles --
   --------------------

   procedure Extract_Cycles is
   begin
      Static_Stack_Analysis.List_Of_Subprograms.Iterate
        (Analyze_Cycles'Access);
   end Extract_Cycles;

end Call_Graph_Cycles;
