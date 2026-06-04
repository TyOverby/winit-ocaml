type t =
  { start_x : float32#
  ; end_x : float32#
  ; samples_x : int
  ; start_y : float32#
  ; end_y : float32#
  ; samples_y : int
  }

let (step_x @ portable) t =
  (Float32_u.to_float t.end_x -. Float32_u.to_float t.start_x) /. Float.of_int t.samples_x
;;

let (step_y @ portable) t =
  (Float32_u.to_float t.end_y -. Float32_u.to_float t.start_y) /. Float.of_int t.samples_y
;;

let (x_at @ portable) t col =
  if col = 0
  then t.start_x
  else Float32_u.of_float (Float32_u.to_float t.start_x +. (step_x t *. Float.of_int col))
;;

let (y_at @ portable) t row =
  if row = 0
  then t.start_y
  else Float32_u.of_float (Float32_u.to_float t.start_y +. (step_y t *. Float.of_int row))
;;

let (row @ portable) t r =
  let y = y_at t r in
  { t with start_y = y; end_y = y; samples_y = 1 }
;;

let (point @ portable) ~x ~y =
  { start_x = x; end_x = x; samples_x = 1; start_y = y; end_y = y; samples_y = 1 }
;;
