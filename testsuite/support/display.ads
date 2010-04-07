package Display is
   procedure Put_Stack_Usage (Stack_Size : Natural);
   pragma Inline_Always (Put_Stack_Usage);
   --  Get the current stack pointer
   --  Inline this function so they do not affect stack utilization
end Display;
