package body Tasking is

   procedure Process;

   procedure Process is
   begin
      null;
   end Process;

   task body T is
   begin
      Process;
   end T;
end Tasking;
