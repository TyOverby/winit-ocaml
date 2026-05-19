open! Base

module Type : sig
  type 'a t =
    | Bool : bool t
    | Float : float t
  [@@deriving hash, sexp_of]

  val type_equal : 'a t -> 'b t -> ('a, 'b) Type_equal.t option
end

type 'a t =
  | Var : string * 'a Type.t -> 'a t
  | Constant : 'a * 'a Type.t -> 'a t
  | Add : float t * float t -> float t
  | Sub : float t * float t -> float t
  | Mul : float t * float t -> float t
  | Div : float t * float t -> float t
  | Cond : bool t * 'a t * 'a t -> 'a t
  | Eq : float t * float t -> bool t
  | Lt : float t * float t -> bool t
  | Lte : float t * float t -> bool t
  | Gt : float t * float t -> bool t
  | Gte : float t * float t -> bool t
[@@deriving hash, sexp_of, compare, equal]

val type_of : 'a t -> 'a Type.t

module Packed : sig
  type 'a t' = 'a t

  type t =
    | T :
        { expr : 'a t'
        ; type_ : 'a Type.t
        }
        -> t
  [@@deriving compare, equal, hash]
end

val pack : _ t -> Packed.t
