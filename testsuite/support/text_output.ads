package Text_Output is
   procedure Put_Line (Str : String);
   pragma Inline_Always (Put_Line);
   --  Inline this function so they do not affect stack utilization
end Text_Output;
