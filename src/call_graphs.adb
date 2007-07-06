------------------------------------------------------------------------------
--                        STATIC STACK ANALYSIS TOOL                        --
--                                                                          --
--                           C A L L _ G R A P H S                          --
--                                                                          --
--                                 B o d y                                  --
--                                                                          --
--                     Copyright (C) 2005-2007, AdaCore                     --
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
--  Used for Node_Id
--           Edge_Id
--           Cycle

with Global_Data;
--  Used for Unbounded_Frames
--           External_Calls
--           Indirect_Calls
--           Cycles

with Options;
--  Used for Verbose
--           Compute_All_Cycles

with Ada.Text_IO;
--  Used for Put_Line

with Ada.Unchecked_Deallocation;

package body Call_Graphs is

   -----------------------
   -- Local subprograms --
   -----------------------

   procedure Analyze_Call (Position : in Static_Stack_Analysis.Edge_Id);
   --  Analyze potential problems for this call (cycles, external or indirect
   --  calls, or unbounded frames).

   procedure Analyze_Node (Position : in Static_Stack_Analysis.Node_Id);
   --  Analyze potential problems for this call (cycles, external or indirect
   --  calls, or unbounded frames).

   procedure Analyze_Detected_Cycle
     (Position : in Static_Stack_Analysis.Node_Id);
   --  Check whether the detected cycle (the one whose root is the indicated
   --  node) is already known.

   procedure Add_Node_To_Path
     (Cycle : in Static_Stack_Analysis.Cycle;
      Node  : in Static_Stack_Analysis.Node_Id);
   --  This procedure adds the specified node to the cycle and annotates the
   --  node belonging to this cycle to mark that the node is part of the cycle.

   function Already_Detected_Cycle
     (Cycle : Static_Stack_Analysis.Cycle) return Boolean;
   --  Check whether the cycle is already within the list of detected cycles

   procedure Mark_End_Of_Analysis
     (Node : Static_Stack_Analysis.Node_Class_Access);
   --  Mark this node (and all the nodes recursively called by this one) as
   --  fully analyzed.

   procedure Free is new
     Ada.Unchecked_Deallocation
       (Static_Stack_Analysis.Cycle_Element, Static_Stack_Analysis.Cycle);

   ----------------
   -- Local data --
   ----------------

   Reference_Set : Static_Stack_Analysis.List_Of_Nodes.Set :=
     Static_Stack_Analysis.List_Of_Nodes.Empty_Set;
   --  Set of subprograms belonging to the cycle that we are studying

   Explored_Set : Static_Stack_Analysis.List_Of_Nodes.Set :=
     Static_Stack_Analysis.List_Of_Nodes.Empty_Set;
   --  Set of subprograms belonging to the cycle that we are analyzing

   Nodes_With_Cycles : Static_Stack_Analysis.List_Of_Node_Ids.Vector :=
     Static_Stack_Analysis.List_Of_Node_Ids.Empty_Vector;
   --  Set of subprograms that are part of a cycle. This list will be analyzed
   --  for cycles as soon as possible to avoid expensive iterations.

   Analyze_Later : Boolean := False;
   --  This flag is set to True when we want to stop the analysis of cycles.
   --  The idea is to analyze first the cycles so we avoid repeating the costly
   --  process of analyzing the same cycle again.

   Main_Found : Boolean := False;
   --  Set to True if the main Ada procedure has been found

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
      --  Next node to be added to the path that makes up the cycle

      Found : Boolean := False;
      --  Set to True when the next node in the cycle has been found

      Index : Static_Stack_Analysis.Edge_Id;
      --  Index used to explore calls made by this subprogram

      procedure Is_Under_Analysis (Target : Static_Stack_Analysis.Edge);
      --  Check whether the target of this call is part ot the cycle that we
      --  are analyzing.

      procedure Is_Under_Analysis (Target : Static_Stack_Analysis.Edge) is
      begin
         Found := Target.Under_Analysis;
      end Is_Under_Analysis;

   begin
      --  Get the edge that is under analysis. We start from the last edge
      --  because this way we consider the last path being studied. There may
      --  already be several cycles detected.

      Index := Explored_Node.Target_Calls.Last;

      loop
         Static_Stack_Analysis.List_Of_Edges.Query_Element
           (Index, Is_Under_Analysis'Access);

         exit when Found;

         Static_Stack_Analysis.List_Of_Edges.Previous (Index);

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

      procedure Add_To_Reference_Path
        (Position : Static_Stack_Analysis.Paths.Cursor);
      --  Add the node to the list of nodes to be taken as a reference

      procedure Add_To_Reference_Path
        (Position : Static_Stack_Analysis.Paths.Cursor) is
      begin
         Static_Stack_Analysis.List_Of_Nodes.Insert
           (Reference_Set,
            Static_Stack_Analysis.List_Of_Nodes.Element
              (Static_Stack_Analysis.Paths.Element (Position).Source_Node));
      end Add_To_Reference_Path;

      procedure Check_Cycle
        (Position : Static_Stack_Analysis.List_Of_Cycles.Cursor);
      --  Compare the indicated cycle (the set of subprograms that make up the
      --  callgraph cycle) against the reference one (Reference_Set). If they
      --  are the same then it means that the cycle has already been detected
      --  and it must not be added again to the list of known cycles.

      procedure Check_Cycle
        (Position : Static_Stack_Analysis.List_Of_Cycles.Cursor)
      is
         Explored_Path : constant Static_Stack_Analysis.Paths.Vector :=
           Static_Stack_Analysis.List_Of_Cycles.Element (Position).Path;
         --  Path under analysis

         procedure Add_To_Explored_Path
           (Position : Static_Stack_Analysis.Paths.Cursor);
         --  Add the node to the list of nodes to be compared against the
         --  reference.

         procedure Add_To_Explored_Path
           (Position : Static_Stack_Analysis.Paths.Cursor) is
         begin
            Static_Stack_Analysis.List_Of_Nodes.Insert
              (Explored_Set,
               Static_Stack_Analysis.List_Of_Nodes.Element
                 (Static_Stack_Analysis.Paths.Element (Position).Source_Node));
         end Add_To_Explored_Path;

      begin
         if not Found then
            --  Get the set of subprograms that make up the call graph cycle
            --  that we want to compare.

            Explored_Set.Clear;
            Explored_Path.Iterate (Add_To_Explored_Path'Access);

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

      Reference_Set.Clear;
      Cycle.Path.Iterate (Add_To_Reference_Path'Access);

      --  Compare the detected cycle against the list of already detected
      --  cycles.

      Global_Data.Cycles.Iterate (Check_Cycle'Access);

      return Found;
   end Already_Detected_Cycle;

   ------------------
   -- Analyze_Node --
   ------------------

   procedure Analyze_Node (Position : in Static_Stack_Analysis.Node_Id) is
      Node : constant Static_Stack_Analysis.Node_Class_Access :=
        Static_Stack_Analysis.List_Of_Nodes.Element (Position);

      use Static_Stack_Analysis;

      function Ada_Binder_Main return Boolean;
      --  Look for the typical Ada entry point which is identified by the
      --  symbol "main". Sometimes, the main Ada entry point is not "main" but
      --  a procedure generated by the binder that has the particularity of
      --  calling a procedure whose name is its own name prefixed by "_ada_".

      function Ada_Binder_Main return Boolean is
         Index : Static_Stack_Analysis.Edge_Id;
         --  Index used to explore calls made by this subprogram

         Name : Static_Stack_Analysis.Name;

         Found : Boolean := False;

         procedure Calls_Ada_Main (Call : Static_Stack_Analysis.Edge);
         --  If this call represents a call from XXX to _ada_XXX then we have
         --  found the main Ada entry point.

         procedure Calls_Ada_Main (Call : Static_Stack_Analysis.Edge) is
            Called : constant Static_Stack_Analysis.Node_Class_Access :=
              Static_Stack_Analysis.List_Of_Nodes.Element (Call.Target);
         begin
            Found :=
              Static_Stack_Analysis.Get_Subprogram_Name (Called.all).all =
              "_ada_" & Name.all;
         end Calls_Ada_Main;

      begin
         if Main_Found then
            return False;

         --  Look for the main Ada entry point
         else
            Name := Static_Stack_Analysis.Get_Subprogram_Name (Node.all);

            if Name.all = "main" then
               Main_Found := True;
               return True;
            else
               Index := Node.Target_Calls.First;

               while
                 Static_Stack_Analysis.List_Of_Edges.Has_Element (Index)
               loop
                  Static_Stack_Analysis.List_Of_Edges.Query_Element
                    (Index, Calls_Ada_Main'Access);

                  if Found then
                     return True;
                  else
                     Static_Stack_Analysis.List_Of_Edges.Next (Index);
                  end if;
               end loop;

               return False;
            end if;
         end if;
      end Ada_Binder_Main;

   begin
      --  Do nothing if this node has been fully analyzed. It means that all
      --  the cycles to which it belongs are already known.

      if not Analyze_Later
        and then not Node.Analysis_Finished
      then
         --  First we check for cycles

         if Node.Under_Analysis then
            --  Cycle detected. It may be a new or an already detected one

            Analyze_Detected_Cycle (Position);

         else
            --  Mark it under analysis

            Node.Under_Analysis := True;

            --  Update accuracy of the explored entry point

            if not Global_Data.Unbounded_Frames
              and then Node.all in Explicit_Node'Class
              and then Explicit_Node (Node.all).Stack_Info.Frame_Type =
                       Unbounded
            then
               Global_Data.Unbounded_Frames := True;

            elsif not Global_Data.External_Calls
              and then Node.all in Unresolved_Node'Class
            then
               Global_Data.External_Calls := True;

            elsif not Global_Data.Indirect_Calls
              and then Node.all in Fake_Node'Class
            then
               Global_Data.Indirect_Calls := True;
            end if;

            --  Explore all the possible target calls.

            List_Of_Edges.Iterate (Node.Target_Calls, Analyze_Call'Access);

            --  Mark the end of the analysis for this node

            if not Options.Compute_All_Cycles then
               Node.Analysis_Finished := True;
            end if;

            Node.Under_Analysis := False;

            --  Verify whether this is a potential entry point for the
            --  application.
            --  If the -a option (use all subprograms as entry points) has been
            --  selected then we consider subprograms not called by anyone
            --  else. Only explicit nodes, which means excluding external
            --  subprograms and indirect (including dispatching) calls.
            --  Otherwise (no -a option), use main procedure(s) and task entry
            --  points). This will be the symbol "main" for all targets except
            --  VxWorks (kernel mode). If "main" is not found we can use those
            --  subprograms XXX that call _ada_XXX. If these symbols are not
            --  found then we can use all potential entry points (every
            --  subprogram not called by any other and defined in a spec).
            --  For task entry points we will first try to detect whether
            --  tasking is used. For that, we can look for references to
            --  system__tasking__stages__create_task or
            --  system__tasking__restricted__stages__create_restricted_task. If
            --  tasking is used then we can apply the heuristic of looking for
            --  symbols like my_package__tTKB or my_package__tB, or
            --  my_package__tB.1).

            if Options.Automatic_Entry_Point_Detection
              and then Node.all in Explicit_Node'Class
              and then not Node.Is_Called
              and then
                (Options.Explore_All
                   or else
                 Ada_Binder_Main
                   or else
                 (Global_Data.Ada_Tasking_Used
                    and then
                  Global_Data.Is_Task_Entry (Get_Subprogram_Name (Node.all))))
            then
               Global_Data.Entry_Points.Append (Position);
            end if;
         end if;
      end if;
   end Analyze_Node;

   procedure Analyze_Call (Position : in Static_Stack_Analysis.Edge_Id) is
      Explored_Edge : constant Static_Stack_Analysis.Edge :=
        Static_Stack_Analysis.List_Of_Edges.Element (Position);

      Target_Node : constant Static_Stack_Analysis.Node_Class_Access :=
        Static_Stack_Analysis.List_Of_Nodes.Element (Explored_Edge.Target);

   begin
      if not Analyze_Later then
         pragma Assert (not Explored_Edge.Under_Analysis);

         --  Mark it under analysis

         Explored_Edge.Under_Analysis := True;

         --  Analyze the node to which this call points

         Analyze_Node (Explored_Edge.Target);

         --  Mark the target subprogram as being directly called

         Target_Node.Is_Called := True;

         --  Mark the end of the analysis for this edge

         Explored_Edge.Under_Analysis := False;
      end if;
   end Analyze_Call;

   ------------------------
   -- Analyze_Call_Graph --
   ------------------------

   procedure Analyze_Call_Graph is
      procedure Analyze_Subprogram
        (Position : in Static_Stack_Analysis.Node_Id);
      --  Depending on the selected flags, this procedure will extract all the
      --  cycles that can be reached from the specified entry point, as well as
      --  undefined references, indirect calls and unbounded frames.

      procedure Analyze_Subprogram
        (Position : in Static_Stack_Analysis.Node_Id)
      is
         Cycle_Index : Static_Stack_Analysis.Node_Id;

      begin
         --  Start analysis from this node

         Analyze_Later := False;

         --  Check for potential problems (such as cycles, indirect or external
         --  calls or unbounded frames) if it has not been done yet.

         Analyze_Node (Position);

         --  We must analyze the new cycles that have been found. The goal
         --  is to analyze cycles as soon as possible so we can mark then
         --  as analyzed, avoinding repeating the same analysis again.

         while not Nodes_With_Cycles.Is_Empty loop
            --  Start analysis of this new cycle

            Analyze_Later := False;

            Cycle_Index := Nodes_With_Cycles.Last_Element;

            Nodes_With_Cycles.Delete_Last;

            Analyze_Node (Cycle_Index);
         end loop;

         --  Once all the reachable cycles from this subprogram have been found
         --  then we can mark this node (and all the nodes called by this one)
         --  as analyzed. This is the case when computing all cycles. If we are
         --  trying a simpler (and quicker) cycle detection scheme the nodes
         --  will be marked as analyzed once we have explored all the possible
         --  calls.

         if Options.Compute_All_Cycles then
            Mark_End_Of_Analysis
              (Static_Stack_Analysis.List_Of_Nodes.Element (Position));
         end if;
      end Analyze_Subprogram;

   begin
      --  Iterate over all the subprograms

      Static_Stack_Analysis.List_Of_Nodes.Iterate
        (Global_Data.List_Of_Subprograms, Analyze_Subprogram'Access);
   end Analyze_Call_Graph;

   ----------------------------
   -- Analyze_Detected_Cycle --
   ----------------------------

   procedure Analyze_Detected_Cycle
     (Position : in Static_Stack_Analysis.Node_Id)
   is
      New_Cycle : Static_Stack_Analysis.Cycle :=
        new Static_Stack_Analysis.Cycle_Element'
          (Id         => 0,
           Path       => Static_Stack_Analysis.Paths.Empty_Vector,
           Iterations => 1);
      --  Potential cycle to be analyzed for determining whether it is
      --  already known or not.
      --  This dynamically created object is later destroyed if it is not
      --  used (it happens when it is not inserted in the list of cycles).

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
         --  Add the cycle to the list of cycles for this node

         Element.Cycles.Append (New_Cycle);
      end Mark_Nodes;

   begin
      if Options.Debug then
         Ada.Text_IO.Put_Line ("Cycle detected");
      end if;

      --  Now we need to extract and identify this cycle. We need to
      --  follow the path marked by the Under_Analysis flag.

      Add_Node_To_Path (New_Cycle, Position);

      --  Add the new cycle to the list of detected cycles, if not there yet.
      --  The object is deleted if it is no longer used.

      if Already_Detected_Cycle (New_Cycle) then
         New_Cycle.Path.Clear;
         Free (New_Cycle);

      else
         --  Add cycle

         Global_Data.Cycles.Append (New_Cycle);

         --  Update Id

         New_Cycle.Id := Global_Data.Cycles.Last_Index;

         --  Mark the nodes as belonging to this cycle

         New_Cycle.Path.Iterate (Mark_Nodes'Access);

         --  We mark this cycle to be analyzed later

         if Options.Compute_All_Cycles then
            --  Add the subprogram to the list to be analyzed later if not
            --  already there.

            if not Nodes_With_Cycles.Contains (Position) then
               Static_Stack_Analysis.List_Of_Node_Ids.Append
                 (Nodes_With_Cycles, Position);
            end if;

            --  Stop the analysis so we start the analysis of the already
            --  detected cycles.

            Analyze_Later := True;
         end if;
      end if;
   end Analyze_Detected_Cycle;

   --------------------------
   -- Mark_End_Of_Analysis --
   --------------------------

   procedure Mark_End_Of_Analysis
     (Node : Static_Stack_Analysis.Node_Class_Access)
   is
      procedure Mark_End_Of_Analysis
        (Position : in Static_Stack_Analysis.Edge_Id);
      --  Mark the target node as analyzed

      procedure Mark_End_Of_Analysis
        (Position : in Static_Stack_Analysis.Edge_Id) is
      begin
         Mark_End_Of_Analysis
           (Static_Stack_Analysis.List_Of_Nodes.Element
              (Static_Stack_Analysis.List_Of_Edges.Element (Position).Target));
      end Mark_End_Of_Analysis;

   begin
      --  Nothing else to do if the node is already marked as analyzed. If not,
      --  mark this node as analyzed and all the nodes recursively called by
      --  this one.

      if not Node.Analysis_Finished then
         Node.Analysis_Finished := True;

         Static_Stack_Analysis.List_Of_Edges.Iterate
           (Node.Target_Calls, Mark_End_Of_Analysis'Access);
      end if;
   end Mark_End_Of_Analysis;

end Call_Graphs;
