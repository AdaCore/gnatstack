package Stack_Handling is
   procedure Initialize_Stack;
   --  Fill the stack with "deadbeef" pattern. This is done for the
   --  environment task only.

   procedure Print_Stack_Usage;
   --  Evaluate stack utilization

   pragma Inline_Always (Initialize_Stack);
   pragma Inline_Always (Print_Stack_Usage);
   --  Inline these subprograms so they do not affect stack utilization
end Stack_Handling;
