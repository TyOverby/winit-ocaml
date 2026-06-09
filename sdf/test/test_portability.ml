open! Core
open Sdf

let _ : unit -> (module Executor.S) list @ portable =
  fun () ->
  [ (module Expr_tree_eval); (module Expr_graph_eval); (module Expr_graph_batch_eval) ]
;;

let _ : unit -> (module Oracle.S) list @ portable =
  fun () -> [ (module Sdf_passthrough_oracle) ]
;;
