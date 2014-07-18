.. _Examples:

********
Examples
********

This section contains a number of examples of the use of
GNATstack showing how to use the tool and how to interpret
the results. Let us start analyzing a simple program like the
following:

.. code-block:: ada

  procedure Main_Unit is
     type Data_Type is array (1 .. 5) of Integer;

     function Inverse (Input : Data_Type) return Data_Type is
        Result : Data_Type;
     begin
        for Index in Data_Type'Range loop
           Result (Index) := Input (Data_Type'Last -
                                    (Index - Data_Type'First));
        end loop;

        return Result;
     end Inverse;

     Data   : Data_Type := (1, 2, 3, 4, 5);
     Result : Data_Type;
  begin
     Result := Inverse (Data);
  end Main_Unit;  

A typical project file would contain the flags to compile the
application with the required options to generate stack consumption
and call-graph information. In addition, it would contain the desired
option for the stack analysis phase:

.. code-block:: ada

  project Prj is
     for Main use ("main_unit.adb");

     package Compiler is
        for Default_Switches ("Ada") use ("-fcallgraph-info=su");
     end Compiler;

     package Stack is
        for Switches use ("-p");
     end Stack;
  end Prj;

We can then easily compile and analyze the application using this
project file::

  $ gnatmake -P prj.gpr
  [...]
  $ gnatstack -P prj.gpr
  Accumulated stack usage information for entry points

  main : total 376 bytes
   +-> main
   +-> main_unit
   +-> main_unit.inverse

Note that we do not need to specify the :file:`.ci` files for the
application. *gnatstack* computes automatically this list from
the project file. In addition, the main entry point has also been automatically
detected by GNATstack.

The execution of the tool tells that the longest path (in terms of
stack consumption) is that made up by `main` (the program entry
point) -> `main_unit` (the main Ada program) ->
`main_unit.inverse`. The maximum stack
consumption following this path is 376 bytes, and this bound can be
trusted.

Focusing on the capability of detecting problems related to the
computation of stack requirements we can use the following example:

.. code-block:: ada

  package Ext is
     procedure Set_Alignment (Minimum : Integer);
     function Get_Size (Value : Integer) return Integer;
  end Ext;

  package body Ext is
     Threshold : Integer;

     procedure Set_Alignment (Minimum : Integer) is
     begin
        Threshold := Minimum;
     end Set_Alignment;

     function Get_Size (Value : Integer) return Integer is
     begin
        return (((Value - 1) / Threshold) + 1) * Threshold;
     end Get_Size;
  end Ext;

  with Ext;
  --  Ext is compiled without stack usage information

  procedure P is
     Set_Alignment : access procedure (Minimum : Integer) :=
       Ext.Set_Alignment'Access;
     --  Indirect call

     procedure R;

     procedure Q is
        Data : array (1 .. Ext.Get_Size (10)) of Character;
        --  Dynamically sized local objects
     begin
        R;
     end Q;

     procedure R is
     begin
        Q;
     end R;
  begin
     --  Set minimum alignment (via indirect call)
     Set_Alignment.all (Integer'Alignment);

     --  Recursion: Q -> R -> Q
     Q;
  end P;

To compile and analyze this program we do::

  $ gcc -c ext.adb
  $ gnatmake p.adb -cargs -fcallgraph-info=su,da
  [...]
  $ gnatstack *.ci
  [...]
  Worst case analysis is *not* accurate because of cycles, unbounded frames,
  external calls, indirect calls. Use -Wa for details.

  Accumulated stack usage information for entry points

  main : total 472+? bytes
   +-> main
   +-> p
   +-> p.q *
   +-> p.r *

The result of the analysis is not accurate. As indicated in the warning
message, we can check which is the origin of this inaccuracy using the
*-W* option. Additional information can be extracted increasing
the verbosity level. Adding the *-v* option will also print
detailed information about the location of the different subprograms
and per-subprogram stack requirements::

  $ gnatstack -Wa -v -p *.ci
  [...]

  List of reachable cycles:

  <c1> p.q
   +-> p.q at Q:p.adb:11:14 : 144+? bytes (unbounded,cycle) (<c1>)
   +-> p.r at R:p.adb:9:14 : 104+? bytes (cycle) (<c1>)
   +-> p.q at Q:p.adb:11:14 : 144+? bytes (unbounded,cycle) (<c1>)

  List of reachable subprograms with dynamic unbounded frames:

    In p.q at Q:p.adb:11:14
      Data at p.adb:12

  List of reachable external subprograms:

    ext.get_size at Get_Size:ext.ads:3:13

  List of indirect (including dispatching) calls:

    1 indirect calls in: p at P:p.adb:4:11
      at p.adb:24

  Accumulated stack usage information for entry points

  main : total 472+? bytes (unbounded,cycle)
   +-> main at main:b~p.ads:24:14 : 112 bytes
   +-> p at ada_main_program:b~p.adb:28:17,P:p.adb:4:11 : 112 bytes
   +-> p.q at Q:p.adb:11:14 : 144+? bytes (unbounded,cycle) (<c1>)
   +-> p.r at R:p.adb:9:14 : 104+? bytes (cycle) (<c1>)

We can see that the result is not accurate because there is recursion,
dynamic frames, and symbols for which there is no stack
usage information.

GNATstack has detected one cycle in the call graph (`Q`
calling `R` which in turn calls `Q`). The cycle has been
tagged as `<c1>` for later references. The following section of the
report indicates that the use of a dynamically sized local object
(`Data`) derives into a dynamic unbounded frame (subprogram
`Q`). We then have the list of subprograms for which there is no
stack usage information (package `Ext` has been compiled without
the required flags). Finally, there is a list of locations where there
is an indirect call.

Looking at the information about entry points we can see that the
computed stack requirements for the `main` entry point is 472
bytes. However, this result is not accurate (as indicated by the mark
`+?`), and we see that the two problems that have been found is
the existence of cycles and unbounded frames.

The call chain information provides more detailed information about
the subprograms that are part of a cycle (`Q` and `R` in
this case), and the dynamic size of the frame for subprogram `Q`.
