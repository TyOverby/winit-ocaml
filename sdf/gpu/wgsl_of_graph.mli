open! Core
open Sdf

(* Compiles a register-based {!Expr_graph} program into the source of a WGSL compute
   shader that evaluates it for one pixel per GPU invocation.

   The shader exposes one [read_write] storage buffer (binding 0) for the output and one
   [read] storage buffer per input variable (bindings [1 .. num_vars]). Each buffer is a
   flat [array<u32>] indexed by the linear pixel index ([global_invocation_id.x]); a
   variable's value at that pixel is read from [var{i}[index]].

   Every SDF register is represented as a [u32] holding the raw bits of a {!Value.t} —
   exactly the host-side representation — and float operations [bitcast] to/from [f32]
   around the arithmetic. This keeps the GPU's per-bit semantics aligned with the CPU
   backends (the same trick the CPU backends use, where a [Value.t] is 32 raw bits
   reinterpreted as a float or a bool). *)
val of_graph
  :  instructions:Expr_graph.t
  -> final_register:int
  -> register_count:int
  -> num_vars:int
  -> string

(* The size of the 1-D compute workgroup the generated shader declares; callers dispatch
   [ceil (width * height / workgroup_size)] workgroups. *)
val workgroup_size : int
