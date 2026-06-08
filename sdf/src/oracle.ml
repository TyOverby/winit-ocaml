open! Core

module type S = sig
  type t [@@deriving equal, compare, sexp_of]

  include Comparable.S_plain with type t := t

  val create : Expr_tree.t list -> t

  val prepare
    :  t
    -> exec:(module Executor.S) @ portable
    -> oracles:Prepared_oracle.t Oracle_key.Map.t
    -> sample_region:Sample_region.t
    -> Prepared_oracle.t
end

module Key = Oracle_key
module Prepared = Prepared_oracle
