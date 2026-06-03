open! Core
open Sdf

(* How each input variable is accessed inside the shader. *)
type var_kind =
  | Storage_buffer of { binding : int }
  (** Read from a [var<storage, read> varN: array<u32>] at the given binding index. *)
  | Inline_u32 of string
  (** Embed the given WGSL expression (which must produce a [u32]) directly at each use
      site. Callers use this to compute uniform, affine, or other constant variables
      on-device without uploading a per-pixel buffer. *)

(* Compiles a register-based {!Expr_graph} program into the source of a WGSL compute
   shader that evaluates it for one pixel per GPU invocation.

   The shader exposes one [read_write] storage buffer (binding 0) for the output. Input
   variables are accessed according to the [var_kinds] array: [Storage_buffer] entries get
   a [var<storage, read>] declaration at their binding index; [Inline_u32] entries are
   evaluated inline and need no buffer.

   Every SDF register is represented as a [u32] holding the raw bits of a {!Value.t} —
   exactly the host-side representation — and float operations [bitcast] to/from [f32]
   around the arithmetic. This keeps the GPU's per-bit semantics aligned with the CPU
   backends (the same trick the CPU backends use, where a [Value.t] is 32 raw bits
   reinterpreted as a float or a bool). *)
val of_graph
  :  instructions:Expr_graph.t
  -> final_register:int
  -> register_count:int
  -> var_kinds:var_kind array
  -> string

(* The size of the 1-D compute workgroup the generated shader declares; callers dispatch
   [ceil (width * height / workgroup_size)] workgroups. *)
val workgroup_size : int
