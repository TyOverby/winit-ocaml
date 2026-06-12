(* Minimal cross-platform SIMD shim using only compiler builtins. Works on both amd64
   (SSE) and arm64 (NEON) without any external library.

   Uses [@@builtin (amd64, "name") (arm64, "name")] to let the compiler select the correct
   instruction per architecture. Architecture-specific ops (comparisons, rounding,
   shuffle) use [@@builtin arch, "name"] with [Sys.arch] dispatch; the compiler eliminates
   the dead branch. *)

(* ---- vec128 casts (zero-cost bit reinterpretation) ---- *)

external float32x4_of_int32x4
  :  int32x4#
  -> float32x4#
  @@ portable
  = "sdf_simd_unreachable" "caml_vec128_cast"
[@@noalloc] [@@builtin]

external int32x4_of_float32x4
  :  float32x4#
  -> int32x4#
  @@ portable
  = "sdf_simd_unreachable" "caml_vec128_cast"
[@@noalloc] [@@builtin]

(* ---- int32# array load/store (compiler primitives, cross-platform) ---- *)

external arr_load
  :  (int32# array[@local_opt]) @ read
  -> idx:int
  -> int32x4#
  @@ portable
  = "%caml_unboxed_int32_array_get128u#"

external arr_store
  :  (int32# array[@local_opt])
  -> idx:int
  -> int32x4#
  -> unit
  @@ portable
  = "%caml_unboxed_int32_array_set128u#"

(* ---- broadcast (set1) ---- *)

external f32x4_low_of
  :  float32#
  -> float32x4#
  @@ portable
  = "sdf_simd_unreachable" "caml_float32x4_low_of_float32"
[@@noalloc] [@@builtin]

external amd64_shuffle_f32x4
  :  (int[@untagged])
  -> float32x4#
  -> float32x4#
  -> float32x4#
  @@ portable
  = "sdf_simd_unreachable" "sdf_simd_unreachable"
[@@noalloc] [@@builtin amd64, "caml_sse_vec128_shuffle_32"]

external arm64_broadcast_i32x4
  :  int32x4#
  -> int32x4#
  @@ portable
  = "sdf_simd_unreachable" "sdf_simd_unreachable"
[@@noalloc] [@@builtin arm64, "caml_neon_int32x4_dup"]

let[@inline] f32x4_set1 (a : float32#) : float32x4# =
  let v = f32x4_low_of a in
  match Sys.arch with
  | Amd64 -> amd64_shuffle_f32x4 0 v v
  | Arm64 -> float32x4_of_int32x4 (arm64_broadcast_i32x4 (int32x4_of_float32x4 v))
;;

let[@inline] i32x4_set1 (a : int32#) : int32x4# =
  int32x4_of_float32x4 (f32x4_set1 (Float32_u.of_bits a))
;;

let f32x4_zero = f32x4_set1 #0.0s
let f32x4_one = f32x4_set1 #1.0s

(* ---- int32x4 bitwise ops ---- *)

external i32x4_and
  :  int32x4#
  -> int32x4#
  -> int32x4#
  @@ portable
  = "sdf_simd_unreachable" "sdf_simd_unreachable"
[@@noalloc]
[@@builtin (amd64, "caml_sse_vec128_and") (arm64, "caml_neon_int32x4_bitwise_and")]

external i32x4_or
  :  int32x4#
  -> int32x4#
  -> int32x4#
  @@ portable
  = "sdf_simd_unreachable" "sdf_simd_unreachable"
[@@noalloc]
[@@builtin (amd64, "caml_sse_vec128_or") (arm64, "caml_neon_int32x4_bitwise_or")]

external i32x4_xor
  :  int32x4#
  -> int32x4#
  -> int32x4#
  @@ portable
  = "sdf_simd_unreachable" "sdf_simd_unreachable"
[@@noalloc]
[@@builtin (amd64, "caml_sse_vec128_xor") (arm64, "caml_neon_int32x4_bitwise_xor")]

(* ---- int32x4 equality ---- *)

external i32x4_cmpeq
  :  int32x4#
  -> int32x4#
  -> int32x4#
  @@ portable
  = "sdf_simd_unreachable" "sdf_simd_unreachable"
[@@noalloc]
[@@builtin (amd64, "caml_sse2_int32x4_cmpeq") (arm64, "caml_neon_int32x4_cmpeq")]

(* ---- float32x4 arithmetic ---- *)

external f32x4_add
  :  float32x4#
  -> float32x4#
  -> float32x4#
  @@ portable
  = "sdf_simd_unreachable" "sdf_simd_unreachable"
[@@noalloc]
[@@builtin (amd64, "caml_sse_float32x4_add") (arm64, "caml_neon_float32x4_add")]

external f32x4_sub
  :  float32x4#
  -> float32x4#
  -> float32x4#
  @@ portable
  = "sdf_simd_unreachable" "sdf_simd_unreachable"
[@@noalloc]
[@@builtin (amd64, "caml_sse_float32x4_sub") (arm64, "caml_neon_float32x4_sub")]

external f32x4_mul
  :  float32x4#
  -> float32x4#
  -> float32x4#
  @@ portable
  = "sdf_simd_unreachable" "sdf_simd_unreachable"
[@@noalloc]
[@@builtin (amd64, "caml_sse_float32x4_mul") (arm64, "caml_neon_float32x4_mul")]

external f32x4_div
  :  float32x4#
  -> float32x4#
  -> float32x4#
  @@ portable
  = "sdf_simd_unreachable" "sdf_simd_unreachable"
[@@noalloc]
[@@builtin (amd64, "caml_sse_float32x4_div") (arm64, "caml_neon_float32x4_div")]

external f32x4_sqrt
  :  float32x4#
  -> float32x4#
  @@ portable
  = "sdf_simd_unreachable" "sdf_simd_unreachable"
[@@noalloc]
[@@builtin (amd64, "caml_sse_float32x4_sqrt") (arm64, "caml_neon_float32x4_sqrt")]

external f32x4_min_raw
  :  float32x4#
  -> float32x4#
  -> float32x4#
  @@ portable
  = "sdf_simd_unreachable" "sdf_simd_unreachable"
[@@noalloc]
[@@builtin (amd64, "caml_sse_float32x4_min") (arm64, "caml_neon_float32x4_min")]

external f32x4_max_raw
  :  float32x4#
  -> float32x4#
  -> float32x4#
  @@ portable
  = "sdf_simd_unreachable" "sdf_simd_unreachable"
[@@noalloc]
[@@builtin (amd64, "caml_sse_float32x4_max") (arm64, "caml_neon_float32x4_max")]

(* ---- float32x4 rounding ---- *)

external amd64_f32x4_round
  :  (int[@untagged])
  -> float32x4#
  -> float32x4#
  @@ portable
  = "sdf_simd_unreachable" "sdf_simd_unreachable"
[@@noalloc] [@@builtin amd64, "caml_sse41_float32x4_round"]

external arm64_f32x4_round_nearest
  :  float32x4#
  -> float32x4#
  @@ portable
  = "sdf_simd_unreachable" "sdf_simd_unreachable"
[@@noalloc] [@@builtin arm64, "caml_neon_float32x4_round_near"]

let[@inline] f32x4_round_nearest (v : float32x4#) : float32x4# =
  match Sys.arch with
  | Amd64 -> amd64_f32x4_round 0x8 v (* 0x8 = Nearest *)
  | Arm64 -> arm64_f32x4_round_nearest v
;;

(* ---- float32x4 comparisons (return int32x4# mask: all-1s or all-0s per lane) ---- *)

(* amd64: SSE cmpps takes mode parameter (0x1=Less, 0x2=Less_or_equal) *)
external amd64_f32x4_cmp
  :  (int[@untagged])
  -> float32x4#
  -> float32x4#
  -> int32x4#
  @@ portable
  = "sdf_simd_unreachable" "sdf_simd_unreachable"
[@@noalloc] [@@builtin amd64, "caml_sse_float32x4_cmp"]

external arm64_f32x4_cmpgt
  :  float32x4#
  -> float32x4#
  -> int32x4#
  @@ portable
  = "sdf_simd_unreachable" "sdf_simd_unreachable"
[@@noalloc] [@@builtin arm64, "caml_neon_float32x4_cmgt"]

external arm64_f32x4_cmpge
  :  float32x4#
  -> float32x4#
  -> int32x4#
  @@ portable
  = "sdf_simd_unreachable" "sdf_simd_unreachable"
[@@noalloc] [@@builtin arm64, "caml_neon_float32x4_cmge"]

external arm64_f32x4_cmplt
  :  float32x4#
  -> float32x4#
  -> int32x4#
  @@ portable
  = "sdf_simd_unreachable" "sdf_simd_unreachable"
[@@noalloc] [@@builtin arm64, "caml_neon_float32x4_cmlt"]

external arm64_f32x4_cmple
  :  float32x4#
  -> float32x4#
  -> int32x4#
  @@ portable
  = "sdf_simd_unreachable" "sdf_simd_unreachable"
[@@noalloc] [@@builtin arm64, "caml_neon_float32x4_cmle"]

let[@inline] f32x4_lt (a : float32x4#) (b : float32x4#) : int32x4# =
  match Sys.arch with
  | Amd64 -> amd64_f32x4_cmp 0x1 a b
  | Arm64 -> arm64_f32x4_cmplt a b
;;

let[@inline] f32x4_le (a : float32x4#) (b : float32x4#) : int32x4# =
  match Sys.arch with
  | Amd64 -> amd64_f32x4_cmp 0x2 a b
  | Arm64 -> arm64_f32x4_cmple a b
;;

let[@inline] f32x4_gt (a : float32x4#) (b : float32x4#) : int32x4# =
  match Sys.arch with
  | Amd64 -> amd64_f32x4_cmp 0x1 b a (* swap args: a>b = b<a *)
  | Arm64 -> arm64_f32x4_cmpgt a b
;;

let[@inline] f32x4_ge (a : float32x4#) (b : float32x4#) : int32x4# =
  match Sys.arch with
  | Amd64 -> amd64_f32x4_cmp 0x2 b a (* swap args: a>=b = b<=a *)
  | Arm64 -> arm64_f32x4_cmpge a b
;;

(* ---- select (bitwise blend, cross-platform) ---- *)

(* select mask ~fail ~pass = fail ^ (mask & (fail ^ pass)) When mask lane is all-1s: fail
   ^ (fail ^ pass) = pass When mask lane is all-0s: fail ^ 0 = fail *)
let[@inline] i32x4_select (mask : int32x4#) ~(fail : int32x4#) ~(pass : int32x4#)
  : int32x4#
  =
  i32x4_xor fail (i32x4_and mask (i32x4_xor fail pass))
;;

let[@inline] f32x4_select (mask : int32x4#) ~(fail : float32x4#) ~(pass : float32x4#)
  : float32x4#
  =
  float32x4_of_int32x4
    (i32x4_select
       mask
       ~fail:(int32x4_of_float32x4 fail)
       ~pass:(int32x4_of_float32x4 pass))
;;

(* ---- float32x4 min/max ----

   Every backend must agree bitwise with the scalar [Float32_u.min]/[max] (plus the scalar
   evaluators' sign-OR/AND tie-break for equal operands), which on arm64 is what NEON
   [fmin]/[fmax] compute in one instruction. SSE [minps]/[maxps] disagree in two cases: a
   NaN in the FIRST operand is dropped (the second operand wins whenever the comparison is
   unordered), and equal operands — including [-0. = +0.] — return the second operand
   instead of ordering the zeros. The amd64 path corrects both:

   min a b = if a = b then a |bits| b (orders the zeros: min(-0,+0) = -0) else if a is NaN
   then a (NaN propagates, preferring a's payload) else minps a b (covers a < b, b < a,
   and NaN-in-b)

   and symmetrically for max with a sign-AND on ties. *)

let[@inline] f32x4_min (a : float32x4#) (b : float32x4#) : float32x4# =
  match Sys.arch with
  | Arm64 -> f32x4_min_raw a b
  | Amd64 ->
    let ai = int32x4_of_float32x4 a in
    let bi = int32x4_of_float32x4 b in
    let eq = amd64_f32x4_cmp 0x0 a b (* CMPEQPS: false on NaN, true on -0 = +0 *) in
    let a_nan = amd64_f32x4_cmp 0x3 a a (* CMPUNORDPS: a is NaN *) in
    let m = int32x4_of_float32x4 (f32x4_min_raw a b) in
    let r = i32x4_select a_nan ~fail:m ~pass:ai in
    float32x4_of_int32x4 (i32x4_select eq ~fail:r ~pass:(i32x4_or ai bi))
;;

let[@inline] f32x4_max (a : float32x4#) (b : float32x4#) : float32x4# =
  match Sys.arch with
  | Arm64 -> f32x4_max_raw a b
  | Amd64 ->
    let ai = int32x4_of_float32x4 a in
    let bi = int32x4_of_float32x4 b in
    let eq = amd64_f32x4_cmp 0x0 a b in
    let a_nan = amd64_f32x4_cmp 0x3 a a in
    let m = int32x4_of_float32x4 (f32x4_max_raw a b) in
    let r = i32x4_select a_nan ~fail:m ~pass:ai in
    float32x4_of_int32x4 (i32x4_select eq ~fail:r ~pass:(i32x4_and ai bi))
;;

(* ---- float32x4 abs/neg ----

   Sign-bit operations on the integer view, matching the scalar backends' fneg/fabs
   exactly (so [neg +0. = -0.] and NaN payloads survive). *)

let[@inline] f32x4_neg (v : float32x4#) : float32x4# =
  float32x4_of_int32x4 (i32x4_xor (int32x4_of_float32x4 v) (i32x4_set1 #0x80000000l))
;;

let[@inline] f32x4_abs (v : float32x4#) : float32x4# =
  float32x4_of_int32x4 (i32x4_and (int32x4_of_float32x4 v) (i32x4_set1 #0x7fffffffl))
;;
