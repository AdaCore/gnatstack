.. _Machine_Specific_Topics:

***********************
Machine Specific Topics
***********************

Because stack usage information is only generated for Ada or C code, if you
interface with code written in assembly you may need extra details.

When using a cross compiler with restricted run-time libraries, the
stack usage information for the run-time libraries is stored together
with the libraries. The options *--target* and *--RTS* can
be used to retrieve the information for the run-time library. These
options are used the same way as for building the application, as shown
in the following example::

  $ gprbuild --target=powerpc-elf --RTS=powerpc-elf/zfp-prep -P prj.gpr
  $ gnatstack --target=powerpc-elf --RTS=powerpc-elf/zfp-prep -P prj.gpr

AVR
===

The stack used by the `call`, `rcall`, `icall` or `eicall`
instructions is counted in the callee. That is all subprograms use at least
3 bytes on avr6 architecture (`atmega256x`) and 2 bytes or avr5
architecture.

If you link with libgcc (which is the default unless you use -nostdlib), add
3 bytes (on avr6 architecture) to the maximum stack usage reported by
GNATstack as there is some left subprograms written in assembly.
