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
val cond : loc:Source_code_position.t -> condition:t -> then_:t -> else_:t -> t Or_error.t
val lt : loc:Source_code_position.t -> t -> t -> t Or_error.t
val gt : loc:Source_code_position.t -> t -> t -> t Or_error.t
val lte : loc:Source_code_position.t -> t -> t -> t Or_error.t
val gte : loc:Source_code_position.t -> t -> t -> t Or_error.t
val and_ : loc:Source_code_position.t -> t -> t -> t Or_error.t
val or_ : loc:Source_code_position.t -> t -> t -> t Or_error.t
val xor : loc:Source_code_position.t -> t -> t -> t Or_error.t
