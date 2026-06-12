(* See the .mli for why this exists. The recursion is deliberately non-tail so each level
   occupies a stack frame; [opaque_identity] keeps the whole thing from being optimized
   away. 4096 frames is roughly 100-200 KB — far deeper than any evaluator recursion over
   a real expression tree, so once pre-grown the fiber never grows its stack again while
   unboxed values are live. *)
let rec grow n = if n = 0 then 0 else 1 + grow (n - 1)

let pre_grow () =
  match Sys.arch with
  | Amd64 -> ignore (Sys.opaque_identity (grow 4096) : int)
  | Arm64 -> ()
;;
