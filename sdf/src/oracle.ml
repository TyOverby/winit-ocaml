open! Core
module Key = Oracle_key
module Prepared = Prepared_oracle

module type S = sig
  type t [@@deriving equal, compare, sexp_of]

  include Comparator.S [@mode portable] with type t := t

  val create : Expr_tree.t list -> t

  val prepare
    :  t
    -> exec:(module Executor.S) @ portable
    -> oracles:Prepared.t Oracle_key.Map.t
    -> sample_region:Sample_region.t
    -> Prepared.t
end
