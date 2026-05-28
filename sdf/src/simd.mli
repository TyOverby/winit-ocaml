@@ portable

(* vec128 casts *)
val float32x4_of_int32x4 : int32x4# -> float32x4#
val int32x4_of_float32x4 : float32x4# -> int32x4#

(* int32# array load/store *)
val arr_load : int32# array -> idx:int -> int32x4#
val arr_store : int32# array -> idx:int -> int32x4# -> unit

(* broadcast *)
val f32x4_set1 : float32# -> float32x4#
val i32x4_set1 : int32# -> int32x4#
val f32x4_zero : float32x4#
val f32x4_one : float32x4#

(* int32x4 bitwise *)
val i32x4_and : int32x4# -> int32x4# -> int32x4#
val i32x4_or : int32x4# -> int32x4# -> int32x4#
val i32x4_xor : int32x4# -> int32x4# -> int32x4#

(* int32x4 equality *)
val i32x4_cmpeq : int32x4# -> int32x4# -> int32x4#

(* float32x4 arithmetic *)
val f32x4_add : float32x4# -> float32x4# -> float32x4#
val f32x4_sub : float32x4# -> float32x4# -> float32x4#
val f32x4_mul : float32x4# -> float32x4# -> float32x4#
val f32x4_div : float32x4# -> float32x4# -> float32x4#
val f32x4_sqrt : float32x4# -> float32x4#
val f32x4_min : float32x4# -> float32x4# -> float32x4#
val f32x4_max : float32x4# -> float32x4# -> float32x4#

(* float32x4 abs/neg *)
val f32x4_neg : float32x4# -> float32x4#
val f32x4_abs : float32x4# -> float32x4#

(* float32x4 rounding *)
val f32x4_round_nearest : float32x4# -> float32x4#

(* float32x4 comparisons *)
val f32x4_lt : float32x4# -> float32x4# -> int32x4#
val f32x4_le : float32x4# -> float32x4# -> int32x4#
val f32x4_gt : float32x4# -> float32x4# -> int32x4#
val f32x4_ge : float32x4# -> float32x4# -> int32x4#

(* select *)
val i32x4_select : int32x4# -> fail:int32x4# -> pass:int32x4# -> int32x4#
val f32x4_select : int32x4# -> fail:float32x4# -> pass:float32x4# -> float32x4#
