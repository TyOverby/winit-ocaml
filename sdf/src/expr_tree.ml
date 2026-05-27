open! Core

(* Shadow Float32_u with bitwise comparison for CSE correctness.
   IEEE 754 treats -0.0 = +0.0, but they have different bit patterns
   and different semantics (e.g., 1/+0 = +inf, 1/-0 = -inf), so the
   expression tree's equality must distinguish them. *)
module Float32_u = struct
  include Float32_u

  let equal a b = Int32_u.equal (to_bits a) (to_bits b)
  let compare a b = Int32_u.compare (to_bits a) (to_bits b)
end

module Type = struct
  type t =
    | Bool
    | Float
  [@@deriving sexp, equal, compare, hash, quickcheck]
end

module Source_code_position = struct
  type t = Source_code_position.t [@@deriving sexp_of, hash]

  (* Ignore source positions in structural comparison so that CSE in
     [Expr_graph.from_tree] can merge identical subexpressions regardless
     of where they were defined. *)
  let equal _ _ = true
  let compare _ _ = 0

  let quickcheck_generator = Quickcheck.Generator.return Stdlib.Lexing.dummy_pos

  let quickcheck_observer =
    Quickcheck.Observer.create (fun pos ~size:_ ~hash ->
      Source_code_position.hash_fold_t hash pos)
  ;;

  let quickcheck_shrinker = Quickcheck.Shrinker.create Sequence.return
end

module Var_name = struct
  type t = string [@@deriving sexp_of, equal, compare, hash]

  let quickcheck_generator = Quickcheck.Generator.of_list [ "x"; "y" ]

  let quickcheck_observer =
    Quickcheck.Observer.create (fun s ~size:_ ~hash -> hash_fold_t hash s)
  ;;

  let quickcheck_shrinker = Quickcheck.Shrinker.empty ()
end

type t =
  { loc : Source_code_position.t
  ; kind : kind
  ; type_ : Type.t
  }

and kind =
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
[@@deriving sexp_of, equal, compare, quickcheck]

include functor Comparator.Make [@mode portable]

let both_float name a b =
  match a.type_, b.type_ with
  | Type.Float, Type.Float -> Ok ()
  | Float, Bool ->
    Error
      (Error.create_s
         [%message
           "RHS of operator is a bool"
             (name : string)
             ~loc:(b.loc : Source_code_position.t)])
  | Bool, Float ->
    Error
      (Error.create_s
         [%message
           "LHS of operator is a bool"
             (name : string)
             ~loc:(a.loc : Source_code_position.t)])
  | Bool, Bool ->
    Error
      (Error.create_s
         [%message
           "both arguments to operator are bools"
             (name : string)
             ~lhs_loc:(a.loc : Source_code_position.t)
             ~rhs_loc:(b.loc : Source_code_position.t)])
;;

let both_bool name a b =
  match a.type_, b.type_ with
  | Type.Bool, Type.Bool -> Ok ()
  | Bool, Float ->
    Error
      (Error.create_s
         [%message
           "RHS of operator is a float"
             (name : string)
             ~loc:(b.loc : Source_code_position.t)])
  | Float, Bool ->
    Error
      (Error.create_s
         [%message
           "LHS of operator is a float"
             (name : string)
             ~loc:(a.loc : Source_code_position.t)])
  | Float, Float ->
    Error
      (Error.create_s
         [%message
           "both arguments to operator are floats"
             (name : string)
             ~lhs_loc:(a.loc : Source_code_position.t)
             ~rhs_loc:(b.loc : Source_code_position.t)])
;;

let float_literal ~loc v = Ok { loc; kind = Float_literal v; type_ = Type.Float }
let bool_literal ~loc v = Ok { loc; kind = Bool_literal v; type_ = Type.Bool }
let var ~loc name type_ = Ok { loc; kind = Var (name, type_); type_ }

let add ~loc a b =
  let%map.Or_error () = both_float "addition" a b in
  { loc; kind = Add (a, b); type_ = Type.Float }
;;

let mul ~loc a b =
  let%map.Or_error () = both_float "multiplication" a b in
  { loc; kind = Mul (a, b); type_ = Type.Float }
;;

let sub ~loc a b =
  let%map.Or_error () = both_float "subtraction" a b in
  { loc; kind = Sub (a, b); type_ = Type.Float }
;;

let div ~loc a b =
  let%map.Or_error () = both_float "division" a b in
  { loc; kind = Div (a, b); type_ = Type.Float }
;;

let sqrt ~loc a =
  match a.type_ with
  | Type.Float -> Ok { loc; kind = Sqrt a; type_ = Type.Float }
  | Bool ->
    Error
      (Error.create_s
         [%message "argument to sqrt is a bool" ~loc:(a.loc : Source_code_position.t)])
;;

let unary_float name kind ~loc a =
  match a.type_ with
  | Type.Float -> Ok { loc; kind = kind a; type_ = Type.Float }
  | Bool ->
    Error
      (Error.create_s
         [%message
           ("argument to " ^ name ^ " is a bool") ~loc:(a.loc : Source_code_position.t)])
;;

let abs ~loc a = unary_float "abs" (fun a -> Abs a) ~loc a
let neg ~loc a = unary_float "neg" (fun a -> Neg a) ~loc a
let sign ~loc a = unary_float "sign" (fun a -> Sign a) ~loc a
let sin ~loc a = unary_float "sin" (fun a -> Sin a) ~loc a
let cos ~loc a = unary_float "cos" (fun a -> Cos a) ~loc a
let round ~loc a = unary_float "round" (fun a -> Round a) ~loc a

let min ~loc a b =
  let%map.Or_error () = both_float "min" a b in
  { loc; kind = Min (a, b); type_ = Type.Float }
;;

let max ~loc a b =
  let%map.Or_error () = both_float "max" a b in
  { loc; kind = Max (a, b); type_ = Type.Float }
;;

let cond ~loc ~condition ~then_ ~else_ =
  let%bind.Or_error () =
    match condition.type_ with
    | Bool -> Ok ()
    | Float ->
      Error
        (Error.create_s
           [%message "condition is a float" ~loc:(condition.loc : Source_code_position.t)])
  in
  let%map.Or_error type_ =
    match then_.type_, else_.type_ with
    | Float, Float -> Ok Type.Float
    | Bool, Bool -> Ok Type.Bool
    | Float, Bool | Bool, Float ->
      Error
        (Error.create_s
           [%message
             "conditional arms disagree"
               ~then_loc:(then_.loc : Source_code_position.t)
               ~else_loc:(else_.loc : Source_code_position.t)])
  in
  { loc; kind = Cond { condition; then_; else_ }; type_ }
;;

let lt ~loc a b =
  let%map.Or_error () = both_float "less than" a b in
  { loc; kind = Lt (a, b); type_ = Type.Bool }
;;

let gt ~loc a b =
  let%map.Or_error () = both_float "greater than" a b in
  { loc; kind = Gt (a, b); type_ = Type.Bool }
;;

let lte ~loc a b =
  let%map.Or_error () = both_float "less than or equal to" a b in
  { loc; kind = Lte (a, b); type_ = Type.Bool }
;;

let gte ~loc a b =
  let%map.Or_error () = both_float "greater than or equal to" a b in
  { loc; kind = Gte (a, b); type_ = Type.Bool }
;;

let and_ ~loc a b =
  let%map.Or_error () = both_bool "and" a b in
  { loc; kind = And (a, b); type_ = Type.Bool }
;;

let or_ ~loc a b =
  let%map.Or_error () = both_bool "or" a b in
  { loc; kind = Or (a, b); type_ = Type.Bool }
;;

let xor ~loc a b =
  let%map.Or_error () = both_bool "xor" a b in
  { loc; kind = Xor (a, b); type_ = Type.Bool }
;;

module Direct = struct
  let float_literal ~(loc : [%call_pos]) v = Or_error.ok_exn (float_literal ~loc v)
  let bool_literal ~(loc : [%call_pos]) v = Or_error.ok_exn (bool_literal ~loc v)
  let var ~(loc : [%call_pos]) name type_ = Or_error.ok_exn (var ~loc name type_)
  let add ~(loc : [%call_pos]) a b = Or_error.ok_exn (add ~loc a b)
  let mul ~(loc : [%call_pos]) a b = Or_error.ok_exn (mul ~loc a b)
  let sub ~(loc : [%call_pos]) a b = Or_error.ok_exn (sub ~loc a b)
  let div ~(loc : [%call_pos]) a b = Or_error.ok_exn (div ~loc a b)
  let sqrt ~(loc : [%call_pos]) a = Or_error.ok_exn (sqrt ~loc a)
  let abs ~(loc : [%call_pos]) a = Or_error.ok_exn (abs ~loc a)
  let neg ~(loc : [%call_pos]) a = Or_error.ok_exn (neg ~loc a)
  let sign ~(loc : [%call_pos]) a = Or_error.ok_exn (sign ~loc a)
  let sin ~(loc : [%call_pos]) a = Or_error.ok_exn (sin ~loc a)
  let cos ~(loc : [%call_pos]) a = Or_error.ok_exn (cos ~loc a)
  let round ~(loc : [%call_pos]) a = Or_error.ok_exn (round ~loc a)
  let min ~(loc : [%call_pos]) a b = Or_error.ok_exn (min ~loc a b)
  let max ~(loc : [%call_pos]) a b = Or_error.ok_exn (max ~loc a b)

  let cond ~(loc : [%call_pos]) ~condition ~then_ ~else_ () =
    Or_error.ok_exn (cond ~loc ~condition ~then_ ~else_)
  ;;

  let lt ~(loc : [%call_pos]) a b = Or_error.ok_exn (lt ~loc a b)
  let gt ~(loc : [%call_pos]) a b = Or_error.ok_exn (gt ~loc a b)
  let lte ~(loc : [%call_pos]) a b = Or_error.ok_exn (lte ~loc a b)
  let gte ~(loc : [%call_pos]) a b = Or_error.ok_exn (gte ~loc a b)
  let and_ ~(loc : [%call_pos]) a b = Or_error.ok_exn (and_ ~loc a b)
  let or_ ~(loc : [%call_pos]) a b = Or_error.ok_exn (or_ ~loc a b)
  let xor ~(loc : [%call_pos]) a b = Or_error.ok_exn (xor ~loc a b)
  let ( + ) = add
  let ( - ) = sub
  let ( * ) = mul
  let ( / ) = div
  let ( < ) = lt
  let ( > ) = gt
  let ( <= ) = lte
  let ( >= ) = gte
  let ( && ) = and_
  let ( || ) = or_
end
