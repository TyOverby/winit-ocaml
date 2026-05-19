open! Base

module Type = struct
  type 'a t =
    | Bool : bool t
    | Float : float t
  [@@deriving sexp_of, hash]

  let compare : type a b. a t -> b t -> int =
    fun a b ->
    match a, b with
    | Bool, Bool | Float, Float -> 0
    | Bool, Float -> -1
    | Float, Bool -> 1
  ;;

  let equal : type a b. a t -> b t -> bool =
    fun a b ->
    match a, b with
    | Bool, Bool | Float, Float -> true
    | _ -> false
  ;;

  let hash_fold_fn : type a. a t -> (Hash.state -> a -> Hash.state) = function
    | Bool -> hash_fold_bool
    | Float -> hash_fold_float
  ;;

  let equal_fn : type a. a t -> (a -> a -> bool) = function
    | Bool -> equal_bool
    | Float -> equal_float
  ;;

  let sexp_of_fn : type a. a t -> (a -> Sexp.t) = function
    | Bool -> sexp_of_bool
    | Float -> sexp_of_float
  ;;

  let compare_fn : type a. a t -> (a -> a -> int) = function
    | Bool -> compare_bool
    | Float -> compare_float
  ;;

  let type_equal : type a b. a t -> b t -> (a, b) Type_equal.t option =
    fun a b ->
    match a, b with
    | Bool, Bool -> Some T
    | Float, Float -> Some T
    | _ -> None
  ;;
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
[@@deriving hash, sexp_of]

let ord : type a. a t -> int = function
  | Var _ -> 0
  | Constant _ -> 1
  | Add _ -> 2
  | Sub _ -> 3
  | Mul _ -> 4
  | Div _ -> 5
  | Cond _ -> 6
  | Eq _ -> 7
  | Lt _ -> 8
  | Lte _ -> 9
  | Gt _ -> 10
  | Gte _ -> 11
;;

let rec compare_many = function
  | [] -> 0
  | 0 :: tl -> compare_many tl
  | other :: _ -> other
;;

let rec compare : type a. (a -> a -> int) -> a t -> a t -> int =
  fun f a b ->
  match a, b with
  | Var (a, t1), Var (b, t2) -> compare_many [ compare_string a b; Type.compare t1 t2 ]
  | Constant (a, t1), Constant (b, t2) -> compare_many [ f a b; Type.compare t1 t2 ]
  | Add (a1, a2), Add (b1, b2) -> compare_many [ compare f a1 b1; compare f a2 b2 ]
  | Sub (a1, a2), Sub (b1, b2) -> compare_many [ compare f a1 b1; compare f a2 b2 ]
  | Mul (a1, a2), Mul (b1, b2) -> compare_many [ compare f a1 b1; compare f a2 b2 ]
  | Div (a1, a2), Div (b1, b2) -> compare_many [ compare f a1 b1; compare f a2 b2 ]
  | Cond (c1, t1, e1), Cond (c2, t2, e2) ->
    compare_many [ compare compare_bool c1 c2; compare f t1 t2; compare f e1 e2 ]
  | Eq (a1, a2), Eq (b1, b2) ->
    compare_many [ compare compare_float a1 b1; compare compare_float a2 b2 ]
  | Lt (a1, a2), Lt (b1, b2) ->
    compare_many [ compare compare_float a1 b1; compare compare_float a2 b2 ]
  | Lte (a1, a2), Lte (b1, b2) ->
    compare_many [ compare compare_float a1 b1; compare compare_float a2 b2 ]
  | Gt (a1, a2), Gte (b1, b2) ->
    compare_many [ compare compare_float a1 b1; compare compare_float a2 b2 ]
  | _, _ -> compare_int (ord a) (ord b)
;;

let rec equal : type a. (a -> a -> bool) -> a t -> a t -> bool =
  fun f a b ->
  match a, b with
  | Var (a, t1), Var (b, t2) -> equal_string a b && Type.equal t1 t2
  | Constant (a, t1), Constant (b, t2) -> f a b && Type.equal t1 t2
  | Add (a1, a2), Add (b1, b2) -> equal f a1 b1 && equal f a2 b2
  | Sub (a1, a2), Sub (b1, b2) -> equal f a1 b1 && equal f a2 b2
  | Mul (a1, a2), Mul (b1, b2) -> equal f a1 b1 && equal f a2 b2
  | Div (a1, a2), Div (b1, b2) -> equal f a1 b1 && equal f a2 b2
  | Cond (c1, t1, e1), Cond (c2, t2, e2) ->
    equal equal_bool c1 c2 && equal f t1 t2 && equal f e1 e2
  | Eq (a1, a2), Eq (b1, b2) -> equal equal_float a1 b1 && equal equal_float a2 b2
  | Lt (a1, a2), Lt (b1, b2) -> equal equal_float a1 b1 && equal equal_float a2 b2
  | Lte (a1, a2), Lte (b1, b2) -> equal equal_float a1 b1 && equal equal_float a2 b2
  | Gt (a1, a2), Gt (b1, b2) -> equal equal_float a1 b1 && equal equal_float a2 b2
  | Gte (a1, a2), Gte (b1, b2) -> equal equal_float a1 b1 && equal equal_float a2 b2
  | _, _ -> false
;;

let rec type_of : type a. a t -> a Type.t = function
  | Var (_, t) -> t
  | Constant (_, t) -> t
  | Add _ -> Float
  | Sub _ -> Float
  | Mul _ -> Float
  | Div _ -> Float
  | Cond (_, t, _) -> type_of t
  | Eq _ -> Bool
  | Lt _ -> Bool
  | Lte _ -> Bool
  | Gt _ -> Bool
  | Gte _ -> Bool
;;

module Packed = struct
  type 'a t' = 'a t

  type t =
    | T :
        { expr : 'a t'
        ; type_ : 'a Type.t
        }
        -> t

  let compare (T { expr = expr_a; type_ = type_a }) (T { expr = expr_b; type_ = type_b }) =
    match Type.type_equal type_a type_b with
    | Some T -> compare (Type.compare_fn type_a) expr_a expr_b
    | None -> Type.compare type_a type_b
  ;;

  let equal (T { expr = expr_a; type_ = type_a }) (T { expr = expr_b; type_ = type_b }) =
    match Type.type_equal type_a type_b with
    | Some T -> equal (Type.equal_fn type_a) expr_a expr_b
    | None -> false
  ;;

  let hash_fold_t hash_state (T { expr = expr_a; type_ = type_a }) =
    let hash_state = hash_fold_t (Type.hash_fold_fn type_a) hash_state expr_a in
    Type.hash_fold_t (fun _ -> assert false) hash_state type_a
  ;;

  let sexp_of_t (T { expr; type_ }) = sexp_of_t (Type.sexp_of_fn type_) expr

  let hash t =
    let state = Hash.alloc () in
    let state = hash_fold_t state t in
    Hash.get_hash_value state
  ;;

  include functor Core.Hashable.Make_plain
end

let pack expr =
  let type_ = type_of expr in
  Packed.T { expr; type_ }
;;
