open! Core
open Sdf

let _ : (module Executor.S) list @ portable =
  [ (module Expr_tree_eval); (module Expr_graph_eval); (module Expr_graph_batch_eval) ]
;;

let _ : (module Executor.S) list @ shareable =
  [ (module Expr_tree_eval); (module Expr_graph_eval); (module Expr_graph_batch_eval) ]
;;

let _ : (module Oracle.S) list @ portable = [ (module Sdf_passthrough_oracle) ]
let _ : (module Oracle.S) list @ shareable = [ (module Sdf_passthrough_oracle) ]
