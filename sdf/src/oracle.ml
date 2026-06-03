open! Core

module type S = sig
  type t [@@deriving equal, compare, sexp_of]

  include Comparable.S_plain with type t := t

  val create : Expr_tree.t -> t

  val prepare
    :  t
    -> exec:(module Executor.S) @ portable
    -> range_x:#(float32# * float32#)
    -> range_y:#(float32# * float32#)
    -> Prepared_oracle.t
end

module Key = Oracle_key
module Prepared = Prepared_oracle
