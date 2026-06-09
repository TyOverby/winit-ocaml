open! Core
open Sdf

type t

val create : (module Executor.S) @ portable -> t
val add_oracle : t -> name:string -> (module Oracle.S) @ portable -> unit
val set_executor : t -> (module Executor.S) @ portable -> unit

val run
  :  t
  -> region:Sample_region.t
  -> filename:string
  -> string
  -> f:
       ('a.
        Parallel.t @ local
        -> 'a @ contended portable
        -> ('a -> x:int -> y:int -> Value.t) @ portable
        -> unit)
     @ once shareable
  -> unit
