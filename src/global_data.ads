------------------------------------------------------------------------------
--                        STATIC STACK ANALYSIS TOOL                        --
--                                                                          --
--                           G L O B A L _ D A T A                          --
--                                                                          --
--                                 S p e c                                  --
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

with Static_Stack_Analysis;
--  Used for List_Of_Cycles
--           List_Of_Nodes
--           List_Of_Node_Ids

package Global_Data is

   -------------------------------
   -- Unaccuracies in the graph --
   --------------------------------

   Unbounded_Frames : Boolean := False;
   --  Flag indicating whether there is a subprogram that can be reached from
   --  any entry point whose stack usage cannot be bounded at compile-time
   --  because it depends on data arguments passed to the frame.

   External_Calls : Boolean := False;
   --  Flag indicating whether there is a subprogram that can be reached from
   --  any entry point for which we have neither stack usage not call graph
   --  information.

   Indirect_Calls : Boolean := False;
   --  Flag indicating whether there is a subprogram that can be reached from
   --  any entry point that represents an indirect (including dispatching)
   --  call.

   Cycles : Static_Stack_Analysis.List_Of_Cycles.Vector :=
     Static_Stack_Analysis.List_Of_Cycles.Empty_Vector;
   --  List of paths corresponding to the different cycles that have been
   --  detected.

   -----------------
   -- Subprograms --
   -----------------

   List_Of_Subprograms : Static_Stack_Analysis.List_Of_Nodes.Set :=
     Static_Stack_Analysis.List_Of_Nodes.Empty_Set;
   --  List of all nodes under analysis

   function Is_Task_Entry
     (Name : Static_Stack_Analysis.Name) return Boolean;
   --  Returns True if the node corresponds to a task entry

   Task_Wrapper : Static_Stack_Analysis.List_Of_Nodes.Cursor :=
     Static_Stack_Analysis.List_Of_Nodes.No_Element;
   --  When we have a tasking program the task wrapper is the one that calls
   --  the code belonging to the different tasks so we need to take into
   --  account this information for computing stack usage for all the tasks.

   ------------------
   -- Entry points --
   ------------------

   Entry_Points : Static_Stack_Analysis.List_Of_Node_Ids.Vector :=
     Static_Stack_Analysis.List_Of_Node_Ids.Empty_Vector;
   --  List of nodes to be used as entry points in the partition. They are
   --  the roots for computing the call graphs.

   ------------------------
   -- Phases of analysis --
   ------------------------

   type Phase_Type is (Parse, Accuracy_Analysis, Print_Warnings,
                       Worst_Case_Analysis, Print_Results);
   --  Type for Phase variable

   Phase : Phase_Type;
   --  Variable that indicates the phase of the analysis in which we are

end Global_Data;
