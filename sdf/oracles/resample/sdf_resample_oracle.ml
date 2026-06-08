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
        }
        -> t

  let sample (T { computed; exec; oracles }) ~x ~y =
    let module E = (val exec.portended) in
    E.Single.run computed ~vars:(E.Single.Variable_idx.Map.of_alist_exn []) ~oracles ~x ~y
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
  ~sample_region:_
  =
  let module E = (val exec) in
  let computed = E.Single.of_tree tree in
  Oracle.Prepared.wrap
    (module Prepared)
    (Prepared.T { computed; exec = { portended = exec }; oracles })
;;

let prepare tree ~(exec : (module Executor.S)) ~oracles ~sample_region =
  make tree ~exec:(Obj.magic Obj.magic_portable exec) ~oracles ~sample_region
;;
