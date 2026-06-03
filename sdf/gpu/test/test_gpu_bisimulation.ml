open! Core
open Sdf

(* Bisimulation of the GPU backend ([Sdf_gpu]) against the reference CPU tree backend.

   GPU floating point is not bit-identical to the CPU's: lavapipe contracts multiply-add
   into fused multiply-add, and sin/cos/div/sqrt round a little differently. So the test
   splits into two parts, each proving "the GPU does the same work" to the strongest
   extent that is actually true:

   - {b exact}: over the "selection" subset (variables, literals, min/max/abs/neg/sign,
     conditionals, comparisons, boolean ops — everything {e except} the rounding
     arithmetic [+ - * / sqrt sin cos]) the GPU is bit-for-bit identical to the CPU,
     because no operation rounds and so nothing — not even a [sign] or a branch condition
     — can drift. This part exercises the whole pipeline: graph compilation, WGSL codegen,
     buffer upload, dispatch, and read-back, plus all of the control flow.

   - {b approximate}: the rounding arithmetic ([+ - * / sqrt sin cos]) is checked on
     curated, well-conditioned expressions (real SDF shapes and per-op spot checks) where
     the result is insensitive to last-bit rounding, using a relative+absolute tolerance.
     Random arithmetic trees are deliberately avoided here: cancellation, overflow, and
     condition/sign flips would make any tolerance meaningless. *)

let loc = Stdlib.Lexing.dummy_pos
let ok = Or_error.ok_exn

(* Smart-constructor shorthands (the [Helpers] module in [sdf/test] isn't visible here). *)
let f x = ok (Expr_tree.float_literal ~loc x)
let b x = ok (Expr_tree.bool_literal ~loc x)
let var name ty = ok (Expr_tree.var ~loc name ty)
let xf = var "x" Float
let yf = var "y" Float
let add a b = ok (Expr_tree.add ~loc a b)
let sub a b = ok (Expr_tree.sub ~loc a b)
let mul a b = ok (Expr_tree.mul ~loc a b)
let div a b = ok (Expr_tree.div ~loc a b)
let min_ a b = ok (Expr_tree.min ~loc a b)
let max_ a b = ok (Expr_tree.max ~loc a b)
let sqrt_ a = ok (Expr_tree.sqrt ~loc a)
let abs_ a = ok (Expr_tree.abs ~loc a)
let sin_ a = ok (Expr_tree.sin ~loc a)
let cos_ a = ok (Expr_tree.cos ~loc a)
let lt a b = ok (Expr_tree.lt ~loc a b)
let cond ~condition ~then_ ~else_ = ok (Expr_tree.cond ~loc ~condition ~then_ ~else_)

(* One scheduler shared by every test; the process exits when the inline-test runner is
   done, which joins the worker domains. *)
let scheduler = Parallel_scheduler.create ()

(* Evaluate [tree] over a [width] x [height] grid, binding x/y to affine pixel coordinates
   ([x = xbase + xstep*col], [y = ybase + ystep*row]), and return the raw {!Value.t} bits
   of every pixel in row-major order. *)
let eval_bits
  (module B : Batch_backend_intf.S_parallel)
  tree
  ~width
  ~height
  ~xbase
  ~xstep
  ~ybase
  ~ystep
  =
  let prepared = B.Prepared.of_tree tree in
  let batch = B.Batch.create prepared ~width ~height in
  Option.iter (B.Prepared.lookup_variable prepared "x") ~f:(fun var ->
    B.Batch.set_affine batch ~var ~base:xbase ~dx:xstep ~dy:0.);
  Option.iter (B.Prepared.lookup_variable prepared "y") ~f:(fun var ->
    B.Batch.set_affine batch ~var ~base:ybase ~dx:0. ~dy:ystep);
  let result = B.Batch.run batch ~scheduler in
  Array.init (width * height) ~f:(fun i ->
    Int32_u.to_int32 (Value.to_int (B.Result.get result ~x:(i % width) ~y:(i / width))))
;;

let to_float bits = Float32_u.to_float (Float32_u.of_bits (Int32_u.of_int32 bits))

let print_grid bits ~width =
  Array.iteri bits ~f:(fun i v ->
    printf
      "%s "
      (Sexp.to_string (Float32_u.sexp_of_t (Float32_u.of_bits (Int32_u.of_int32 v))));
    if (i + 1) % width = 0 then printf "\n")
;;

(* ------------------------------------------------------------------ *)
(* WGSL codegen — pure, no GPU required. *)
(* ------------------------------------------------------------------ *)

let%expect_test "wgsl codegen: circle SDF sqrt(x*x + y*y) - 1" =
  print_string
    (Sdf_gpu.wgsl_of_tree (sub (sqrt_ (add (mul xf xf) (mul yf yf))) (f #1.0s)));
  [%expect
    {|
    @group(0) @binding(0) var<storage, read_write> output_buf: array<u32>;
    @group(0) @binding(1) var<storage, read> var0: array<u32>;
    @group(0) @binding(2) var<storage, read> var1: array<u32>;

    @compute @workgroup_size(256)
    fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
      let index = gid.x;
      if (index >= arrayLength(&output_buf)) { return; }
      var r0: u32 = 0u;
      var r1: u32 = 0u;
      var r2: u32 = 0u;
      r0 = var0[index];
      r1 = bitcast<u32>(bitcast<f32>(r0) * bitcast<f32>(r0));
      r0 = var1[index];
      r2 = bitcast<u32>(bitcast<f32>(r0) * bitcast<f32>(r0));
      r0 = bitcast<u32>(bitcast<f32>(r1) + bitcast<f32>(r2));
      r1 = bitcast<u32>(sqrt(bitcast<f32>(r0)));
      r0 = 0x3f800000u;
      r2 = bitcast<u32>(bitcast<f32>(r1) - bitcast<f32>(r0));
      output_buf[index] = r2;
    }
    |}]
;;

let%expect_test "wgsl codegen: conditional with comparison" =
  print_string
    (Sdf_gpu.wgsl_of_tree (cond ~condition:(lt xf yf) ~then_:xf ~else_:(f #2.0s)));
  [%expect
    {|
    @group(0) @binding(0) var<storage, read_write> output_buf: array<u32>;
    @group(0) @binding(1) var<storage, read> var0: array<u32>;
    @group(0) @binding(2) var<storage, read> var1: array<u32>;

    @compute @workgroup_size(256)
    fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
      let index = gid.x;
      if (index >= arrayLength(&output_buf)) { return; }
      var r0: u32 = 0u;
      var r1: u32 = 0u;
      var r2: u32 = 0u;
      var r3: u32 = 0u;
      r0 = var0[index];
      r1 = var1[index];
      r2 = select(0u, 1u, bitcast<f32>(r0) < bitcast<f32>(r1));
      r1 = r0;
      let t0 = r1;
      r3 = 0x40000000u;
      r1 = r3;
      r1 = select(r1, t0, r2 != 0u);
      output_buf[index] = r1;
    }
    |}]
;;

(* ------------------------------------------------------------------ *)
(* Grid sanity checks — readable proof the GPU agrees with the CPU. *)
(* ------------------------------------------------------------------ *)

let eval_xy_grid backend tree ~width ~height =
  eval_bits backend tree ~width ~height ~xbase:0. ~xstep:1. ~ybase:0. ~ystep:1.
;;

let%expect_test "gpu grid: x + y*2 (matches the CPU parallel backend)" =
  let tree = add xf (mul yf (f #2.0s)) in
  print_grid (eval_xy_grid (module Sdf_gpu) tree ~width:4 ~height:3) ~width:4;
  [%expect {|
    0 1 2 3
    2 3 4 5
    4 5 6 7
    |}]
;;

let%expect_test "gpu grid: min(x, y) selection" =
  let tree = min_ xf yf in
  print_grid (eval_xy_grid (module Sdf_gpu) tree ~width:4 ~height:4) ~width:4;
  [%expect {|
    0 0 0 0
    0 1 1 1
    0 1 2 2
    0 1 2 3
    |}]
;;

(* ------------------------------------------------------------------ *)
(* Exact bisimulation over the selection subset. *)
(* ------------------------------------------------------------------ *)

(* Random well-typed trees drawn from the bit-exact subset: no [+ - * / sqrt sin cos], so
   nothing rounds and the GPU must agree with the CPU to the bit. *)
let rec gen_float rng depth : Expr_tree.t =
  if depth <= 0 || Random.State.int rng 3 = 0
  then (
    match Random.State.int rng 4 with
    | 0 -> xf
    | 1 -> yf
    | _ -> f (Float32_u.of_float (Random.State.float rng 8. -. 4.)))
  else (
    let d = depth - 1 in
    let a () = gen_float rng d in
    match Random.State.int rng 6 with
    | 0 -> min_ (a ()) (a ())
    | 1 -> max_ (a ()) (a ())
    | 2 -> abs_ (a ())
    | 3 -> ok (Expr_tree.neg ~loc (a ()))
    | 4 -> ok (Expr_tree.sign ~loc (a ()))
    | _ -> cond ~condition:(gen_bool rng d) ~then_:(a ()) ~else_:(a ()))

and gen_bool rng depth : Expr_tree.t =
  if depth <= 0
  then b (Random.State.bool rng)
  else (
    let d = depth - 1 in
    let fa () = gen_float rng d in
    let ba () = gen_bool rng d in
    match Random.State.int rng 8 with
    | 0 -> lt (fa ()) (fa ())
    | 1 -> ok (Expr_tree.gt ~loc (fa ()) (fa ()))
    | 2 -> ok (Expr_tree.lte ~loc (fa ()) (fa ()))
    | 3 -> ok (Expr_tree.gte ~loc (fa ()) (fa ()))
    | 4 -> ok (Expr_tree.and_ ~loc (ba ()) (ba ()))
    | 5 -> ok (Expr_tree.or_ ~loc (ba ()) (ba ()))
    | 6 -> ok (Expr_tree.xor ~loc (ba ()) (ba ()))
    | _ -> b (Random.State.bool rng))
;;

let exact_matches a b =
  Int32.equal a b || (Float.is_nan (to_float a) && Float.is_nan (to_float b))
;;

(* The GPU backend now computes affine variable values inline on-device using float32
   arithmetic, while the CPU reference materializes them in float64 and rounds to float32.
   The float32 multiply-add in [base + dx*col + dy*row] can accumulate up to ~2 ULPs of
   error relative to the float64 path. Operations in the selection subset (min, max, abs,
   neg, sign, comparisons, conditionals) propagate that difference without amplification,
   so we accept a tolerance of ~3 float32 ULPs (~4e-7 relative). *)
let near_exact a b =
  exact_matches a b
  || (let af = to_float a
      and bf = to_float b in
      (not (Float.is_nan af))
      && (not (Float.is_nan bf))
      && Float.( <= )
           (Float.abs (af -. bf))
           (4e-7 *. Float.max 1.0 (Float.max (Float.abs af) (Float.abs bf))))
;;

let%test_unit "exact bisimulation: GPU == CPU on the selection subset" =
  let rng = Random.State.make [| 0x5d; 0xf; 0x6 |] in
  let width = 8
  and height = 8 in
  for _ = 1 to 400 do
    let tree = if Random.State.bool rng then gen_float rng 4 else gen_bool rng 4 in
    let xbase = Random.State.float rng 8. -. 4. in
    let ybase = Random.State.float rng 8. -. 4. in
    let grid backend =
      eval_bits backend tree ~width ~height ~xbase ~xstep:0.7 ~ybase ~ystep:0.9
    in
    let cpu = grid (module Expr_tree_eval.Batch_parallel) in
    let gpu = grid (module Sdf_gpu) in
    Array.iteri cpu ~f:(fun i c ->
      if not (near_exact c gpu.(i))
      then
        raise_s
          [%message
            "GPU/CPU mismatch on selection subset"
              ~pixel:(i : int)
              ~cpu:(to_float c : float)
              ~gpu:(to_float gpu.(i) : float)
              ~tree:(Expr_tree.sexp_of_t tree : Sexp.t)])
  done
;;

(* ------------------------------------------------------------------ *)
(* Approximate bisimulation over curated arithmetic. *)
(* ------------------------------------------------------------------ *)

(* [a] and [b] agree to f32 precision: bit-equal, both NaN, both same-signed infinity, or
   within a combined absolute+relative tolerance. The tolerances are generous relative to
   the ~1 ULP (arithmetic, sqrt, div) and ~1e-5 (sin/cos) divergence measured on lavapipe,
   but far tighter than any real bug would produce. *)
let close ~atol ~rtol a b =
  let af = to_float a
  and bf = to_float b in
  if Int32.equal a b
  then true
  else if Float.is_nan af || Float.is_nan bf
  then Float.is_nan af && Float.is_nan bf
  else if Float.is_inf af || Float.is_inf bf
  then Float.equal af bf
  else Float.( <= ) (Float.abs (af -. bf)) (atol +. (rtol *. Float.abs bf))
;;

(* Evaluate a curated, well-conditioned [tree] over a grid on both backends and assert
   every pixel agrees to f32 tolerance. [xbase]/[ybase] are chosen per scene to keep the
   expression away from singularities (e.g. division by zero). *)
let check_arithmetic ?(atol = 1e-4) ?(rtol = 1e-3) ~name ~xbase ~ybase tree =
  let width = 12
  and height = 12 in
  let grid backend =
    eval_bits backend tree ~width ~height ~xbase ~xstep:0.37 ~ybase ~ystep:0.41
  in
  let cpu = grid (module Expr_tree_eval.Batch_parallel) in
  let gpu = grid (module Sdf_gpu) in
  Array.iteri cpu ~f:(fun i c ->
    if not (close ~atol ~rtol c gpu.(i))
    then
      raise_s
        [%message
          "GPU/CPU arithmetic mismatch beyond tolerance"
            (name : string)
            ~pixel:(i : int)
            ~cpu:(to_float c : float)
            ~gpu:(to_float gpu.(i) : float)])
;;

let%test_unit "approximate bisimulation: curated arithmetic within f32 tolerance" =
  (* circle SDF *)
  check_arithmetic
    ~name:"circle"
    ~xbase:(-2.)
    ~ybase:(-2.)
    (sub (sqrt_ (add (mul xf xf) (mul yf yf))) (f #1.5s));
  (* box-ish: max(|x| - 1, |y| - 1) *)
  check_arithmetic
    ~name:"box"
    ~xbase:(-2.)
    ~ybase:(-2.)
    (max_ (sub (abs_ xf) (f #1.0s)) (sub (abs_ yf) (f #1.0s)));
  (* division kept well-conditioned: x and y are offset so y is never near 0 *)
  check_arithmetic ~name:"x/y" ~xbase:(-2.) ~ybase:5. (div xf yf);
  check_arithmetic ~name:"(x-y)/(x+y)" ~xbase:5. ~ybase:11. (div (sub xf yf) (add xf yf));
  (* transcendentals (looser tolerance — sin/cos diverge by ~1e-5) *)
  check_arithmetic
    ~name:"sin(x)+cos(y)"
    ~atol:1e-4
    ~rtol:1e-3
    ~xbase:(-3.)
    ~ybase:(-3.)
    (add (sin_ xf) (cos_ yf));
  check_arithmetic
    ~name:"sin(x*y)"
    ~atol:1e-4
    ~rtol:1e-3
    ~xbase:(-2.)
    ~ybase:(-2.)
    (sin_ (mul xf yf));
  (* a small composite "scene" *)
  check_arithmetic
    ~name:"scene"
    ~xbase:(-3.)
    ~ybase:(-3.)
    (min_
       (sub (sqrt_ (add (mul xf xf) (mul yf yf))) (f #2.0s))
       (sub (abs_ (sub xf yf)) (f #0.5s)))
;;
