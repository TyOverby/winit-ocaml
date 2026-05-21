open! Core

module Eval_result : sig
  type t =
    | Ok of Float32_u.t
    | Error of Error.t
  [@@deriving sexp_of]
end

val eval : Expr_tree.t -> Eval_result.t
