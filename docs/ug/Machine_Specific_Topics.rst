.. _Machine_Specific_Topics:

***********************
Machine Specific Topics
***********************

Because stack usage information is only generated for Ada or C code, if you
interface with code written in assembly you may need extra details.

AVR
===

The stack used by the `call`, `rcall`, `icall` or `eicall`
instructions is counted in the callee. That is all subprograms use at least
3 bytes on avr6 architecture (`atmega256x`) and 2 bytes on avr5
architecture.

If you link with libgcc (which is the default unless you use -nostdlib), add
3 bytes (on avr6 architecture) to the maximum stack usage reported by
GNATstack as there are some left subprograms written in assembly.
