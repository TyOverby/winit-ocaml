@@ portable

open! Core

module Result : sig
  type t =
    | Ok of Value.t
    | Error of Error.t
  [@@deriving sexp_of]
end

val eval : env:Value.Boxed.t String.Map.t -> Expr_tree.t -> Result.t

module Batched : Batch_backend_intf.S

(** Grid-native ({!Batch_backend_intf.S_parallel}) wrapper over {!Batched}.

    [@@ nonportable] because [S_parallel.Batch.run] drives the scheduler and so cannot be
    portable; without it the enclosing [@@ portable] signature would demand a fully
    portable module. *)
module (Batch_parallel @@ nonportable) : Batch_backend_intf.S_parallel
