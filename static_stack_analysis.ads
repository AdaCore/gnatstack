------------------------------------------------------------------------------
--                        STATIC STACK ANALYSIS TOOL                        --
--                                                                          --
--                 S T A T I C _ S T A C K _ A N A L Y S I S                --
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

with Ada.Containers.Vectors;
with Ada.Containers.Ordered_Sets;

package Static_Stack_Analysis is

   -------------------------
   -- Subprogram location --
   -------------------------

   type Subprogram_Name is access all String;
   --  Type that contains the symbol name for the node

   Indirect_Call : constant Subprogram_Name;
   --  String used for identifying indirect calls

   type Location is record
      File          : Subprogram_Name;
      --  Name of the file that contains the node (subprogram)

      Demangled     : Subprogram_Name;
      --  Demangled name for the subprogram

      Line_Number   : Natural;
      --  Line number for the subprogram

      Column_Number :  Natural;
      --  Column number for the subprogram
   end record;
   --  Record used for representing locations in a source file using
   --  quadruplets (file_name, demangled_name, line_number, column_number).

   function "=" (Left, Right : Location) return Boolean;

   function Alphabetical_Order (Left, Right : Location) return Boolean;

   Null_Location : constant Location;
   --  Identifier to be used when the location is not specified

   package List_Of_Locations is new
     Ada.Containers.Ordered_Sets (Location, Alphabetical_Order, "=");
   --  Package used for storing lists of locations

   -----------------
   -- Stack usage --
   -----------------

   type Stack_Usage is (Static, Bounded, Unbounded, Unknown);
   --  This type is used to identify whether the stack usage information that
   --  we have for a certain call is statically known at compile-time,
   --  partially known (there is a dynamic part that depends on data arguments
   --  passed to the frame, which can be bounded or unbounded), or completely
   --  unknown.

   type Frame_Size is new Natural;
   --  This type represents the static part (in bytes) that is reserved in the
   --  frame.

   type Stack_Usage_Info is record
      Frame_Type  : Stack_Usage;
      --  Flag that indicates whether stack usage can be statically,
      --  determined, or bounded, for this frame.

      Static_Usage : Frame_Size;
      --  Amount of stack statically reserved by the frame. This is the size
      --  that can be statically determined by the compiler.

      Dynamic_Usage : Frame_Size;
      --  Amount of stack dynamically used by the frame. This is the maximum
      --  bound that can be statically determined by the compiler.

      Unknown_Usage : Frame_Size;
      --
   end record;
   --  Type used to represent the amount of stack needed by a subprogram, or
   --  by a call tree, including the qualifiers for this stack usage (static,
   --  bounded, unbounded, unknown).

   Unknown_Stack_Usage : constant Stack_Usage_Info;
   --  Value indicating an unknown stack usage

   function "+" (Left, Right : Stack_Usage_Info) return Stack_Usage_Info;

   function "<" (Left, Right : Stack_Usage_Info) return Boolean;

   -------------------------
   -- Nodes (subprograms) --
   -------------------------

   type Node;
   --  Nodes represent subprograms in the call graph

   type Node_Class_Access is access all Node'Class;
   --  Classwide access type

   function Alphabetical_Order
     (Left, Right : Node_Class_Access) return Boolean;
   --  Returns True if Left is alphabetically before Right, False otherwise.
   --  It is used for ordering sets of nodes alphabetically.

   function Stack_Usage_Order
     (Left, Right : Node_Class_Access) return Boolean;
   --  Returns True if Left has a total accumulated stack usage greater than
   --  Right, False otherwise. It is used for ordering sets of nodes according
   --  to their total accumulated stack usage (in decreasing order).

   function Equal (Left, Right : Node_Class_Access) return Boolean;

   package List_Of_Nodes is
     new Ada.Containers.Ordered_Sets
       (Node_Class_Access, Alphabetical_Order, Equal);
   --  Package used for storing an ordered list of pointers to nodes
   --  representing subprograms. The nodes are ordered alphabetically
   --  (according to the program they represent).

   subtype Node_Id is List_Of_Nodes.Cursor;
   --  Unique identifier for subprograms

   function Stack_Usage_Order (Left, Right : Node_Id) return Boolean;
   --  Returns True if Left has a total accumulated stack usage greater than
   --  Right, False otherwise. It is used for ordering sets of nodes according
   --  to their total accumulated stack usage (in decreasing order).

   function Get_Node (Subprogram : String) return Node_Id;
   --  This function returns the identifier for the name of the symbol
   --  representing this subprogram (if it already exists). If the subprogram
   --  has not been registered within the list then it returns No_Element.

   List_Of_Subprograms : List_Of_Nodes.Set := List_Of_Nodes.Empty_Set;
   --  List of all nodes under analysis

   ------------------------------
   -- Edges (subprogram calls) --
   ------------------------------

   type Edge_Element is record
      Target        : Node_Id;
      --  Target node for this edge

      Point_Of_Call : Location;
      --  Location where the call associated to this edge appears

      Feasible_Call : Boolean;
      --  Flag that indicates whether the this theoretical call is feasible or
      --  not. For example, the user may mark a certain call as not possible
      --  given the operational conditions of the program.

      Under_Analysis : Boolean;
      --  Indicates whether the edge is part of the path being analyzed for
      --  obtaining the worst case stack usage. It is very useful for
      --  detecting cycles in the call graph.
   end record;

   type Edge is access all Edge_Element;
   --  Edge joins the caller to the callee. This information is stored in the
   --  caller.

   function Stack_Usage_Order (Left, Right : Edge) return Boolean;
   --  We will order the different calls according to the accumulated stack
   --  usage (in decreasing order) that we get going through this path.

   package List_Of_Edges is new Ada.Containers.Vectors (Natural, Edge);
   --  Package used for storing a singly-linked list of edges for a given
   --  subprogram.

   subtype Edge_Id is List_Of_Edges.Cursor;
   --  Unique identifier for calls. They are unique within each subprogram

   ----------
   -- Path --
   ----------

   type Path_Element is record
      Source_Node : Node_Id;
      Call_To     : Edge_Id;
   end record;
   --  An element of a path (or call chain) is represented as a set of couples
   --  made up by the source node and the edge that represent the call from
   --  this node to the next.

   package Paths is new Ada.Containers.Vectors (Natural, Path_Element);
   --  Paths are represented as a set of nodes together with the calls between
   --  two adjacent nodes.

   ------------
   -- Cycles --
   ------------

   type Cycle_Element is record
      Path       : Paths.Vector;
      Iterations : Natural;
   end record;

   type Cycle is access all Cycle_Element;
   --  What identifies a cycle is the path (set of nodes and edges that make
   --  up the cycle) and the number of iterations that we consider.

   package List_Of_Cycles is new Ada.Containers.Vectors (Natural, Cycle);
   --  Package used for identifying collections of call graph cycles

   Cycles : List_Of_Cycles.Vector := List_Of_Cycles.Empty_Vector;
   --  List of paths corresponding to the different cycles that have been
   --  detected.

   ------------------
   -- Entry points --
   ------------------

   function "=" (Left, Right : Node_Id) return Boolean;

   package List_Of_Entry_Points is new
     Ada.Containers.Vectors (Natural, Node_Id, "=");

   Entry_Points : List_Of_Entry_Points.Vector :=
     List_Of_Entry_Points.Empty_Vector;
   --  List of nodes to be used as entry points in the partition. They are
   --  the roots for computing the call graphs.

   -------------------
   -- Abstract node --
   -------------------

   type Node is abstract tagged
      record
         Target_Calls : List_Of_Edges.Vector;
         --  Target_Calls represent the set of possible nodes that can be
         --  called from this node (frame).
         --  This list will be ordered according to stack usage.

         Accumulated_Stack_Usage : Stack_Usage_Info;
         --  Stack usage for the current node, including stack requirements
         --  for the nodes that can be called from this node.

         Under_Analysis : Boolean;
         --  Indicates whether the node is part of the path being analyzed for
         --  obtaining the worst case stack usage. It is very useful for
         --  detecting cycles in the call graph.

         Cycles : List_Of_Cycles.Vector;
         --  A node may be part of different cycles in the call graph, and
         --  this field contains the set of cycles to which this node belongs.
      end record;
   --  The only information that is required for every node is  the
   --  accumulated stack information, including the pointer to the next node
   --  belonging to the longest path, which is very practical if we want to
   --  retrieve partial stack requirements. There is a boolean variable which
   --  indicates whether the node is part of the path currently under analysis.
   --  Nodes contain also the set of cycles in the call graph to which they
   --  belong so we can take that information into account when analyzing the
   --  longest paths.
   --
   --  For the purpose of generating a call graph, we can distinguish several
   --  types of calling methods:
   --
   --    * Explicit calls in which the target subprogram is unambiguously
   --      determined at compile-time.
   --
   --    * Dispatching calls are those which cannot be uniquely determined
   --      at compile-time because it uses the dynamic dispatching capability
   --      provided by class-wide types.
   --
   --    * Access_To_Subprogram calls are the result of dereferences of
   --      access-to-subprogram values, and hence their target depend on
   --      the values stored in the pointer.
   --
   --    * Unresolved calls are those for which there is no information about
   --      its stack usage nor about subprograms that are called from
   --      this node.

   function Get_Stack_Usage
     (Target : Node) return Stack_Usage_Info is abstract;
   --  This function returns the stack requirements for the specified frame

   function Get_Subprogram_Name
     (Target : Node) return Subprogram_Name is abstract;
   --  This function returns the name of the subprogram associated to the
   --  specified node.

   function Get_Location_List
     (Target : Node) return List_Of_Locations.Set is abstract;
   --  This function returns the list of locations (file, demangled, line,
   --  column) where the associated subprogram is defined.

   function Get_Accumulated_Stack_Usage
     (Target : Node) return Stack_Usage_Info;
   --  This function returns the accumulated stack requirements for longest
   --  path, in terms of stack usage, that can be followed starting from the
   --  specified node.

   ---------------
   -- Real_Node --
   ---------------

   type Real_Node is abstract new Node with
      record
         Location_List : List_Of_Locations.Set;
         --  List of places where the subprogram appears. This list of
         --  locations will typically contain just one entry, and it will
         --  contain a list of more than one location in the case of
         --  instantiations of generic units.

         Subprogram    : Subprogram_Name;
         --  Name of the symbol representing this subprogram
      end record;
   --  Node representing  real nodes (explicit and unresolved). We need to
   --  store the list of candidate target nodes that may correspond to this
   --  call.

   overriding function Get_Subprogram_Name
     (Target : Real_Node) return Subprogram_Name;
   --  This function returns the name of the subprogram associated to an
   --  real (explicit or unresolved) node.

   overriding function Get_Location_List
     (Target : Real_Node) return List_Of_Locations.Set;
   --  This function returns the list of locations (file, demangled, line,
   --  column) where the associated subprogram is defined for a real
   --  (explicit or unresolved) node.

   -------------------
   -- Explicit_Node --
   -------------------

   type Explicit_Node is new Real_Node with
      record
         Stack_Info    : Stack_Usage_Info;
         --  Stack requirements for this specific frame
      end record;
   --  Node representing subprogram unambiguously determined at compile-time.
   --  The compiler hence knows the associated symbol name, the place where
   --  the subprogram appears in the source code, and it may have some
   --  information about stack requirements.

   overriding function Get_Stack_Usage
     (Target : Explicit_Node) return Stack_Usage_Info;
   --  This function returns the stack requirements for an explicit node

   not overriding procedure Update_Stack_Usage
     (Target : in out Explicit_Node; Stack_Usage : Stack_Usage_Info);
   --  Incorporate the stack usage information for an explicit node

   ---------------------
   -- Unresolved_Node --
   ---------------------

   type Unresolved_Node is new Real_Node with null record;
   --  Unresolved calls are those for which there is no information about its
   --  stack usage nor about subprograms that are called from this node. We
   --  know the name of the symbol and the place where the subprogram appears.

   overriding function Get_Stack_Usage
     (Target : Unresolved_Node) return Stack_Usage_Info;
   --  This function returns the stack requirements for the any unresolved node

   ---------------
   -- Fake_Node --
   ---------------

   type Fake_Node is abstract new Node with null record;
   --  Node representing  fake nodes (dispatching and indirect). We need to
   --  store the list of candidate target nodes that may correspond to this
   --  call.

   overriding function Get_Stack_Usage
     (Target : Fake_Node) return Stack_Usage_Info;
   --  This function returns the stack requirements for the any fake node

   overriding function Get_Subprogram_Name
     (Target : Fake_Node) return Subprogram_Name;
   --  This function returns the name of the subprogram associated to a fake
   --  node.

   overriding function Get_Location_List
     (Target : Fake_Node) return List_Of_Locations.Set;
   --  This function returns the list of locations (file, demangled, line,
   --  column) where the associated subprogram is defined for a fake node.

   ----------------------
   -- Dispatching_Node --
   ----------------------

   type Dispatching_Node is new Fake_Node with null record;
   --  Dispatching calls are those which cannot be uniquely determined at
   --  compile-time because it uses the dynamic dispatching capability
   --  provided by class-wide types.

   -------------------
   -- Indirect_Node --
   -------------------

   type Indirect_Node is new Fake_Node with null record;
   --  Indirect calls are the result of dereferences of access-to-subprogram
   --  values, and hence their target depend on the values stored in the
   --  pointer.

private

   Indirect_Call : constant Subprogram_Name := new String'("__indirect_call");

   Null_Location : constant Location := (null, null, 0, 0);

   Unknown_Stack_Usage : constant Stack_Usage_Info :=
     (Frame_Type    => Unknown,
      Static_Usage  => 0,
      Dynamic_Usage => 0,
      Unknown_Usage => 0);

end Static_Stack_Analysis;
