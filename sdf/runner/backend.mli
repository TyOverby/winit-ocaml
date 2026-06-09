open! Core
open Sdf

module type S = sig
  module E : Executor.S

  type t

  val create : unit -> t

  val add_oracle : t -> name:string -> (module Oracle.S) @ portable -> unit
  val scheduler : t -> Parallel_scheduler.t

  val run
    :  t
    -> region:Sample_region.t
    -> filename:string
    -> string
    -> E.Parallel.Result.t
end

module Make (E : Executor.S @ portable) : S with module E = E
