.. _Getting_Started_with_GNATstack:

******************************
Getting Started with GNATstack
******************************

Two steps are needed to analyze stack usage: 1) generation of the basic
stack consumption and call-graph information, followed by 2) analysis
and report generation. With an LLVM based toolchain there is one more
step between the two, the decoding of the linked executable.

GNATstack relies on information produced by the compiler, provided
through :file:`.ci` files. How those files are obtained differs between
the two toolchains. A GCC based compiler writes one :file:`.ci` file per
compilation unit, as described in :ref:`GCC_Based_Toolchains`. With an
LLVM based compiler the information travels in sections of the object
files, and a single :file:`.ci` file describing the whole program is
produced from the linked executable, as described in
:ref:`LLVM_Based_Toolchains`.

The first step is to compile the application with the required options
to generate the information about per-subprogram stack consumption and
call-graph information. The two toolchains use different switches.

.. index:: -fcallgraph-info=su

The *-fcallgraph-info=su* GCC compiler switch outputs this information on a
per-file basis in the common VCG format::

  $ gprbuild main_unit.adb -cargs -fcallgraph-info=su

.. index:: -fexperimental-call-graph-section
.. index:: -fstack-size-section

An LLVM based compiler requires *-fexperimental-call-graph-section*
along with *-fstack-size-section* to put the same information into
sections of the object files::

  $ gprbuild main_unit.adb -cargs -fexperimental-call-graph-section -fstack-size-section

The linked executable is then decoded into a single :file:`.ci` file by
the *llvm-callgraph-decoder* tool, which is described together with the
rest of that route in :ref:`LLVM_Based_Toolchains`.

.. index:: -fcallgraph-info=da

The GCC compiler can also generate information about dynamically allocated
objects adding the `da` marker to the `-fcallgraph-info`
compiler switch (`-fcallgraph-info=su,da`). This option helps
locating the objects that introduce potentially unbounded stack
requirements. There is no equivalent of the `da` marker under GNAT Pro
LLVM: a frame size is recorded only where the compiler knows it
statically, and a subprogram that allocates its frame dynamically is
left without a size of its own in the information the executable
carries.

In the second step, GNATstack can then parse this information to generate the
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

  Print progress information (for GNAT Studio).

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
  files from the object files. It may contain the prefix (such as
  `powerpc-elf-objcopy`) or the suffix (such as `objcopyppc`).
  This switch concerns the GCC section route described in
  :ref:`Information_in_Non-Loadable_Section` only.

*-s=section*
  .. index:: -s

  Extract the :file:`.ci` files from section named `section` in the
  object files. This switch concerns the GCC section route described in
  :ref:`Information_in_Non-Loadable_Section` only.

*-k*
  .. index:: -k

  Keep the temporary files created by GNATstack (such as the :file:`.ci`
  files extracted from the object files). This switch concerns the GCC
  section route described in :ref:`Information_in_Non-Loadable_Section`
  only.

*--target=tgt*
  .. index:: --target

  Use `tgt` as program prefix used to build the application being
  analyzed. This value is only used to help retrieving the stack usage
  information for the run-time library (see :ref:`Run-Time_Library`).

*--RTS=rts*
  .. index:: --RTS

  Use `rts` as the run-time library used to build the application
  being analyzed. This value is only used to retrieve the stack usage
  information for the run-time library (see :ref:`Run-Time_Library`).

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
(which is the package `Stack`) that has a unique attribute
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

When *gnatstack* is used with a project file, it gets the set of
:file:`.ci` files that correspond to the units that belong to the project
and all projects in the project tree. With an LLVM based toolchain there
are no such per unit files to collect; see :ref:`LLVM_Based_Toolchains`.

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

Within GNAT Studio the stack usage information is available
via the :menuselection:`Analyze --> Stack Analysis --> Analyze Stack Usage` menu.
For each of the subprograms the information is displayed in the form of
annotations containing *local* stack requirements, which refers to a single
stack frame, and *global* stack requirements, which refers to the worst case
(with respect to stack usage) call chain starting from the subprogram. In the
previous example, *local* is the 80 bytes of the *main* subprogram, and
*global* is 408 bytes (for the call chain where *main* calls *Main_Unit* and
*Main_Unit* calls *Process*)::

  --  main
  --
  --  Stack usage: local: 80 bytes, global: 408 bytes

More details about the locations of the subprograms and their local stack
frames are displayed using the *-v* switch::

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

  $ gnatstack -v -Wa -P my_project.gpr
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

Within GNAT Studio, this missing information is expressed with annotations indicating
the reasons behind the inaccuracy. For the *main* entry point we would have::

  --  main
  --
  --  Stack usage: local: 80 bytes, global: 576 bytes (unbounded)

and for the *Process* subprogram we would have::

  --  pck.process
  --
  --  Stack usage: local: 480 bytes (unbounded), global: 480 bytes (unbounded)
