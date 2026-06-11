open! Core
open Sdf

type t = Expr_tree.t [@@deriving equal, compare, sexp_of]

include functor Comparator.Make [@mode portable]

module Prepared = struct
  type t : value mod contended portable =
    | T :
        { exec :
            (module Executor.S with type Single.t = 'a and type Single.Variable_idx.t = 'b)
              portended
        ; computed : 'a
        ; range : Expr_graph_range_eval.t
        ; oracles : Oracle.Prepared.t Map.M(Oracle.Key).t
        }
        -> t

  let sample (T { computed; exec; oracles; range = _ }) ~x ~y =
    let module E = (val exec.portended) in
    E.Single.run computed ~vars:(Map.empty (module E.Single.Variable_idx)) ~oracles ~x ~y
    |> Value.to_float
  ;;

  let sample_range (T { range; oracles; exec = _; computed = _ }) ~x ~y =
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

let make
  (type (a : value mod contended portable) (b : value mod contended portable))
  tree
  ~(exec : (module Executor.S with type Single.t = a and type Single.Variable_idx.t = b))
  ~oracles
  ~sample_region:_
  =
  let module E = (val exec) in
  let computed = E.Single.of_tree tree in
  let range = Expr_graph_range_eval.of_tree tree in
  Oracle.Prepared.wrap
    (module Prepared)
    (Prepared.T { computed; range; exec = { portended = exec }; oracles })
;;

let prepare tree ~par:_ ~(exec : (module Executor.S)) ~oracles ~sample_region =
  make tree ~exec:(Obj.magic Obj.magic_portable exec) ~oracles ~sample_region
;;
