open! Core

module Result : sig
  type t =
    | Ok of Value.t
    | Error of Error.t
  [@@deriving sexp_of]
end

val eval : Expr_tree.t -> Result.t
