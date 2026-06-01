@@ portable

open! Core

module Register_bank : sig
  type t

  val create : register_count:int -> width:int -> t

  (** Get result from register [reg] at pixel [px] *)
  val get_result : t -> reg:int -> px:int -> Value.t
end

module Variable_bank : sig
  type t

  val create : num_vars:int -> width:int -> t

  (** Fill variable [var] for pixel [px] *)
  val set_variable : t -> var:int -> px:int -> Value.t -> unit
end

(** Run all instructions across [width] pixels in one pass *)
val run
  :  variable_bank:Variable_bank.t
  -> instructions:Expr_graph.t
  -> register_bank:Register_bank.t
  -> width:int
  -> unit

module Batched : Batch_backend_intf.S

(** Grid-native ({!Batch_backend_intf.S_parallel}) wrapper over {!Batched}.

    [@@ nonportable] because [S_parallel.Batch.run] drives the scheduler and so cannot be
    portable; without it the enclosing [@@ portable] signature would demand a fully
    portable module. *)
module (Batch_parallel @@ nonportable) : Batch_backend_intf.S_parallel
