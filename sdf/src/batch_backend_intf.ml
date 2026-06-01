open! Core

module type S = sig @@ portable
  module Variable_idx : sig
    (* [Prepared.t] and [Variable_idx.t] mode-cross portability and contention so that a
       prepared program (and the variable indices looked up from it) can be shared across
       the worker domains of a parallel render. *)
    type t : value mod portable contended
  end

  module Prepared : sig
    type t : value mod portable contended

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
    val run : t -> Result.t
  end
end
