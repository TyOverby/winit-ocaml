@@ portable

type t =
  { start_x : float32#
  ; end_x : float32#
  ; start_y : float32#
  ; end_y : float32#
  ; samples_x : int
  ; samples_y : int
  }
[@@deriving sexp_of]

val step_x : t -> float32#
val step_y : t -> float32#
val x_at : t -> int -> float32#
val y_at : t -> int -> float32#
val row : t -> int -> t
val point : x:float32# -> y:float32# -> t

(* Expand the region by [by_] samples in all directions. *)
val expand : t -> by_:int -> t
