open! Core
open Sdf

type t = Expr_tree.t [@@deriving equal, compare, sexp_of]

include functor Comparable.Make_plain [@mode portable]

module Prepared = struct
  type t : value mod contended portable =
    | T :
        { exec :
            (module Executor.S with type Single.t = 'a and type Single.Variable_idx.t = 'b)
              portended
        ; computed : 'a
        ; oracles : Oracle.Prepared.t Oracle.Key.Map.t
        ; x_var_idx : 'b
        ; y_var_idx : 'b
        }
        -> t

  let sample (T { computed; exec; oracles; x_var_idx; y_var_idx }) ~x ~y =
    let module E = (val exec.portended) in
    E.Single.run
      computed
      ~vars:
        (E.Single.Variable_idx.Map.of_alist_exn
           [ x_var_idx, x |> Value.of_float |> Value.box
           ; y_var_idx, y |> Value.of_float |> Value.box
           ])
      ~oracles
    |> Value.to_float
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
  ~range_x:_
  ~range_y:_
  =
  let module E = (val exec) in
  let computed = E.Single.of_tree tree in
  let x_var_idx = E.Single.lookup_variable computed "x" in
  let y_var_idx = E.Single.lookup_variable computed "y" in
  Oracle.Prepared.wrap
    (module Prepared)
    (Prepared.T { computed; exec = { portended = exec }; oracles; x_var_idx; y_var_idx })
;;

let prepare tree ~(exec : (module Executor.S)) ~oracles ~range_x ~range_y =
  make tree ~exec:(Obj.magic Obj.magic_portable exec) ~oracles ~range_x ~range_y
;;
