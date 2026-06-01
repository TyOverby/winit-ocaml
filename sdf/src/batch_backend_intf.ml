open! Core

module type S = sig @@ portable
  module Variable_idx : sig
    type t
  end

  module Prepared : sig
    type t

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
