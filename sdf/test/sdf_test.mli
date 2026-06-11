open! Core

module Test_bisimulation : sig
  val gen_float_expr : depth:int -> Sdf.Expr_tree.t Quickcheck.Generator.t
  val gen_bool_expr : depth:int -> Sdf.Expr_tree.t Quickcheck.Generator.t
end
