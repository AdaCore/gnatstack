.. _Getting_Started_with_GNATstack:

******************************
Getting Started with GNATstack
******************************

Two steps are needed to analyze stack usage: 1) generation of the basic
stack consumption and call-graph information, followed by 2) analysis
and report generation.

.. index:: -fcallgraph-info=su

The first step is to compile the application with the required options
to generate the information about per-subprogram stack consumption and
call-graph information. The *-fcallgraph-info=su* compiler
switch outputs this information on a per-file basis in the common VCG
format::

  $ gnatmake main_unit.adb -cargs -fcallgraph-info=su

The use of this compiler switch generates a :file:`.ci` file for every
compilation unit.

.. index:: -fcallgraph-info=da

The compiler can also generate information about dynamically allocated
objects adding the `da` marker to the `-fcallgraph-info`
compiler switch (`-fcallgraph-info=su,da`). This option helps
locating the objects that introduce potentially unbounded stack
requirements.

In the second step, GNATstack can then parse these files to generate the
complete call graph decorated with stack usage information, so it can
look for the longest paths in terms of stack usage::

  $ gnatstack *.ci
  [...]
  Accumulated stack usage information for entry points

  main : total 376 bytes
   +-> main
   +-> main_unit
   +-> process

.. _Options_for_GNATstack:

Options for GNATstack
=====================

GNATstack is configurable with respect to the amount of
information that we want to obtain. The set of options available is
the following:

*-a*
  .. index:: -a

  Consider all subprograms as entry points.

*-ca*
  .. index:: -ca

  Extract all possible cycles in the call graph.

*-c n*
  .. index:: -c

  Use `n` bytes frame for subprograms at the beginning of cycles. This can
  be used to increase visibility of cycles in reports.

*-g*
  .. index:: -g

  Generate internal debug information.

*-aO dir*
  .. index:: -aO

  Load :file:`.ci` files from `dir`.

*-e entry_point[,...]*
  .. index:: -e

  Name of symbols to be used as entry points for the analysis. It accepts both
  symbol and demangled names, and it performs a case-insensitive search.

*-files=file*
  .. index:: -files

  Take as arguments the files listed in text file `file`.
  Text file `file` may contain empty lines that are ignored.
  Each non empty line should contain the name of an existing file.
  Several such switches may be specified simultaneously.

*-h or --help*
  .. index:: -h
  .. index:: --help

  Output a message explaining the usage of *gnatstack*.

*-l n*
  .. index:: -l

  Print the `n` subprograms requiring the biggest local stack
  usage. By default none will be displayed.

*-o=x*
  .. index:: -o

  Specifies the order for displaying the different call graphs.
  The options allowed for this qualifier are:

* *-o=s*
    .. index:: -o=s

  Select stack usage order (the default mode).

* *-o=a*
    .. index:: -o=a

  Select alphabetical order.

*-p*
  .. index:: -p

  Print all the subprograms that make up the worst-case path for every
  entry point (the default mode).

*-pi*
  .. index:: -pi

  Print progress information (for GPS).

*-q*
  .. index:: -q

  Be quiet: do not display progress information.

*-Q*
  .. index:: -Q

  Very quiet: do not display any console message except those indicating
  an error and the progress information.

*-np*
  .. index:: -np

  Do not print worst-case path for entry points.

*-f file*
  .. index:: -f

  Write the generated graph (VCG format) into `file`.

*-r regexp*
  .. index:: -r

  Any symbol matching the regular expression `regexp` will be
  considered as an entry point for the analysis. It accepts both
  symbol and demangled names, and it performs a case-insensitive
  pattern matching.

*-d n*
  .. index:: -d

  Set default stack size for unbounded (dynamic) frames to `n` bytes.

*-u n*
  .. index:: -u

  Set default stack size for unknown (external) calls to `n` bytes.

*-v*
  .. index:: -v

  Specify the amount of information to be displayed about the
  different subprograms. In verbose mode the full location of the
  subprogram will be part of the output, as well as detailed information
  about inaccurate data.

*--version*
  .. index:: --version

  Print version information.

*-tx*
  .. index:: -t

  Print potential targets for indirect and dispatching calls.
  The options allowed for this qualifier are:

* *-ta*
    .. index:: -ta

    Print potential targets for both indirect and dispatching calls.


* *-ti*
    .. index:: -ti

    Print potential targets for indirect calls.


* *-td*
    .. index:: -td

    Print potential targets for dispatching calls.

*-Wx*
  .. index:: -W

  Warning mode. The options allowed for this qualifier are:

* *-Wa*
    .. index:: -Wa

    Turn on all optional warnings.

* *-Wc*
    .. index:: -Wc

    Turn on warnings for cycles (recursion).

* *-Wu*
    .. index:: -Wu

    Turn on warnings for unbounded frames.

* *-We*
    .. index:: -We

    Turn on warnings for external calls.

* *-Wi*
    .. index:: -Wi

    Turn on warnings for indirect (including dispatching) calls.

*-x*
  .. index:: -x

  Generate file `stack_usage.xml` with the information in XML format.

*-oc=name*
  .. index:: -oc

  Use the `objcopy` executable `name` to extract the :file:`.ci`
  files from the object files. If may contain the prefix (such as
  `powerpc-elf-objcopy`) or the suffix (such as `objcopyppc`).

*-s=section*
  .. index:: -s

  Extract the :file:`.ci` files from section named `section` in the
  object files.

*-k*
  .. index:: -k

  Keep the temporary files created by GNATstack (such as the :file:`.ci`
  files extracted from the object files.

*--target=tgt*
  .. index:: --target

  Use `tgt` as program prefix used to build the application being
  analyzed. This value is only used to help retrieving the stack usage
  information for the run-time library.

*--RTS=rts*
  .. index:: --RTS

  Use `rts` as the run-time library used to build the application
  being analyzed. This value is only used to retrieve the stack usage
  information for the run-time library.

*-Xname=val*
  .. index:: -X

  Set project variable `name` to `val`. Several *-X*
  switches can be used simultaneously. If several *-X* switches
  specify the same `name`, only the last one is used. An external
  variable specified with a *-X* switch takes precedence over
  the value of the same name in the environment.

*-Pprj*
  .. index:: -P

  Get the GNATstack options from the specified project `prj`.

.. _Use_of_Project_Files:

Use of Project Files
====================

*gnatstack* supports the use of project files. There is an
optional package in the project file for GNATstack
(which is the package `Stack`) that has an unique attribute
`Switches`. This attribute is a simple variable that contains a
string list value representing the switches to be passed to
*gnatstack*:

.. code-block:: ada

  project Prj is
     package Stack is
        for Switches use ("-p");
     end Stack;
  end Prj;  

The following command will parse the project file :file:`prj.gpr` and
call *gnatstack* with the specified options::

  $ gnatstack -P prj.gpr
  
When *gnatstack* is used with a project file, if gets the set of
:file:`.ci` files that correspond to the units that belong to the project
and all projects in the project tree.

If one or more user-defined :file:`.ci` files need to be taken into account
for the analysis, the appropriate place to specify them is in the
`Switches` attribute of the project file:

.. code-block:: ada

  project Prj is
     package Stack is
        for Switches use (..., "user1.ci", "user2.ci");
     end Stack;
  end Prj;
  
.. _GNATstack_Output:

GNATstack output
================

The execution of GNATstack produces the maximum stack space required by every
entry point (including tasks) in the application, together with the paths that
lead to these stack needs::

  $ gnatstack -P my_project.gpr

  Accumulated stack usage information for entry points

  main : total 408 bytes
   +-> main
   +-> main_unit
   +-> pck.process

The maximum stack consumption for the *main* entry point is 408 bytes, and this
is a safe bound that can be trusted. The indicated call chain is the path with
the longest stack consumption from all possible paths starting from *main*.

More details about the locations of the subprograms and their local stack
frames is displayed using the *-v* switch::

  $ gnatstack -v -P my_project.gpr
  [...]

  Accumulated stack usage information for entry points

  main : total 408 bytes
   +-> main at main:b__main_unit.adb:118:4 : 80 bytes
   +-> main_unit at Main_Unit:main_unit.adb:3:1 : 16 bytes
   +-> pck.process at Process:pck.adb:2:4,Process:pck.ads:2:14 : 312 bytes

In this case, the first line indicates the total (global) stack requirement of
408 bytes for the whole call chain (adding up all the frames in the call chain),
and the following lines contain the individual (local) stack frames for each of
the subprograms in the call chain.

When the computed stack consumption cannot be safely bound (because of cycles,
unbounded frames, external calls, or indirect calls) the total stack
requirements contain a "+?" indication, plus a "*" indication in the frames
containing missing information. For example, if we add a dynamic variable to
the previous example we would have the following GNATstack report::

  $ gnatstack -P my_project.gpr

  Worst case analysis is *not* accurate because of unbounded frames.
  Use -Wa for details.

  Accumulated stack usage information for entry points

  main : total 576+? bytes
   +-> main
   +-> main_unit
   +-> pck.process *

If we add the "-Wa" and "-v" options to GNATstack we get the following
additional information::

  $  gnatstack -v -Wa -P my_project.gpr
  [...]
  
   Worst case analysis is *not* accurate because of unbounded frames.

   List of reachable subprograms with dynamic unbounded frames:

     In pck.process at Process:pck.adb:2:4,Process:pck.ads:2:14

   Accumulated stack usage information for entry points

   main : total 576+? bytes (unbounded)
    +-> main at main:b__main_unit.adb:118:4 : 80 bytes
    +-> main_unit at Main_Unit:main_unit.adb:3:1 : 16 bytes
    +-> pck.process at Process:pck.adb:2:4,Process:pck.ads:2:14 : 480+? bytes (unbounded)

This analysis indicates that the computed worst case stack usage is not
accurate. There are 576 bytes needed, plus the amount required by the dynamic
object declared by subprogram *Process*.

.. _Information_in_Non-Loadable_Section:

Information in Non-Loadable Section
===================================

The :file:`.ci` file generated for every compilation unit can be written
into the generated object as a non-loadable section. For example, it can
be written into a section named `.GNU.callgraph` doing::

  $ gcc -c -fcallgraph-info=su main_unit.adb
  $ objcopy --add-section .GNU.callgraph=main_unit.ci main_unit.o
  $ gnatstack main_unit.o
  
This section is not downloaded into the target so it does not affect the
execution. The advantage is that it may facilitate the retrieval of the
required :file:`.ci` files (we simply need the list of object files that
make up the application), and it may help guaranteeing the coherence
between the call-graph and stack usage information and the corresponding
object files.

The linker would merge (concatenate) the :file:`.ci` sections corresponding
to the object files being linked into the final executable (including those
coming from library files).

GNATstack can later extract this section from the object files
and use the information for the rest of the analysis. GNATstack
uses the `objcopy` tool to extract the :file:`.ci` files.

By default, GNATstack uses the native `objcopy` executable.
It can be changed using the *-oc* option (see :ref:`Options_for_GNATstack`)::

  $ powerpc-elf-gcc -c -fcallgraph-info=su main_unit.adb
  $ powerpc-elf-objcopy --add-section .GNU.callgraph=main_unit.ci main_unit.o
  $ gnatstack -oc=powerpc-elf-objcopy main_unit.o

The section where the :file:`.ci` files are stored can also be changed, and
GNATstack provides an option (*-s*, see :ref:`Options_for_GNATstack`) to specify
this section::

  $ gcc -c -fcallgraph-info=su main_unit.adb
  $ objcopy --add-section my_section=main_unit.ci main_unit.o
  $ gnatstack -s=my_section main_unit.o
