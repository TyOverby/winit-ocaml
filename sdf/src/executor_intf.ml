open! Core

module type S_single = sig @@ portable
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

module type S_batch = sig @@ portable
  module Variable_idx : sig
    type t : value mod contended portable
  end

  module Prepared : sig
    type t : value mod contended portable

    val of_tree : Expr_tree.t -> t
    val lookup_variable : t -> string -> Variable_idx.t
  end

  module Result : sig
    type t

    val get_output : t -> px:int -> Value.t
  end

  module Batch : sig
    type t

    val create : Prepared.t -> Sample_region.t -> t
    val set_variable : t -> var:Variable_idx.t -> Value.t -> unit
    val run : t -> oracles:Prepared_oracle.t Map.M(Oracle_key).t -> Result.t
  end
end

module type S_parallel = sig @@ portable
  module Variable_idx : sig
    type t : value mod contended portable
  end

  module Prepared : sig
    type t : value mod contended portable

    val of_tree : Expr_tree.t -> t
    val lookup_variable : t -> string -> Variable_idx.t option
  end

  module Result : sig
    type t : value mod contended portable

    val get : t -> x:int -> y:int -> Value.t @@ portable
  end

  module Batch : sig
    type t : value

    val create : Prepared.t -> Sample_region.t -> t
    val set_variable : t -> var:Variable_idx.t -> Value.t -> unit

    val run
      :  t
      -> par:Parallel.t @ local
      -> oracles:Prepared_oracle.t Map.M(Oracle_key).t
      -> Result.t
  end
end

(* An evaluator over ranges: instead of a single (x, y) point it takes inclusive
   coordinate intervals and returns an interval guaranteed to contain the value the
   scalar evaluator would produce at any point of the box. *)
module type S_range = sig @@ portable
  type t : value mod contended portable

  module Variable_idx : sig
    type t : value mod contended portable

    include Comparator.S [@mode portable] with type t := t
  end

  val of_tree : Expr_tree.t -> t
  val lookup_variable : t -> string -> Variable_idx.t

  (** For [Float]-typed expressions; raises on [Bool]-typed ones. Note that [vars] are
      scalars, exactly as in {!S_single} — only the coordinates are ranges. *)
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
end

module type S = sig @@ portable
  module Single : S_single
  module Batch : S_batch
  module Parallel : S_parallel
end

(* Defined after [S] so that [prepare] can reference [(module S)]. *)

module type Executor = sig
  module type S_single = S_single
  module type S_batch = S_batch
  module type S_parallel = S_parallel
  module type S_range = S_range
  module type S = S

  module Batch_to_parallel (_ : S_batch) : S_parallel @ portable
  module Single_to_batch (_ : S_single) : S_batch @ portable
  module Batch_to_single (_ : S_batch) : S_single @ portable
  module Parallel_to_single (_ : S_single) : S_parallel @ portable
end
