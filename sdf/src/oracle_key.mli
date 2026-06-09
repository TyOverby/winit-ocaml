@@ portable

open! Core

type t = string * Expr_tree.t list [@@deriving compare, equal, sexp_of]

include Comparator.S [@mode portable] with type t := t
