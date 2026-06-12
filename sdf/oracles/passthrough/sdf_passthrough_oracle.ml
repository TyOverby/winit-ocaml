open! Core
open Sdf

type t = Expr_tree.t [@@deriving equal, compare, sexp_of]

include functor Comparator.Make [@mode portable]

module Prepared = struct
  type t : value mod contended portable =
    { computed : Expr_graph_eval.Single.t
    ; range : Expr_graph_range_eval.t
    ; oracles : Oracle.Prepared.t Map.M(Oracle.Key).t
    }

  let sample { computed; oracles; range = _ } ~x ~y =
    Expr_graph_eval.Single.run
      computed
      ~vars:(Map.empty (module Expr_graph_eval.Single.Variable_idx))
      ~oracles
      ~x
      ~y
    |> Value.to_float
  ;;

  let sample_range { range; oracles; computed = _ } ~x ~y =
    Expr_graph_range_eval.run
      range
      ~vars:(Map.empty (module Expr_graph_range_eval.Variable_idx))
      ~oracles
      ~x
      ~y
  ;;
end

let create = function
  | [ tree ] -> tree
  | _ -> failwith "expected exactly one tree"
;;

let prepare tree ~par:_ ~trace:_ ~oracles ~sample_region:_ =
  let computed = Expr_graph_eval.Single.of_tree tree in
  let range = Expr_graph_range_eval.of_tree tree in
  Oracle.Prepared.wrap (module Prepared) { Prepared.computed; range; oracles }
;;
