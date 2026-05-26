@@ portable

open! Core

(** Untagged union of [float32#] and [int32#].

    Values are stored as raw 32-bit data with no runtime tag distinguishing floats from
    ints. The static type system is responsible for tracking which interpretation is
    correct; converting between the two views reinterprets the bit pattern. *)
type t : bits32 [@@deriving sexp_of, equal, compare, quickcheck]

val of_float : Float32_u.t -> t
val of_int : Int32_u.t -> t
val of_bool : bool -> t
val to_float : t -> Float32_u.t
val to_int : t -> Int32_u.t
val to_bool : t -> bool

module Boxed : sig
  type nonrec t = T of t
end

module Array : sig
  type value := t
  type t

  val create : len:int -> t

  (** Getters *)
  val get : t -> int -> value

  val get_int : t -> int -> int32#
  val get_float : t -> int -> float32#
  val get_bool : t -> int -> bool

  (** Setters *)
  val set : t -> int -> value -> unit

  val set_int : t -> int -> int32# -> unit
  val set_float : t -> int -> float32# -> unit
  val set_bool : t -> int -> bool -> unit
end
