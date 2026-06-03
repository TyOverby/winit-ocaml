open! Core

type t = { toposorted : Oracle_key.t list list }

val extract_deps : Expr_tree.t -> t
