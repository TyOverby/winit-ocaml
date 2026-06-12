open! Core
open Sdf
open Sdf_for_testing

(* The tiled machinery sends the production evaluators across domains, so they must
   mode-cross. The shapes from [Sdf_for_testing.Executor] are only used to state the
   assertion. *)

let _ : (module Executor.S_batch) list @ portable = [ (module Expr_graph_batch_eval) ]
let _ : (module Executor.S_batch) list @ shareable = [ (module Expr_graph_batch_eval) ]

let _ : (module Executor.S_single) list @ portable =
  [ (module Expr_graph_eval.Single); (module Expr_tree_eval.Single) ]
;;

let _ : (module Executor.S_single) list @ shareable =
  [ (module Expr_graph_eval.Single); (module Expr_tree_eval.Single) ]
;;

let _ : (module Oracle.S) list @ portable = [ (module Sdf_passthrough_oracle) ]
let _ : (module Oracle.S) list @ shareable = [ (module Sdf_passthrough_oracle) ]
let _ : (module Oracle.S) list @ immutable = [ (module Sdf_passthrough_oracle) ]
