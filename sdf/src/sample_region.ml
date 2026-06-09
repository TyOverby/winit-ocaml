open! Core

type t =
  { start_x : Float32_u.t
  ; end_x : Float32_u.t
  ; start_y : Float32_u.t
  ; end_y : Float32_u.t
  ; samples_x : int
  ; samples_y : int
  }
[@@deriving sexp_of]

let expand { start_x; end_x; start_y; end_y; samples_x; samples_y } ~by_ =
  let new_samples_x = samples_x + (by_ * 2) in
  let new_samples_y = samples_y + (by_ * 2) in
  let open Float32_u in
  let sample_width = (end_x - start_x) / of_int samples_x in
  let sample_height = (end_y - start_y) / of_int samples_y in
  { start_x = start_x - (sample_width * of_int by_)
  ; end_x = end_x + (sample_width * of_int by_)
  ; start_y = start_y - (sample_height * of_int by_)
  ; end_y = end_y + (sample_height * of_int by_)
  ; samples_x = new_samples_x
  ; samples_y = new_samples_y
  }
;;

let step_x t =
  (Float32_u.to_float t.end_x -. Float32_u.to_float t.start_x) /. Float.of_int t.samples_x
;;

let step_y t =
  (Float32_u.to_float t.end_y -. Float32_u.to_float t.start_y) /. Float.of_int t.samples_y
;;

let x_at t col =
  if col = 0
  then t.start_x
  else Float32_u.of_float (Float32_u.to_float t.start_x +. (step_x t *. Float.of_int col))
;;

let y_at t row =
  if row = 0
  then t.start_y
  else Float32_u.of_float (Float32_u.to_float t.start_y +. (step_y t *. Float.of_int row))
;;

let row t r =
  let y = y_at t r in
  { t with start_y = y; end_y = y; samples_y = 1 }
;;

let point ~x ~y =
  { start_x = x; end_x = x; samples_x = 1; start_y = y; end_y = y; samples_y = 1 }
;;
