------------------------------------------------------------------------------
--                        STATIC STACK ANALYSIS TOOL                        --
--                                                                          --
--                           C A L L _ G R A P H S                          --
--                                                                          --
--                                 B o d y                                  --
--                                                                          --
--                     Copyright (C) 2005-2011, AdaCore                     --
--                                                                          --
-- GNATstack  is free  software;  you can redistribute  it and/or modify it --
-- under terms of the  GNU General Public License as published  by the Free --
-- Software  Foundation;  either version 3,  or (at your option)  any later --
-- version.  GNATstack is distributed  in the hope that it will be  useful, --
-- but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANT- --
-- ABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public --
-- License for  more details.  You should have  received  a copy of the GNU --
-- General Public License distributed with GNATstack; see file COPYING3. If --
-- not,  go to  http://www.gnu.org/licenses  for a  complete  copy  of  the --
-- license.                                                                 --
------------------------------------------------------------------------------

with Static_Stack_Analysis;
with Display;
with Global_Data;
with Options;

with Ada.Text_IO;

with Ada.Unchecked_Deallocation;

package body Call_Graphs is

   -----------------------
   -- Local subprograms --
   -----------------------

   procedure Analyze_Call (Position : Static_Stack_Analysis.Edge_Id);
   --  Analyze potential problems for this call (cycles, external or indirect
   --  calls, or unbounded frames).

   procedure Analyze_Node (Position : Static_Stack_Analysis.Node_Id);
   --  Analyze potential problems for this call (cycles, external or indirect
   --  calls, or unbounded frames).

   procedure Analyze_Detected_Cycle
     (Position : Static_Stack_Analysis.Node_Id);
   --  Check whether the detected cycle (the one whose root is the indicated
   --  node) is already known.

   procedure Add_Node_To_Path
     (Cycle : Static_Stack_Analysis.Cycle;
      Node  : Static_Stack_Analysis.Node_Id);
   --  This procedure adds the specified node to the cycle and annotates the
   --  node belonging to this cycle to mark that the node is part of the cycle.

   procedure Mark_Tree_End_Of_Analysis
     (Node : Static_Stack_Analysis.Node_Class_Access);
   --  Mark this node (and all the nodes recursively called by this one) as
   --  fully analyzed.

   procedure Mark_Path_End_Of_Analysis
     (From, To : Static_Stack_Analysis.Node_Id);
   --  Mark the nodes between the origin and the end as nodes that can reach
   --  a cycle. This way the cycle analysis can stop earlier.

   function Is_Entry_Point
     (Node     : Static_Stack_Analysis.Node_Class_Access;
      Position : Static_Stack_Analysis.Node_Id) return Boolean;
   --  If the indicated subprogram is a potential entry point for the
   --  application we add it to the list.

   procedure Free is new
     Ada.Unchecked_Deallocation
       (Static_Stack_Analysis.Cycle_Element, Static_Stack_Analysis.Cycle);

   ----------------
   -- Local data --
   ----------------

   Main_Found : Boolean := False;
   --  Set to True if the main Ada procedure has been found

   New_Cycle_Found : Boolean := False;
   --  Set to True if we know that the cycle is new. It is true when one
   --  subprogram in the cycle does not yet belong to any registered cycle.

   Entry_Under_Analysis : Static_Stack_Analysis.Node_Id :=
     Static_Stack_Analysis.List_Of_Nodes.No_Element;
   --  Entry point that is being analyzed

   ----------------------
   -- Add_Node_To_Path --
   ----------------------

   procedure Add_Node_To_Path
     (Cycle : Static_Stack_Analysis.Cycle;
      Node  : Static_Stack_Analysis.Node_Id)
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

      --  If the cycle under study contains a subprogram that does not yet
      --  belong to any registered cycle we are sure this is a new cycle.

      if not New_Cycle_Found and then Explored_Node.Cycles.Is_Empty then
         New_Cycle_Found := True;
      end if;

      --  Add next node to the path, if not already in the list

      Next_Node := Static_Stack_Analysis.List_Of_Edges.Element (Index).Target;

      if Next_Node /= Cycle.Path.First_Element.Source_Node then
         Add_Node_To_Path (Cycle, Next_Node);
      end if;
   end Add_Node_To_Path;

   ------------------
   -- Analyze_Node --
   ------------------

   procedure Analyze_Node (Position : Static_Stack_Analysis.Node_Id) is
      Node : constant Static_Stack_Analysis.Node_Class_Access :=
        Static_Stack_Analysis.List_Of_Nodes.Element (Position);

      use Static_Stack_Analysis;

   begin
      --  Do nothing if this node has been fully analyzed. It means that all
      --  the cycles to which it belongs are already known.

      if not Node.Analysis_Finished then
         --  First we check for cycles

         if Node.Under_Analysis then

            --  Cycle detected. It may be a new or an already detected one

            Analyze_Detected_Cycle (Position);

         else
            if Options.Progress_Information then
               Display.Increase_Count (Global_Data.Analyze_Subprogram);
            end if;

            --  Mark node as reachable

            Node.Is_Reachable := True;

            --  Mark it under analysis

            Node.Under_Analysis := True;

            --  Update accuracy information of the explored subprogram

            --  Unbounded frame
            if not Global_Data.Unbounded_Frames
              and then Node.all in Explicit_Node'Class
              and then
                Explicit_Node (Node.all).Stack_Info.Frame_Type = Unbounded
            then
               Global_Data.Unbounded_Frames := True;

            --  External call
            elsif not Global_Data.External_Calls
              and then Node.all in Unresolved_Node'Class
              and then Node.Target_Calls.Is_Empty
            then
               Global_Data.External_Calls := True;

            --  Indirect and dispatching call
            elsif not Global_Data.Indirect_Calls
              and then Node.all in Fake_Node'Class
              and then Node.Target_Calls.Is_Empty
            then
               Global_Data.Indirect_Calls := True;
            end if;

            --  Explore all the possible target calls.

            Static_Stack_Analysis.List_Of_Edges.Iterate
              (Node.Target_Calls, Analyze_Call'Access);

            --  Mark the end of the analysis for this node

            Node.Under_Analysis := False;

            --  Once all the possible calls from this subprogram have been
            --  analyzed then we can mark this node (and all the nodes called
            --  by this one) as analyzed. This is the case only if no cycles
            --  are reachable from this node (otherwise we may have not
            --  explored all the required paths).

            if Node.Cycles.Is_Empty then
               Mark_Tree_End_Of_Analysis (Node);
            end if;
         end if;
      end if;
   end Analyze_Node;

   procedure Analyze_Call (Position : Static_Stack_Analysis.Edge_Id) is
      Explored_Edge : constant Static_Stack_Analysis.Edge :=
        Static_Stack_Analysis.List_Of_Edges.Element (Position);

      Target_Node : constant Static_Stack_Analysis.Node_Class_Access :=
        Static_Stack_Analysis.List_Of_Nodes.Element (Explored_Edge.Target);

   begin
      pragma Assert (not Explored_Edge.Under_Analysis);

      --  Mark it under analysis

      Explored_Edge.Under_Analysis := True;

      --  Analyze the node to which this call points

      Analyze_Node (Explored_Edge.Target);

      --  Mark the end of the analysis for this edge

      Explored_Edge.Under_Analysis := False;

      pragma Assert (Target_Node.Is_Called);
   end Analyze_Call;

   ------------------------
   -- Analyze_Call_Graph --
   ------------------------

   procedure Analyze_Call_Graph is

      procedure Analyze_Subprogram
        (Position : Static_Stack_Analysis.Node_Id);
      --  Depending on the selected flags, this procedure will extract all the
      --  cycles that can be reached from the specified entry point, as well as
      --  undefined references, indirect calls and unbounded frames. It will
      --  also mark all reachable subprograms.

      procedure Analyze_Subprogram
        (Position : Static_Stack_Analysis.Node_Id)
      is
         Node : constant Static_Stack_Analysis.Node_Class_Access :=
           Static_Stack_Analysis.List_Of_Nodes.Element (Position);

      begin
         --  Analyze whether the subprogram is part of a cycle. We do it only
         --  for reachable cycles. During this analysis the reachable unbounded
         --  frames, external calls, and indirect calls will also be extracted.

         if Is_Entry_Point (Node, Position) and then
           not Node.Analysis_Finished
         then
            --  Start analysis from this node

            Entry_Under_Analysis := Position;

            Analyze_Node (Position);

            --  Once all the tree from this subprogram has been analyzed then
            --  we can mark this node (and all the nodes called by this one)
            --  as analyzed.

            Mark_Tree_End_Of_Analysis (Node);
         end if;
      end Analyze_Subprogram;

      Cycle_Counter : Natural := 1;

      procedure Tag_Cycle
        (Cycle : Static_Stack_Analysis.List_Of_Cycles.Cursor);
      --  Allocate unique identifiers to the cycles (their position in the
      --  global list of cycles.

      procedure Tag_Cycle
        (Cycle : Static_Stack_Analysis.List_Of_Cycles.Cursor) is
      begin
         Static_Stack_Analysis.List_Of_Cycles.Element (Cycle).Id :=
           Cycle_Counter;
         Cycle_Counter := Cycle_Counter + 1;
      end Tag_Cycle;

   --  Start of processing for Analyze_Call_Graph
   begin
      --  Iterate over all the subprograms

      Static_Stack_Analysis.List_Of_Nodes.Iterate
        (Global_Data.List_Of_Subprograms, Analyze_Subprogram'Access);

      if Options.Progress_Information then
         --  Make sure that subprogram analysis is displayed as finished

         Global_Data.Expected_Entities (Global_Data.Analyze_Subprogram) :=
           Global_Data.Entities_Processed (Global_Data.Analyze_Subprogram);

         --  -1 because it will be later increased by 1

         Global_Data.Entities_Processed (Global_Data.Analyze_Subprogram) :=
           Global_Data.Entities_Processed (Global_Data.Analyze_Subprogram) - 1;

         --  Force printing

         Display.Increase_Count (Global_Data.Analyze_Subprogram);
      end if;

      if Global_Data.Entities_Processed (Global_Data.Cycle) > 0 then
         --  Allocate unique identifiers to the cycles

         Global_Data.Cycles.Iterate (Tag_Cycle'Access);

         if not Options.Very_Quiet then
            Ada.Text_IO.New_Line;
         end if;
      end if;
   end Analyze_Call_Graph;

   ----------------------------
   -- Analyze_Detected_Cycle --
   ----------------------------

   procedure Analyze_Detected_Cycle
     (Position : Static_Stack_Analysis.Node_Id)
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

      Inserted_Cycle : Boolean;
      --  Boolean indicating whether the cycle is new or not
      Ignore : Static_Stack_Analysis.List_Of_Cycles.Cursor;

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

         use Static_Stack_Analysis;
      begin
         --  Add the cycle to the list of cycles for this node

         Element.Cycles.Insert (New_Cycle);

         --  Its stack usage includes an unspecified part because of the cycle
         if Element.all in Explicit_Node'Class then
            Explicit_Node (Element.all).Stack_Info.Cycle_Usage :=
              Static_Stack_Analysis.Frame_Size (Options.Default_Cycle);
         end if;
      end Mark_Nodes;

   begin
      --  Now we need to extract and identify this cycle. We need to
      --  follow the path marked by the Under_Analysis flag.

      Add_Node_To_Path (New_Cycle, Position);

      --  Normalize the cycle (put first the first subprogram in alphabetical
      --  order) to make comparisons between cycles easier.

      Static_Stack_Analysis.Normalize (New_Cycle);

      --  Add the new cycle to the list of detected cycles, if not there yet.
      --  The object is deleted if it is no longer used.

      Static_Stack_Analysis.List_Of_Cycles.Insert
        (Global_Data.Cycles, New_Cycle, Ignore, Inserted_Cycle);

      if not Inserted_Cycle then
         New_Cycle.Path.Clear;
         Free (New_Cycle);

      else
         --  Mark the nodes as belonging to this cycle

         New_Cycle.Path.Iterate (Mark_Nodes'Access);

         --  Increase the count of cycles analyzed

         Display.Increase_Count (Global_Data.Cycle);
      end if;

      --  If we do not want to compute all cycles we can simplify the
      --  analysis by simply finishing the analysis of subprograms that
      --  can reach a cycle.

      if not Options.Compute_All_Cycles then
         --  Update the list of nodes that can reach a cycle. We start from the
         --  entry point being analyzed until we find the cycle.

         Mark_Path_End_Of_Analysis (Entry_Under_Analysis, Position);
      end if;
   end Analyze_Detected_Cycle;

   --------------------
   -- Is_Entry_Point --
   --------------------

   function Is_Entry_Point
     (Node     : Static_Stack_Analysis.Node_Class_Access;
      Position : Static_Stack_Analysis.Node_Id) return Boolean
   is
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

   --  Start Check_Entry_Point
   begin
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
        and then Node.all in Static_Stack_Analysis.Explicit_Node'Class
        and then not Node.Is_Called
        and then
          (Options.Explore_All
           or else
             Ada_Binder_Main
           or else
             (Global_Data.Ada_Tasking_Used
              and then
                Global_Data.Is_Task_Entry
                  (Static_Stack_Analysis.Get_Subprogram_Name (Node.all))))
      then
         Global_Data.Entry_Points.Append (Position);
         return True;

      --  Check if the user has requested this subprogram to be considered as
      --  an entry point (either with a explicit list or using a regular
      --  expression).
      else
         return Global_Data.Entry_Points.Contains (Position);

      end if;
   end Is_Entry_Point;

   -------------------------------
   -- Mark_Tree_End_Of_Analysis --
   -------------------------------

   procedure Mark_Tree_End_Of_Analysis
     (Node : Static_Stack_Analysis.Node_Class_Access)
   is
      procedure Mark_End_Of_Analysis
        (Position : Static_Stack_Analysis.Edge_Id);
      --  Mark the target node as analyzed

      procedure Mark_End_Of_Analysis
        (Position : Static_Stack_Analysis.Edge_Id) is
      begin
         Mark_Tree_End_Of_Analysis
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
   end Mark_Tree_End_Of_Analysis;

   -------------------------------
   -- Mark_Path_End_Of_Analysis --
   -------------------------------

   procedure Mark_Path_End_Of_Analysis
     (From, To : Static_Stack_Analysis.Node_Id) is
      This_Node : constant Static_Stack_Analysis.Node_Class_Access :=
        Static_Stack_Analysis.List_Of_Nodes.Element (From);

      Found : Boolean := False;
      --  Set to True when the next node in the path has been found

      Next_Node : Static_Stack_Analysis.Node_Id;
      --  Next node in the path to the cycle

      Index : Static_Stack_Analysis.Edge_Id;
      --  Index used to explore calls made by this subprogram

      procedure Is_Under_Analysis (Target : Static_Stack_Analysis.Edge);
      --  Check whether the target of this call is part ot the cycle that we
      --  are analyzing.

      procedure Is_Under_Analysis (Target : Static_Stack_Analysis.Edge) is
      begin
         Found := Target.Under_Analysis;
      end Is_Under_Analysis;

      use type Static_Stack_Analysis.Node_Id;

   begin
      --  Mark until we reach the last element

      This_Node.Analysis_Finished := True;

      --  Get the edge that is under analysis. We start from the last edge
      --  because this way we consider the last path being studied.

      Index := This_Node.Target_Calls.Last;

      loop
         Static_Stack_Analysis.List_Of_Edges.Query_Element
           (Index, Is_Under_Analysis'Access);

         exit when Found;

         Static_Stack_Analysis.List_Of_Edges.Previous (Index);

         pragma Assert
           (Static_Stack_Analysis.List_Of_Edges.Has_Element (Index));
      end loop;

      --  Add next node to the path, if not already in the list

      Next_Node := Static_Stack_Analysis.List_Of_Edges.Element (Index).Target;

      if Next_Node /= To then
         Mark_Path_End_Of_Analysis (Next_Node, To);
      end if;
   end Mark_Path_End_Of_Analysis;

   ---------------------
   -- Resolve_Aliases --
   ---------------------

   procedure Resolve_Aliases is
      procedure Resolve_Alias (Position : Static_Stack_Analysis.Node_Id);
      --  If the node needs to be resolved using the alias information we do
      --  it here.

      procedure Resolve_Alias (Position : Static_Stack_Analysis.Node_Id) is
         Explored_Node : constant Static_Stack_Analysis.Node_Class_Access :=
           Static_Stack_Analysis.List_Of_Nodes.Element (Position);

         Alias_Id : Static_Stack_Analysis.Node_Id;

         use Static_Stack_Analysis;

      begin
         --  If a node with an alias attribute has not been resolved yet it
         --  means that we need to rely on the alias information to know the
         --  actual subprogram that will be called.

         if Explored_Node.all in Unresolved_Node'Class and then
           Unresolved_Node (Explored_Node.all).Alias /= null
         then
            --  Look for the alias target

            Alias_Id :=
              Get_Node (Unresolved_Node (Explored_Node.all).Alias.all);

            if List_Of_Nodes.Has_Element (Alias_Id) then
               pragma Assert (Explored_Node.Target_Calls.Is_Empty);

               --  Mark the callee as called by another one

               List_Of_Nodes.Element (Alias_Id).Is_Called := True;

               --  Create new edge to represent the alias information.

               Static_Stack_Analysis.List_Of_Edges.Append
                 (Explored_Node.Target_Calls,
                  new Static_Stack_Analysis.Edge_Element'(
                    Ada_File_Name  => Explored_Node.Ada_File_Name,
                    Target         => Alias_Id,
                    Point_Of_Call  => Explored_Node.Location_List,
                    Feasible_Call  => True,
                    Under_Analysis => False));
            end if;
         end if;
      end Resolve_Alias;

   begin
      Static_Stack_Analysis.List_Of_Nodes.Iterate
        (Global_Data.List_Of_Subprograms, Resolve_Alias'Access);
   end Resolve_Aliases;

end Call_Graphs;
