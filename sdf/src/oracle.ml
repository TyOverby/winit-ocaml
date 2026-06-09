open! Core
module Key = Oracle_key
module Prepared = Prepared_oracle

module type S = sig @@ portable
  type t : value mod contended portable [@@deriving equal, compare, sexp_of]

  include Comparator.S [@mode portable] with type t := t

  val create : Expr_tree.t list -> t

  val prepare
    :  t
    -> par:Parallel.t @ local
    -> exec:(module Executor.S) @ shareable
    -> oracles:Prepared.t Oracle_key.Map.t
    -> sample_region:Sample_region.t
    -> Prepared.t
end
