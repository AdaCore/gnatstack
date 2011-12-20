------------------------------------------------------------------------------
--                        STATIC STACK ANALYSIS TOOL                        --
--                                                                          --
--                      D I S P A T C H I N G _ C A L L S                   --
--                                                                          --
--                                 S p e c                                  --
--                                                                          --
--                     Copyright (C) 2010-2011, AdaCore                     --
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

package Dispatching_Calls is

   procedure Create_Class_Hierarchies;
   --  Compute the list of derived classes for every base class. The compiler
   --  generates the information about class' parents. In order to get the
   --  list of potentially overriding methods for any given base method, we
   --  are interested in the list of descendent.

   procedure Create_Method_Hierarchies;
   --  Compute the list of methods which override every virtual method. This,
   --  together with the hierarchies of classes, will determine the set of
   --  potential overriding methods that may be called by any given
   --  dispatching call.

   procedure Resolve_Dispatching_Calls;
   --  Compute the list of potential targets for every dispatching call in
   --  the partition.

end Dispatching_Calls;
