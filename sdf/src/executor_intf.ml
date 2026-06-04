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

    val create : Prepared.t -> len:int -> t
    val set_variable : t -> var:Variable_idx.t -> Value.t -> unit
    val set_x : t -> px:int -> Value.t -> unit
    val set_y : t -> px:int -> Value.t -> unit
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
    type t : value

    val create : Prepared.t -> width:int -> height:int -> t

    (* Set x/y coordinates as affine functions of pixel position:
       value at pixel (px, py) = base +. dx *. px +. dy *. py *)
    val set_x_affine : t -> base:float -> dx:float -> dy:float -> unit
    val set_y_affine : t -> base:float -> dx:float -> dy:float -> unit

    val set_variable : t -> var:Variable_idx.t -> Value.t -> unit

    val run
      :  t
      -> par:Parallel.t @ local
      -> oracles:Prepared_oracle.t Oracle_key.Map.t
      -> Result.t
  end
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
  module type S = S

  module Batch_to_parallel (_ : S_batch) : S_parallel
  module Single_to_batch (_ : S_single) : S_batch
  module Batch_to_single (_ : S_batch) : S_single
  module Parallel_to_single (_ : S_single) : S_parallel
end
