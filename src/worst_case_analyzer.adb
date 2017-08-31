------------------------------------------------------------------------------
--                        STATIC STACK ANALYSIS TOOL                        --
--                                                                          --
--                   W O R S T _ C A S E _ A N A L Y Z E R                  --
--                                                                          --
--                                 B o d y                                  --
--                                                                          --
--                     Copyright (C) 2005-2017, AdaCore                     --
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

with Global_Data;
with Options;
with Display;
with Ada.Text_IO;

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

   procedure Worst_Case_For_Entry
        (Position : Static_Stack_Analysis.List_Of_Node_Ids.Cursor);
      --  Compute the worst case stack usage starting from the indicated entry
      --  point.

   procedure Worst_Case_For_Subprogram
     (Position : Static_Stack_Analysis.Node_Id);
   --  Compute the worst case stack usage starting from the indicated
   --  subprogram.

   procedure Worst_Case_For_Call (Position : Static_Stack_Analysis.Edge_Id);
   --  Compute the worst case stack usage starting from the indicated call

   ------------------------
   -- Compute_Worst_Case --
   ------------------------

   procedure Worst_Case_For_Entry
     (Position : Static_Stack_Analysis.List_Of_Node_Ids.Cursor) is
   begin
      --  Analyze the indicated node

      Worst_Case_For_Subprogram
        (Static_Stack_Analysis.List_Of_Node_Ids.Element (Position));
   end Worst_Case_For_Entry;

   procedure Worst_Case_For_Subprogram
     (Position : Static_Stack_Analysis.Node_Id)
   is
      Explored_Node : constant Static_Stack_Analysis.Node_Class_Access :=
        Static_Stack_Analysis.List_Of_Nodes.Element (Position);

      use Static_Stack_Analysis;

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

            --  Iterate over every call from this node

            Static_Stack_Analysis.List_Of_Edges.Iterate
              (Explored_Node.Target_Calls, Worst_Case_For_Call'Access);

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
   end Worst_Case_For_Subprogram;

   procedure Worst_Case_For_Call (Position : Static_Stack_Analysis.Edge_Id)
   is
      Explored_Edge : constant Static_Stack_Analysis.Edge :=
        Static_Stack_Analysis.List_Of_Edges.Element (Position);

   begin
      if Options.Progress_Information then
         Display.Increase_Count (Global_Data.Analyze_Call);
      end if;

      --  Mark it under analysis

      Explored_Edge.Under_Analysis := True;

      --  Analyze the node to which this call points

      Worst_Case_For_Subprogram (Explored_Edge.Target);

      --  Mark the end of the analysis for this edge

      Explored_Edge.Under_Analysis := False;
   end Worst_Case_For_Call;

   ----------------------
   -- Get_Longest_Path --
   ----------------------

   procedure Get_Longest_Path
     (Path   : in out Static_Stack_Analysis.Paths.Vector;
      Target : Static_Stack_Analysis.Node_Id)
   is
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

      Static_Stack_Analysis.List_Of_Node_Ids.Iterate
        (Global_Data.Entry_Points, Worst_Case_For_Entry'Access);

      if Options.Progress_Information then
         --  Make sure that analysis is displayed as finished

         Global_Data.Expected_Entities (Global_Data.Analyze_Call) :=
           Global_Data.Entities_Processed (Global_Data.Analyze_Call);

         --  -1 because it will be later increased by 1

         Global_Data.Entities_Processed (Global_Data.Analyze_Call) :=
           Global_Data.Entities_Processed (Global_Data.Analyze_Call) - 1;

         --  Force printing

         Display.Increase_Count (Global_Data.Analyze_Call);

         Ada.Text_IO.New_Line;
      end if;

   end Worst_Case_Analysis;

end Worst_Case_Analyzer;
