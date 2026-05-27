@@ portable

open! Core

module Type : sig
  type t =
    | Bool
    | Float
  [@@deriving sexp, equal, compare, hash]
end

module Var_name : sig
  type t = string [@@deriving sexp_of, equal, compare, hash]
end

type t = private
  { loc : Source_code_position.t
  ; kind : kind
  ; type_ : Type.t
  }

and kind = private
  | Float_literal of Float32_u.t
  | Bool_literal of bool
  | Var of Var_name.t * Type.t
  | Add of t * t
  | Mul of t * t
  | Sub of t * t
  | Div of t * t
  | Cond of
      { condition : t
      ; then_ : t
      ; else_ : t
      }
  | Lt of t * t
  | Gt of t * t
  | Lte of t * t
  | Gte of t * t
  | Sqrt of t
  | Abs of t
  | Neg of t
  | Sign of t
  | Sin of t
  | Cos of t
  | Round of t
  | Min of t * t
  | Max of t * t
  | And of t * t
  | Or of t * t
  | Xor of t * t
[@@deriving sexp_of, equal, compare]

include Comparator.S [@portable] with type t := t

val float_literal : loc:Source_code_position.t -> float32# -> t Or_error.t
val bool_literal : loc:Source_code_position.t -> bool -> t Or_error.t
val var : loc:Source_code_position.t -> string -> Type.t -> t Or_error.t
val add : loc:Source_code_position.t -> t -> t -> t Or_error.t
val mul : loc:Source_code_position.t -> t -> t -> t Or_error.t
val sub : loc:Source_code_position.t -> t -> t -> t Or_error.t
val div : loc:Source_code_position.t -> t -> t -> t Or_error.t
val sqrt : loc:Source_code_position.t -> t -> t Or_error.t
val abs : loc:Source_code_position.t -> t -> t Or_error.t
val neg : loc:Source_code_position.t -> t -> t Or_error.t
val sign : loc:Source_code_position.t -> t -> t Or_error.t
val sin : loc:Source_code_position.t -> t -> t Or_error.t
val cos : loc:Source_code_position.t -> t -> t Or_error.t
val round : loc:Source_code_position.t -> t -> t Or_error.t
val min : loc:Source_code_position.t -> t -> t -> t Or_error.t
val max : loc:Source_code_position.t -> t -> t -> t Or_error.t
val cond : loc:Source_code_position.t -> condition:t -> then_:t -> else_:t -> t Or_error.t
val lt : loc:Source_code_position.t -> t -> t -> t Or_error.t
val gt : loc:Source_code_position.t -> t -> t -> t Or_error.t
val lte : loc:Source_code_position.t -> t -> t -> t Or_error.t
val gte : loc:Source_code_position.t -> t -> t -> t Or_error.t
val and_ : loc:Source_code_position.t -> t -> t -> t Or_error.t
val or_ : loc:Source_code_position.t -> t -> t -> t Or_error.t
val xor : loc:Source_code_position.t -> t -> t -> t Or_error.t

(** Raising variants of the constructors. Type errors raise instead of
    returning [Or_error.t]. The [loc] parameter is automatically filled
    by [[%call_pos]]. *)
module Direct : sig
  val float_literal : loc:[%call_pos] -> float32# -> t
  val bool_literal : loc:[%call_pos] -> bool -> t
  val var : loc:[%call_pos] -> string -> Type.t -> t
  val add : loc:[%call_pos] -> t -> t -> t
  val mul : loc:[%call_pos] -> t -> t -> t
  val sub : loc:[%call_pos] -> t -> t -> t
  val div : loc:[%call_pos] -> t -> t -> t
  val sqrt : loc:[%call_pos] -> t -> t
  val abs : loc:[%call_pos] -> t -> t
  val neg : loc:[%call_pos] -> t -> t
  val sign : loc:[%call_pos] -> t -> t
  val sin : loc:[%call_pos] -> t -> t
  val cos : loc:[%call_pos] -> t -> t
  val round : loc:[%call_pos] -> t -> t
  val min : loc:[%call_pos] -> t -> t -> t
  val max : loc:[%call_pos] -> t -> t -> t
  val cond : loc:[%call_pos] -> condition:t -> then_:t -> else_:t -> unit -> t
  val lt : loc:[%call_pos] -> t -> t -> t
  val gt : loc:[%call_pos] -> t -> t -> t
  val lte : loc:[%call_pos] -> t -> t -> t
  val gte : loc:[%call_pos] -> t -> t -> t
  val and_ : loc:[%call_pos] -> t -> t -> t
  val or_ : loc:[%call_pos] -> t -> t -> t
  val xor : loc:[%call_pos] -> t -> t -> t
end
