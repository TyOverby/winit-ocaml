@@ portable

open! Core

(** The scalar register-VM evaluator. Production uses it two ways: {!Private.run} is the
    SIMD batch evaluator's scalar tail (widths not divisible by 4), and {!Single} is the
    single-point evaluator behind point-sampled oracles. Both are bitwise identical to the
    SIMD path, per the cross-backend consistency contract. *)

(** Evaluate one [(x, y)] point. *)
module Single : sig
  type t : value mod contended portable

  module Variable_idx : sig
    type t : value mod contended portable

    include Comparator.S [@mode portable] with type t := t
  end

  val of_tree : Expr_tree.t -> t
  val lookup_variable : t -> string -> Variable_idx.t

  val run
    :  t
    -> vars:Value.Boxed.t Map.M(Variable_idx).t
    -> oracles:Prepared_oracle.t Map.M(Oracle_key).t
    -> x:Float32_u.t
    -> y:Float32_u.t
    -> Value.t
end

module Private : sig
  val run
    :  variables:Value.Array.t
    -> instructions:(int * Expr_graph.instr) iarray
    -> registers:Value.Array.t
    -> oracles:Prepared_oracle.t iarray
    -> x:Float32_u.t
    -> y:Float32_u.t
    -> unit
end
