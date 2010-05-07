with System.Storage_Elements;
with Unchecked_Conversion;

package body Memory is

   package SSE renames System.Storage_Elements;

   Default_Size : constant := 20 * 1_024;

   type Mark_Id is new SSE.Integer_Address;

   type Memory is array (Mark_Id range <>) of SSE.Storage_Element;
   for Memory'Alignment use Standard'Maximum_Alignment;

   Mem : Memory (1 .. Default_Size);

   Top : Mark_Id := Mem'First;

   function To_Mark_Id is new Unchecked_Conversion
     (size_t, Mark_Id);

   ----------------
   -- For C code --
   ----------------

   function Malloc (Size : size_t) return System.Address;
   pragma Export (C, Malloc, "malloc");

   function Calloc (N_Elem : size_t; Elem_Size : size_t) return System.Address;
   pragma Export (C, Calloc, "calloc");

   procedure Free (Ptr : System.Address);
   pragma Export (C, Free, "free");

   -----------
   -- Alloc --
   -----------

   function Alloc (Size : size_t) return System.Address is
      Max_Align    : constant Mark_Id := Mark_Id (Standard'Maximum_Alignment);
      Max_Size     : Mark_Id :=
                       ((To_Mark_Id (Size) + Max_Align - 1) / Max_Align)
                       * Max_Align;
      Location     : constant Mark_Id := Top;
   begin
      if Max_Size = 0 then
         Max_Size := Max_Align;
      end if;

      if Size = size_t'Last then
         raise Storage_Error;
      end if;

      Top := Top + Max_Size;

      if Top > Default_Size then
         raise Storage_Error;
      end if;

      return Mem (Location)'Address;
   end Alloc;

   ------------
   -- Malloc --
   ------------

   function Malloc (Size : size_t) return System.Address is
   begin
      return Alloc (Size);
   end Malloc;

   ------------
   -- Calloc --
   ------------

   function Calloc
     (N_Elem : size_t; Elem_Size : size_t) return System.Address
   is
   begin
      return Malloc (N_Elem * Elem_Size);
   end Calloc;

   ----------
   -- Free --
   ----------

   procedure Free (Ptr : System.Address) is
      pragma Unreferenced (Ptr);
   begin
      null;
   end Free;

end Memory;
