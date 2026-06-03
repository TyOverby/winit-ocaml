open! Core

type t = Int32_u.t [@@deriving sexp_of, equal, compare, quickcheck]

let of_float (f : Float32_u.t) : t = Float32_u.to_bits f
let of_int (i : Int32_u.t) : t = i
let to_float (t : t) : Float32_u.t = Float32_u.of_bits t
let to_int (t : t) : Int32_u.t = t
let of_bool b = of_int (if b then #1l else #0l)

let to_bool t =
  match to_int t with
  | #0l -> false
  | _ -> true
;;

module Boxed = struct
  type nonrec t = T of t
end

let box t = Boxed.T t
let unbox (Boxed.T t) = t

module Array = struct
  type t = Int32_u.t array

  let create ~len = Array.create ~len #0l
  let get = Array.unsafe_get
  let get_int t n = Array.unsafe_get t n
  let get_float t n = get_int t n |> to_float
  let get_bool t n = get_int t n |> to_bool
  let set_int t n v = Array.unsafe_set t n v
  let set_bool t n v = set_int t n (of_bool v)
  let set_float t n v = set_int t n (of_float v)
  let set = Array.unsafe_set
end
