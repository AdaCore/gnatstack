.. _Toolchain_Specific_Topics:

*************************
Toolchain Specific Topics
*************************

GNATstack reads the same :file:`.ci` information whichever compiler
produced it. What differs between a GCC based and an LLVM based
toolchain is how that information is produced and how it reaches the
tool. This chapter describes what is specific to each of them.

.. _GCC_Based_Toolchains:

GCC based toolchains
====================

A GCC based compiler writes one :file:`.ci` file per compilation unit,
next to the object file. That is the route described in
:ref:`Getting_Started_with_GNATstack`. The sections below describe an
optional variant of it, in which those files are carried inside the
object files themselves, and how the information for the run-time
library is retrieved.

.. _Information_in_Non-Loadable_Section:

Information in Non-Loadable Section
-----------------------------------

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

An LLVM based toolchain writes sections of its own, in a different
format, which are read by the decoder described below rather than by
*gnatstack* itself, so the *-oc* and *-s* switches do not apply to it.

.. _Run-Time_Library:

Run-Time Library
----------------

When using a cross compiler with restricted run-time libraries, the
stack usage information for the run-time libraries is stored together
with the libraries. The options *--target* and *--RTS* can
be used to retrieve the information for the run-time library. These
options are used the same way as for building the application, as shown
in the following example::

  $ gprbuild --target=powerpc-elf --RTS=powerpc-elf/zfp-prep -P prj.gpr
  $ gnatstack --target=powerpc-elf --RTS=powerpc-elf/zfp-prep -P prj.gpr

.. _LLVM_Based_Toolchains:

LLVM based toolchains
=====================

GNAT Pro LLVM does not write :file:`.ci` files. It puts the same
information into sections of the object files. The linker concatenates
those sections, and a separate tool turns the linked executable into a
single :file:`.ci` file describing the whole program. GNATstack itself
is unchanged: it reads that :file:`.ci` exactly as it reads the one a
GCC based compiler produces.

The *-fcallgraph-info* switch is not implemented by GNAT Pro LLVM.
Passing it has no effect and produces no :file:`.ci` file.

.. _Decoding_the_Executable:

Decoding the executable
-----------------------

.. index:: llvm-callgraph-decoder

The *llvm-callgraph-decoder* tool reads the sections back from a linked
executable and writes the :file:`.ci` file that GNATstack consumes. It
is part of the GNAT Pro LLVM installation, in the same directory as
the compiler driver, so nothing else has to be installed::

  llvm-callgraph-decoder <elf-file> [--ci]

Without *--ci* the tool prints the merged graph in a readable form,
which is a convenient way of seeing what GNATstack is going to be
given. With *--ci* it writes the :file:`.ci` graph to standard output.

The decoder is a host tool and knows nothing about the target
architecture. It reads ELF32 and ELF64 of either endianness, so an
executable built by a cross compiler is decoded on the build machine,
by the same tool as a native one.

To compile, decode and analyze a program we do the following, with
*-fexperimental-call-graph-section* and *-fstack-size-section* in the
`Compiler` package of the project file and *-static* in its `Linker`
package::

  $ gprbuild -P prj.gpr
  $ llvm-callgraph-decoder obj/test --ci > test.ci
  $ gnatstack -P prj.gpr test.ci

  Worst case analysis is *not* accurate because of external calls. Use -Wa for details.

  Accumulated stack usage information for entry points

  main : total 296+? bytes
   +-> main
   +-> test
   +-> foo.baz
   +-> dispatching to foo.bar
   +-> <__gnat_rcheck_PE_Access_Before_Elaboration> *

The dispatching call made by `Foo.Baz` has been resolved: GNATstack
followed the tagged type hierarchy to the primitive that can be reached
by it. The result carries a "+?" because the worst-case path reaches a
run-time subprogram, for which the executable carries no information.

The decoded :file:`.ci` file is passed to *gnatstack* explicitly, as an
argument or in the `Switches` attribute of the project file, because the
compiler leaves no per unit :file:`.ci` files behind for *gnatstack* to
collect. Writing it outside the object directory, as above, also keeps
it out of the files that *gnatstack* gathers from the project on its
own, so that a stale copy of it cannot take part in a later analysis.

.. _Limitations_with_GNAT_Pro_LLVM:

Limitations
-----------

ELF targets only
^^^^^^^^^^^^^^^^

The call graph is carried by sections of the object files, and the LLVM
support for writing them exists for the ELF object format only. On any
other target the switch is refused rather than silently ignored::

  error: -fexperimental-call-graph-section is supported for ELF targets only, not x86_64-windows

Decode before stripping
^^^^^^^^^^^^^^^^^^^^^^^

Link time garbage collection (`--gc-sections`) and
`strip --strip-debug` both leave the decoded graph unchanged. A full
`strip` does not: the sections that carry the information survive it,
but the symbol table does not, and without symbols the decoder can only
name functions by their address, which GNATstack cannot parse. Decode
the executable before stripping it, or keep an unstripped copy for the
analysis.

Static link requirement
^^^^^^^^^^^^^^^^^^^^^^^

The program has to be linked statically before it is decoded. In a
dynamically linked binary the callee recorded in the call graph section
for anything reached through the procedure linkage table is written as
zero, because the section is not loadable and there is no relocation for
the linker to apply to it. The decoder cannot name such a target, the
call comes out as a call to `<unresolved>`, and GNATstack reports it
among the reachable external subprograms.

No run-time library information
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

The run-time libraries shipped with GNAT Pro LLVM are not compiled with
*-fexperimental-call-graph-section* and *-fstack-size-section*. The
executable therefore carries no frame size and no call graph information
for run-time subprograms: they are reported as external calls, and any
path reaching one of them is reported with a "+?" indication.

Accuracy of the reported frame sizes
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

The frame size that GNAT Pro LLVM records for a function is the space
that the prologue of the function allocates, which is not in general the
whole of the activation record that the function occupies. On x86 and
x86_64 the figure can be below real usage, which is the unsafe
direction. The return address that the call instruction pushes is not
part of the frame that the prologue allocates, and neither is the area
that a caller may reserve for arguments passed on the stack.
The error grows with the depth of the call chain rather than being a
constant, so a margin has to be added on top of the figure that
GNATstack reports on these two architectures. Other architectures are
not concerned: there a call leaves the return address in a register and
a subprogram that makes further calls saves it inside its own frame,
which the reported figure already covers.
