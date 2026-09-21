.. _Operational_Environment:

***********************
Operational Environment
***********************

GNATstack operates on any system on which the GNAT compiler is
supported, including both native and cross compilers. It requires GNAT
Pro 5.04a or later.

GCC based toolchains support Ada, C, and C++. Note that analysis of dynamic
dispatching calls in C++ is limited.

With a GNAT Pro LLVM toolchain, support is limited to Ada and to
targets using the ELF object format.
