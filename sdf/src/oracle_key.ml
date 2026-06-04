open! Core

module T = struct
  type t = string * Expr_tree.t list [@@deriving compare, equal, sexp_of]
end

include T
include Comparable.Make_plain [@mode portable] (T)
