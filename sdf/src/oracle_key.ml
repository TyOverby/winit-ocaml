open! Core

module T = struct
  type t = string * Expr_tree.t list [@@deriving compare, equal, sexp_of]
end

include T
include Comparator.Make [@mode portable] (T)
