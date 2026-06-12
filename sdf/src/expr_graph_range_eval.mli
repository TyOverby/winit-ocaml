@@ portable

open! Core

(** A range (interval) evaluator for the instruction graph.

    Where {!Expr_graph_eval} evaluates the program at a single (x, y) point, this
    evaluator takes inclusive coordinate ranges and returns an interval guaranteed to
    contain every value the scalar evaluator can produce at any point of the box.
    Variables remain scalars; only the coordinates (and therefore oracles, via
    {!Prepared_oracle.sample_range}) are ranges. *)

type t : value mod contended portable

module Variable_idx : sig
  type t : value mod contended portable

  include Comparator.S [@mode portable] with type t := t
end

val of_tree : Expr_tree.t -> t
val lookup_variable : t -> string -> Variable_idx.t

(** A prepared call: the variable array, the oracle lookups, and the register buffers are
    resolved/allocated once at {!Context.create} time, so the [_with_context] runs below
    are allocation-free. Use one context for a batch of evaluations that share [vars] and
    [oracles] and differ only in the coordinate box (e.g. the tile scheduler's
    subdivision recursion). A context holds mutable scratch buffers, so it must not be
    shared across concurrent evaluations. *)
module Context : sig
  type eval := t
  type t

  val create
    :  eval
    -> vars:Value.Boxed.t Map.M(Variable_idx).t
    -> oracles:Prepared_oracle.t Map.M(Oracle_key).t
    -> t
end

(** For [Float]-typed expressions; raises on [Bool]-typed ones. *)
val run_with_context : Context.t -> x:Interval.t -> y:Interval.t -> Interval.t

(** For [Bool]-typed expressions; raises on [Float]-typed ones. *)
val run_bool_with_context : Context.t -> x:Interval.t -> y:Interval.t -> Interval.Bool.t

(** [run t ~vars ~oracles ~x ~y] is
    [run_with_context (Context.create t ~vars ~oracles) ~x ~y]. For [Float]-typed
    expressions; raises on [Bool]-typed ones. Note that [vars] are scalars, exactly as in
    {!Expr_graph_eval.Single} — only the coordinates are ranges. *)
val run
  :  t
  -> vars:Value.Boxed.t Map.M(Variable_idx).t
  -> oracles:Prepared_oracle.t Map.M(Oracle_key).t
  -> x:Interval.t
  -> y:Interval.t
  -> Interval.t

(** For [Bool]-typed expressions; raises on [Float]-typed ones. *)
val run_bool
  :  t
  -> vars:Value.Boxed.t Map.M(Variable_idx).t
  -> oracles:Prepared_oracle.t Map.M(Oracle_key).t
  -> x:Interval.t
  -> y:Interval.t
  -> Interval.Bool.t
