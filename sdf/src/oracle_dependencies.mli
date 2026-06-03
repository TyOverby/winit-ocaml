open! Core

type t = { toposorted : Executor.Oracle.Key.t list list }

val extract_deps : Expr_tree.t -> t
