------------------------------------------------------------------------------
--                        STATIC STACK ANALYSIS TOOL                        --
--                                                                          --
--                           G L O B A L _ D A T A                          --
--                                                                          --
--                                 S p e c                                  --
--                                                                          --
--                     Copyright (C) 2005-2010, AdaCore                     --
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

   Cycles : Static_Stack_Analysis.List_Of_Cycles.Set :=
     Static_Stack_Analysis.List_Of_Cycles.Empty_Set;
   --  List of paths corresponding to the different cycles that have been
   --  detected, and that can be reached from any entry point.

   -----------------
   -- Subprograms --
   -----------------

   List_Of_Subprograms : Static_Stack_Analysis.List_Of_Nodes.Set :=
     Static_Stack_Analysis.List_Of_Nodes.Empty_Set;
   --  List of all nodes under analysis

   -------------
   -- Classes --
   -------------

   List_Of_Classes : Static_Stack_Analysis.List_Of_Classes.Set :=
     Static_Stack_Analysis.List_Of_Classes.Empty_Set;
   --  List of all classes under analysis

   -------------
   -- Methods --
   -------------

   List_Of_Methods : Static_Stack_Analysis.List_Of_Virtual_Methods.Set :=
     Static_Stack_Analysis.List_Of_Virtual_Methods.Empty_Set;
   --  List of all virtual methods under analysis
   -------------
   -- Tasking --
   -------------

   Ada_Tasking_Used : Boolean := False;
   --  Set to True when Ada tasking is used

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

   type Phase_Type is (Parse, Call_Graph_Analysis, Print_Warnings,
                       Worst_Case_Analysis, Print_Results);
   --  Type for Phase variable

   Phase : Phase_Type;
   --  Variable that indicates the phase of the analysis in which we are

   ----------------
   -- Statistics --
   ----------------

   type Entities is (Subprogram, Call_To_Subprogram, Cycle);
   --  Main entities to be analyzed

   Entities_Processed : array (Entities) of Natural := (others => 0);
   --  Number of subprograms, calls-to-subprogram, and cycles taken into
   --  account for the different parts of the analysis.

end Global_Data;
