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
