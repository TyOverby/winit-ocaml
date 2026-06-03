open! Core

module type S_single = sig @@ portable
  type t : value mod contended portable

  module Variable_idx : sig
    type t : value mod contended portable

    include Comparable.S [@mode portable] with type t := t
  end

  val of_tree : Expr_tree.t -> t
  val lookup_variable : t -> string -> Variable_idx.t

  val run
    :  t
    -> vars:Value.Boxed.t Variable_idx.Map.t
    -> oracles:Prepared_oracle.t Oracle_key.Map.t
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

    val create : Prepared.t -> len:int -> t
    val set_variable : t -> var:Variable_idx.t -> px:int -> Value.t -> unit
    val run : t -> oracles:Prepared_oracle.t Oracle_key.Map.t -> Result.t
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
    type t

    val create : Prepared.t -> width:int -> height:int -> t

    (* A variable that is constant across the whole grid. *)
    val set_uniform : t -> var:Variable_idx.t -> Value.t -> unit

    (* A variable whose value at pixel [(x, y)] is [base +. dx *. x +. dy *. y]. *)
    val set_affine : t -> var:Variable_idx.t -> base:float -> dx:float -> dy:float -> unit

    (* A general per-pixel variable, supplied as a row-major buffer of raw {!Value.t} bits
       ([width * height] elements). *)
    val set_grid
      :  t
      -> var:Variable_idx.t
      -> (int32, Bigarray.int32_elt, Bigarray.c_layout) Bigarray.Array1.t
      -> unit

    val run
      :  t
      -> par:Parallel.t
      -> oracles:Prepared_oracle.t Oracle_key.Map.t
      -> Result.t
  end
end

module type S = sig
  module Single : S_single
  module Batch : S_batch
  module Parallel : S_parallel
end

(* Defined after [S] so that [prepare] can reference [(module S)]. *)

module type Executor = sig
  module type S_single = S_single
  module type S_batch = S_batch
  module type S_parallel = S_parallel
  module type S = S

  module Batch_to_parallel (_ : S_batch) : S_parallel
  module Single_to_batch (_ : S_single) : S_batch
  module Batch_to_single (_ : S_batch) : S_single
  module Parallel_to_single (_ : S_single) : S_parallel
end
