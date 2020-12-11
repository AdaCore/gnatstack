------------------------------------------------------------------------------
--                        STATIC STACK ANALYSIS TOOL                        --
--                                                                          --
--                 S T A T I C _ S T A C K _ A N A L Y S I S                --
--                                                                          --
--                                 S p e c                                  --
--                                                                          --
--                     Copyright (C) 2005-2020, AdaCore                     --
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

with Ada.Containers.Vectors;
with Ada.Containers.Ordered_Sets;

with GNAT.Strings;

package Static_Stack_Analysis is

   ------------
   -- Errors --
   ------------

   Parser_Error : exception;
   --  Exception to be raised when unexpected data is found

   ---------------
   -- Locations --
   ---------------

   type Name is new GNAT.Strings.String_Access;
   --  Type that contains the name (for a subprogram or an object)

   type File_Name is new GNAT.Strings.String_Access;
   --  Type that contains the name of a file

   Indirect_Call : constant Name;
   --  String used for identifying indirect calls

   type Location is record
      File          : File_Name;
      --  Name of the file that contains the item

      Demangled     : Name;
      --  Demangled name for the item

      Line_Number   : Natural;
      --  Line number for the item

      Column_Number :  Natural;
      --  Column number for the item
   end record;
   --  Record used for representing locations in a source file using
   --  quadruplets (file_name, demangled_name, line_number, column_number).

   function "=" (Left, Right : Location) return Boolean;

   function Alphabetical_Order (Left, Right : Location) return Boolean;

   Null_Location : constant Location;
   --  Identifier to be used when the location is not specified

   package List_Of_Locations is new
     Ada.Containers.Ordered_Sets (Location, Alphabetical_Order, "=");
   --  Package used for storing lists of locations. They are ordered
   --  alphabetically.

   -----------------
   -- Stack usage --
   -----------------

   type Stack_Usage is (Static, Bounded, Unbounded, Unknown);
   --  This type is used to identify whether the stack usage information that
   --  we have for a certain call is statically known at compile-time,
   --  partially known (there is a dynamic part that depends on data arguments
   --  passed to the frame, which can be bounded or unbounded), or completely
   --  unknown.

   Empty_Value : constant := -2;
   --  Indicates that the stack requirements are known to be zero. For example,
   --  it applies when there are no unbounded frames, the part about unbounded
   --  is known to be zero.

   Unspecified_Value : constant := -1;
   --  Indicates that the stack requirements have not been specified, but they
   --  are needed.

   type Frame_Size is new Integer range Empty_Value ..  Integer'Last;
   --  This type represents the static part (in bytes) that is reserved in the
   --  frame.

   function "+" (Left, Right : Frame_Size) return Frame_Size;

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
      --  Amount of stack to be attributed to frames without stack information

      Cycle_Usage : Frame_Size;
      --  Amount of stack to be attributed to call graph cycles
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

   type Node is tagged;
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
   --  Equality operation between two nodes. They are equal if they contain
   --  the same information (subprogram name, calls, etc.).

   package List_Of_Nodes is
     new Ada.Containers.Ordered_Sets
       (Node_Class_Access, Alphabetical_Order, Equal);
   --  Package used for storing an ordered list of pointers to nodes
   --  representing subprograms. The nodes are ordered alphabetically
   --  (according to the program they represent).

   subtype Node_Id is List_Of_Nodes.Cursor;
   --  Unique identifier for subprograms

   function "=" (Left, Right : Node_Id) return Boolean;

   package List_Of_Node_Ids is new Ada.Containers.Vectors (Natural, Node_Id);
   --  Package used for storing lists of Node_Ids

   function Stack_Usage_Order (Left, Right : Node_Id) return Boolean;
   --  Returns True if Left has a total accumulated stack usage greater than
   --  Right, False otherwise. It is used for ordering sets of nodes according
   --  to their total accumulated stack usage (in decreasing order).

   function Get_Node (Subprogram : String) return Node_Id;
   --  This function returns the identifier for the name of the symbol
   --  representing this subprogram (if it already exists). If the subprogram
   --  has not been registered within the list then it returns No_Element.

   ------------------------------
   -- Edges (subprogram calls) --
   ------------------------------

   type Edge_Element is record
      Ada_File_Name : File_Name;
      --  Name of the Ada file where this call appears

      Target        : Node_Id;
      --  Target node for this edge

      Point_Of_Call : List_Of_Locations.Set;
      --  Set of locations where the call associated to this edge appears.
      --  There may be more than one location because the caller may make
      --  multiple calls to a certain callee.

      Feasible_Call : Boolean;
      --  Flag that indicates whether the this theoretical call is feasible or
      --  not. For example, the user may mark a certain call as not possible
      --  given the operational conditions of the program.

      Under_Analysis : Boolean;
      --  Indicates whether the edge is part of the path being analyzed for
      --  obtaining the worst case stack usage. It is very useful for
      --  detecting and handling cycles in the call graph.
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
      --  Subprogram

      Call_To     : Edge_Id;
      --  Call-to-subprogram
   end record;
   --  An element of a path (or call chain) is represented as a set of couples
   --  made up by the source node and the edge that represent the call from
   --  this node to the next.

   function Equal (Left, Right : Path_Element) return Boolean;
   --  Equality operation between two path elements. They are equal if the
   --  content is the same.

   package Paths is new Ada.Containers.Vectors (Natural, Path_Element, Equal);
   --  Paths are represented as a set of nodes together with the calls between
   --  two adjacent nodes.

   ------------
   -- Cycles --
   ------------

   type Cycle_Element is record
      Id         : Natural;
      --  Unique identifier

      Path       : Paths.Vector;
      --  Subprograms that make up the call graph cycle

      Iterations : Natural;
      --  Upper bound to the number of times the cycle is executed
   end record;

   type Cycle is access all Cycle_Element;
   --  What identifies a cycle is the path (set of nodes and edges that make
   --  up the cycle) and the number of iterations that we consider.

   Empty_Cycle : constant Cycle_Element;
   --  Cycle with no elements inside

   procedure Normalize (Target : Cycle);
   --  Modify the call graph that represents the cycle in a way that the first
   --  element contains the first subprogram in alphabetical order.
   --  When analyzing whether a cycle has already been detected we need to
   --  compare two paths, and this process is simpler if there is some order in
   --  the way the path is represented.

   function "=" (Left, Right : Cycle) return Boolean;

   function Alphabetical_Order (Left, Right : Cycle) return Boolean;

   package List_Of_Cycles is new
     Ada.Containers.Ordered_Sets (Cycle, Alphabetical_Order, "=");
   --  Package used for identifying collections of call graph cycles. Cycles
   --  are ordered alphabetically.

   -----------
   -- Class --
   -----------

   type Class;
   type Class_Access is access all Class;

   function Alphabetical_Order (Left, Right : Class_Access) return Boolean;
   --  Returns True if Left is alphabetically before Right, False otherwise.
   --  It is used for ordering sets of classes alphabetically.

   function Equal (Left, Right : Class_Access) return Boolean;
   --  Equality operation between two classes. They are equal if they contain
   --  the same information (name, methods, etc.).

   function Get_Class (Class_Name : String) return Class_Access;
   --  Retrieve a class using its encoded (mangled) name. Return null if the
   --  class is not yet in the list.

   function Insert_Class
     (Symbol : String;
      Defined : Boolean;
      Loc : List_Of_Locations.Set := List_Of_Locations.Empty_Set)
      return Class_Access;
   --  Insert the class. It creates the descriptor for the class if it has
   --  not yet been registered, or return the existing one. Defined is True
   --  when the class is being defined (therefore we expect more information
   --  to be present) and False when it is only being referenced by another
   --  class.

   package List_Of_Classes is new
     Ada.Containers.Ordered_Sets (Class_Access, Alphabetical_Order, Equal);
   --  Types used to represent classes (tagged types)

   type Method is tagged;
   type Method_Class_Access is access all Method'Class;
   --  Root class to represent dispatching methods. There are either virtual
   --  or inherited methods.

   type Virtual is tagged;
   type Virtual_Class_Access is access all Virtual'Class;

   function Alphabetical_Order
     (Left, Right : Virtual_Class_Access) return Boolean;
   --  Order by the name of the owner class, and then by the slot number
   --  It is used for ordering sets of virtual methods alphabetically.

   function Equal (Left, Right : Virtual_Class_Access) return Boolean;
   --  Equality operation between two virtual methods. They are equal if they
   --  contain the same information (name, slot, etc.).

   package List_Of_Virtual_Methods is new
     Ada.Containers.Ordered_Sets
       (Virtual_Class_Access, Alphabetical_Order, Equal);

   type Inherited is tagged;
   type Inherited_Class_Access is access all Inherited'Class;

   type Slot_Number is new Integer;
   --  Type which represents the position in the dispatching table of the
   --  different virtual methods.

   Null_Slot : constant Slot_Number := Slot_Number'First;
   --  Constant defining a non valid slot (the most negative value)

   type Vtable_Loc is
      record
         Class : Class_Access;
         Slot  : Slot_Number;
      end record;
   --  Type used to identify virtual methods. It contains the class that
   --  defines it (and hence the vtable) and its slot in the vtable.

   Null_Vtable_Loc : constant Vtable_Loc := Vtable_Loc'(null, Null_Slot);
   --  Constant defining a non valid pair class:slot

   function "<" (Left, Right : Vtable_Loc) return Boolean;

   type Method is abstract tagged
      record
         Method_Name : Name;
         --  Name of the method
      end record;

   type Virtual is new Method with
      record
         Symbol_Name : Name;
         --  Associated symbol (in the object code) for the method

         Vtable_Entry : Vtable_Loc;
         --  Class (tagged type) and position in the dispatching table that
         --  define the method.

         Redefines : Vtable_Loc;
         --  Class and slot which this method is overriding. Null if this is
         --  not an overridden method. This may point either to the method
         --  in the base class (the one that defines the vtable slot) or to
         --  the method which is being directly overloaded.

         Redefines_Multiple : Vtable_Loc;
         --  When a class has multiple base classes, it has multiple vtables.
         --  When a method is overridden (that does not come from a primary
         --  base), an entry is added to the secondary vtable (corresponding
         --  to the non-primary base) and this entry is added as well to the
         --  primary vtable. Redefines_Multiple will contain the location
         --  in the primary vtable (Redefines will store the location in the
         --  secondary vtable). Null if this is not an overridden method from
         --  a non-primary base.

         Redefined_By : List_Of_Virtual_Methods.Set;
         --  List of methods which override this one. This is used to
         --  determine the set of potential targets for a dispatching call.
         --  This list may be kept in every overloaded method or just in
         --  the method defined in the base class.
      end record;
   --  Types used to represent virtual functions (primitive operations of a
   --  tagged type).

   type Inherited is new Method with
      record
         Inherits : Virtual_Class_Access;
         --  Method inherited from the ancestor
      end record;

   package List_Of_Inherited_Methods is new
     Ada.Containers.Vectors (Natural, Inherited_Class_Access);

   function Get_Method (Id : Vtable_Loc) return Virtual_Class_Access;
   --  Return the method by its class:slot information

   function Insert_Method
     (Id : Vtable_Loc; Symbol : String) return Virtual_Class_Access;
   --  Insert the method. It creates the descriptor for the method if it has
   --  not yet been registered, or return the existing one.

   type Class is
      record
         Class_Name : Name;
         --  Name of the class (tagged type)

         Class_Loc  : List_Of_Locations.Set;
         --  Demangled name and file location for the class

         Primary_Parent : Class_Access;
         --  Identifier for the primary parent of the class. ??? This field can
         --  be probably removed when the compiler generates the information
         --  about the actual method overloaded.

         Parents    : List_Of_Classes.Set;
         --  List of direct parents.

         Derived    : List_Of_Classes.Set;
         --  List of all classes derived from this one. It does not contain
         --  only the direct descencent (children), but derived through the
         --  complete hierarchy (include grandchildren, ...).

         Virtual    : List_Of_Virtual_Methods.Set;
         --  List of virtual methods defined by the class (both new methods
         --  and overriding ones).
      end record;

   -------------------
   -- Abstract node --
   -------------------

   type Node is abstract tagged
      record
         Ada_File_Name : File_Name;
         --  Name of the Ada file where this subprogram is defined

         Location_List : List_Of_Locations.Set;
         --  List of places where the subprogram appears. This list of
         --  locations will typically contain just one entry, and it will
         --  contain a list of more than one location in the case of
         --  instantiations of generic units.

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
         --  detecting and handling cycles in the call graph.

         Analysis_Finished : Boolean;
         --  Indicates whether we already have analyzed all the call graphs
         --  (including cycles) to which this node belongs. Once this flag is
         --  set to True, any analysis arriving to this node can stop.

         Is_Called : Boolean;
         --  Indicates whether this subprogram is directly accessible from any
         --  other.

         Is_Reachable : Boolean;
         --  Indicates whether this subprogram can be reached from at least
         --  one entry point.

         Cycles : List_Of_Cycles.Set;
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
     (Target : Node) return Name is abstract;
   --  This function returns the name of the subprogram associated to the
   --  specified node.

   function Get_Demangled_Name
     (Target : Node) return Name is abstract;
   --  This function returns the demangled name of the subprogram associated
   --  to the specified node.

   function Get_Location_List (Target : Node) return List_Of_Locations.Set;
   --  This function returns the list of locations (file, demangled, line,
   --  column) where the associated subprogram is defined.

   function Get_Accumulated_Stack_Usage
     (Target : Node) return Stack_Usage_Info;
   --  This function returns the accumulated stack requirements for longest
   --  path, in terms of stack usage, that can be followed starting from the
   --  specified node.

   function Get_Dynamic_Objects
     (Target : Node) return List_Of_Locations.Set is abstract;
   --  This function returns the list of locations (file, demangled, line,
   --  column) where dynamic objects are defined (if any) within the
   --  subprogram represented.

   type Indirect_Calls is (Access_To_Subprogram, Dispatching, Both);
   --  Clasification of indirect calls according to their nature into either
   --  dereferences to access-to-subprogram, dispatching, or both.

   type Indirect_Resolution is (Unresolved, Resolved, Both);
   --  Clasification of indirect calls according to the information we have
   --  about their potential targets.

   function Get_Indirect_Calls
     (Target : Node;
      Kind   : Indirect_Calls := Both;
      Status : Indirect_Resolution := Both)
      return List_Of_Edges.Vector;
   --  This function returns the list of indirect calls made from any given
   --  subprogram. We can get either dereferences to access-to-subprogram
   --  values, or dispatching calls, or both (by default). We can get either
   --  resolved or unresolved indirect calls (or both).

   procedure Move_Indirect_Calls (Source, Target : Node_Class_Access);
   --  Procedure to move user-defined targets for indirect calls (associated
   --  to Source) into the node representing indirect calls. The location of
   --  the Target node is the one that will determine the indirect calls that
   --  need to be moved.

   function Location_Is_Dispatching (Loc : in out Location) return Boolean;
   --  Function which says whether a location corresponds to a dispatching
   --  call. The location passed as parameter may be modified because we may
   --  need to remove the file location.

   function Location_Is_Dispatching
     (Locs : in out List_Of_Locations.Set) return Boolean;
   --  Function which says whether any location in the given set corresponds
   --  to a dispatching call. The location passed as parameter may be modified
   --  because we may need to remove the file location.

   ---------------
   -- Real_Node --
   ---------------

   type Real_Node is abstract new Node with
      record
         Subprogram : Name;
         --  Name of the symbol representing this subprogram

         Demangled  : Name;
         --  Demangled name (Ada/C++) corresponding the symbol name
      end record;
   --  Node representing  real nodes (explicit and unresolved). We need to
   --  store the list of candidate target nodes that may correspond to this
   --  call.

   overriding function Get_Subprogram_Name (Target : Real_Node) return Name;
   --  This function returns the name of the subprogram associated to an
   --  real (explicit or unresolved) node.

   overriding function Get_Demangled_Name (Target : Real_Node) return Name;
   --  This function returns the demangled name of the subprogram associated
   --  to an real (explicit or unresolved) node.

   -------------------
   -- Explicit_Node --
   -------------------

   type Explicit_Node is new Real_Node with
      record
         Dynamic_Objects : List_Of_Locations.Set;
         --  List of places where dynamic objects are defined (if any) within
         --  the subprogram represented.

         Stack_Info    : Stack_Usage_Info;
         --  Stack requirements for this specific frame
      end record;
   --  Node representing subprogram unambiguously determined at compile-time.
   --  The compiler hence knows the associated symbol name, the place where
   --  the subprogram appears in the source code, and it may have some
   --  information about stack requirements (including dynamic objects).

   overriding function Get_Stack_Usage
     (Target : Explicit_Node) return Stack_Usage_Info;
   --  This function returns the stack requirements for an explicit node

   overriding function Get_Dynamic_Objects
     (Target : Explicit_Node) return List_Of_Locations.Set;
   --  This function returns the list of locations (file, demangled, line,
   --  column) where dynamic objects are defined (if any) for an explicit
   --  node.

   not overriding procedure Update_Stack_Usage
     (Target : in out Explicit_Node; Stack_Usage : Stack_Usage_Info);
   --  Incorporate the stack usage information for an explicit node

   ---------------------
   -- Unresolved_Node --
   ---------------------

   type Unresolved_Node is new Real_Node with
      record
         Alias      : Name;
         --  Points to the actual implementation of this node;
      end record;
   --  Unresolved calls are those for which there is no information about its
   --  stack usage nor about subprograms that are called from this node. We
   --  know the name of the symbol and the place where the subprogram appears.
   --  It may include aliasing information.

   overriding function Get_Stack_Usage
     (Target : Unresolved_Node) return Stack_Usage_Info;
   --  This function returns the stack requirements for an unresolved node

   overriding function Get_Dynamic_Objects
     (Target : Unresolved_Node) return List_Of_Locations.Set;
   --  This function returns the list of locations (file, demangled, line,
   --  column) where dynamic objects are defined (if any) for an unresolved
   --  node.

   ---------------
   -- Fake_Node --
   ---------------

   type Fake_Node is abstract new Node with
      record
         Internal_Name : Name;
         --  Artificial name which is used as equivalent to the symbol name.
      end record;
   --  Node representing  fake nodes (dispatching and indirect). We need to
   --  store the list of candidate target nodes that may correspond to this
   --  call.
   --  Internal name is an artificial once created concatenating a string
   --  representing either the triple base_class:slot:static_class for
   --  dispatching nodes or the indirect mark plus the caller plus its
   --  location for indirect nodes. One advantage of using this representation
   --  for dispatching nodes is that every dispatching call with the same
   --  pattern (same base and static class and same slot) will be equivalent,
   --  and will be represented by the same node, simplifying the analysis.

   overriding function Get_Stack_Usage
     (Target : Fake_Node) return Stack_Usage_Info;
   --  This function returns the stack requirements for any fake node

   overriding function Get_Subprogram_Name (Target : Fake_Node) return Name;
   --  This function returns the internal name associated to a fake node.

   overriding function Get_Demangled_Name (Target : Fake_Node) return Name;
   --  This function returns the equivalent of a demangled name of the
   --  subprogram associated to a fake node. This is the internal name, which
   --  is either the triple base_class:slot:static_class for dispatching nodes
   --  or the indirect mark plus the caller plus its location for indirect
   --  nodes.

   overriding function Get_Dynamic_Objects
     (Target : Fake_Node) return List_Of_Locations.Set;
   --  This function returns the list of locations (file, demangled, line,
   --  column) where dynamic objects are defined (if any) for a fake node.

   ----------------------
   -- Dispatching_Node --
   ----------------------

   type Dispatching_Node is new Fake_Node with
      record
         Slot          : Slot_Number;
         --  Slot used for dispatching

         Base_Class    : Class_Access;
         --  Base class being used for dispatching

         Static_Class  : Class_Access;
         --  Static view of the object
      end record;
   --  Dispatching calls are those which cannot be uniquely determined at
   --  compile-time because it uses the dynamic dispatching capability
   --  provided by class-wide types. These calls are identified by the
   --  slot number in the vtable that is used for dispatching, the base
   --  class for the dispatching call, and the static view of the object
   --  used for dispatching.

   overriding function Get_Stack_Usage
     (Target : Dispatching_Node) return Stack_Usage_Info;
   --  This function returns the stack requirements for any dispatching
   --  node.

   -------------------
   -- Indirect_Node --
   -------------------

   type Indirect_Node is new Fake_Node with null record;
   --  Indirect calls are the result of dereferences of access-to-subprogram
   --  values, and hence their target depend on the values stored in the
   --  pointer.

   overriding function Get_Stack_Usage
     (Target : Indirect_Node) return Stack_Usage_Info;
   --  This function returns the stack requirements for any indirect
   --  node.

private

   Indirect_Call : constant Name := new String'("__indirect_call");

   Null_Location : constant Location := (null, null, 0, 0);

   Unknown_Stack_Usage : constant Stack_Usage_Info :=
     (Frame_Type    => Unknown,
      Static_Usage  => Empty_Value,
      Dynamic_Usage => Empty_Value,
      Unknown_Usage => Empty_Value,
      Cycle_Usage   => Empty_Value);

   Empty_Cycle : constant Cycle_Element :=
     (Id         => 0,
      Path       => Static_Stack_Analysis.Paths.Empty_Vector,
      Iterations => 1);

end Static_Stack_Analysis;
