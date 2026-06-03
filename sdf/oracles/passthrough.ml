open! Core
open Sdf

type t = Expr_tree.t [@@deriving equal, compare, sexp_of]

include functor Comparable.Make_plain [@mode portable]

module Prepared = struct
  type t : value mod contended portable =
    { tree : Expr_tree.t
    ; exec : (module Executor.S) portended
    }

  let sample { tree = _; exec = _ } ~x:_ ~y:_ = assert false
end

let create = Fn.id

let prepare tree ~exec ~range_x:_ ~range_y:_ =
  Oracle.Prepared.wrap (module Prepared) { Prepared.tree; exec = { portended = exec } }
;;
