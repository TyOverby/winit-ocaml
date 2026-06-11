open! Core
open Sdf

(* ---- Expr_tree helpers (same pattern as sdf/contour/test/test_contour.ml) ---- *)

let here = Stdlib.Lexing.dummy_pos
let ok = Or_error.ok_exn
let f x = ok (Expr_tree.float_literal ~loc:here x)
let coord_x = ok (Expr_tree.coord_x ~loc:here)
let coord_y = ok (Expr_tree.coord_y ~loc:here)
let add a b = ok (Expr_tree.add ~loc:here a b)
let sub a b = ok (Expr_tree.sub ~loc:here a b)
let mul a b = ok (Expr_tree.mul ~loc:here a b)
let sqrt a = ok (Expr_tree.sqrt ~loc:here a)

let circle ~cx ~cy ~r =
  let dx = sub coord_x (f cx) in
  let dy = sub coord_y (f cy) in
  sub (sqrt (add (mul dx dx) (mul dy dy))) (f r)
;;

let square_region ~size =
  { Sample_region.start_x = #0.s
  ; end_x = Float32_u.of_int size
  ; samples_x = size
  ; start_y = #0.s
  ; end_y = Float32_u.of_int size
  ; samples_y = size
  }
;;

(* Prepare the oracle inside a parallel scheduler. Returns the prepared oracle. *)
let prepare_oracle tree region scheduler =
  let prepared_box : Oracle.Prepared.t option ref = ref None in
  Parallel_scheduler.parallel scheduler ~f:(fun par ->
    let empty_oracles = Map.empty (module Oracle.Key) in
    let p =
      Sdf_resample_oracle.create [ tree ]
      |> Sdf_resample_oracle.prepare
           ~par
           ~exec:(Obj.magic Obj.magic (module Sdf.Expr_graph_batch_eval : Sdf.Executor.S))
           ~oracles:empty_oracles
           ~sample_region:region
    in
    let prepared_box = Stdlib.Obj.magic_uncontended prepared_box in
    prepared_box := Some p);
  Option.value_exn !prepared_box
;;

(* ======================================================================= *)
(* Test A1: Smoke — sample_range containment                               *)
(* ======================================================================= *)

let%expect_test "resample oracle: sample_range contains sample value" =
  let tree = circle ~cx:#16.s ~cy:#16.s ~r:#8.s in
  let region = square_region ~size:32 in
  let scheduler = Parallel_scheduler.create () in
  let prepared = prepare_oracle tree region scheduler in
  (* 5x5 grid of 6x6 boxes; check corners and centre are inside sample_range. *)
  let all_contained = ref true in
  let num_points = ref 0 in
  for row = 0 to 4 do
    for col = 0 to 4 do
      let x_lo = Float32_u.of_float (Float.of_int col *. 6.0) in
      let y_lo = Float32_u.of_float (Float.of_int row *. 6.0) in
      let x_hi = Float32_u.(x_lo + #6.s) in
      let y_hi = Float32_u.(y_lo + #6.s) in
      let x_iv = Interval.create ~lo:x_lo ~hi:x_hi in
      let y_iv = Interval.create ~lo:y_lo ~hi:y_hi in
      let range = Oracle.Prepared.sample_range prepared ~x:x_iv ~y:y_iv in
      let cx = Float32_u.((x_lo + x_hi) * #0.5s) in
      let cy = Float32_u.((y_lo + y_hi) * #0.5s) in
      let check px py =
        incr num_points;
        let v = Oracle.Prepared.sample prepared ~x:px ~y:py in
        if not (Interval.contains range v) then all_contained := false
      in
      check x_lo y_lo;
      check x_hi y_lo;
      check x_lo y_hi;
      check x_hi y_hi;
      check cx cy
    done
  done;
  printf "points tested: %d\n" !num_points;
  printf "all contained: %b\n" !all_contained;
  [%expect {|
    points tested: 125
    all contained: true
    |}]
;;

(* ======================================================================= *)
(* Test A2: Dense reference pipeline vs. oracle sample at 9x9 grid points  *)
(* ======================================================================= *)

(* Replicate sdf_resample_oracle.ml's make logic to build a reference sampler. *)
let build_dense_reference tree region =
  let expand_by = 2 in
  let expanded = Sample_region.expand region ~by_:expand_by in
  let module E = Sdf.Expr_graph_batch_eval in
  let pb = E.Batch.Prepared.of_tree tree in
  let batch = E.Batch.Batch.create pb expanded in
  let result = E.Batch.Batch.run batch ~oracles:(Map.empty (module Oracle.Key)) in
  let ew = expanded.samples_x and eh = expanded.samples_y in
  let grid : float32# array = Array.create ~len:(ew * eh) #0.0s in
  for i = 0 to (ew * eh) - 1 do
    grid.(i) <- Value.to_float (E.Batch.Result.get_output result ~px:i)
  done;
  let march_out : float32# array = Array.create ~len:(ew * eh * 2 * 4) #0.0s in
  let length = March.run grid march_out ew eh in
  let ref_segs = Nearest_seg.build march_out ~length in
  let open Float32_u in
  let step_x = Sample_region.step_x region and step_y = Sample_region.step_y region in
  let inv_step_x = #1.s / step_x and inv_step_y = #1.s / step_y in
  let offset_x = of_int expand_by - (region.Sample_region.start_x / step_x) in
  let offset_y = of_int expand_by - (region.Sample_region.start_y / step_y) in
  let dist_scale = step_x in
  fun ~x ~y ->
    let gx = (x * inv_step_x) + offset_x in
    let gy = (y * inv_step_y) + offset_y in
    Nearest_seg.query ref_segs ~x:gx ~y:gy * dist_scale
;;

let%expect_test "resample oracle: oracle sample matches dense reference (9x9 grid)" =
  let tree = circle ~cx:#16.s ~cy:#16.s ~r:#8.s in
  let region = square_region ~size:32 in
  let ref_sample = build_dense_reference tree region in
  let scheduler = Parallel_scheduler.create () in
  let prepared = prepare_oracle tree region scheduler in
  let mismatches = ref 0 in
  for row = 0 to 8 do
    for col = 0 to 8 do
      let x = Float32_u.of_float (Float.of_int col *. 4.0) in
      let y = Float32_u.of_float (Float.of_int row *. 4.0) in
      let oracle_v = Oracle.Prepared.sample prepared ~x ~y in
      let ref_v = ref_sample ~x ~y in
      let ob = Float32_u.to_bits oracle_v in
      let rb = Float32_u.to_bits ref_v in
      if not (Int32_u.equal ob rb) then incr mismatches
    done
  done;
  printf "grid points tested: %d\n" (9 * 9);
  printf "mismatches: %d\n" !mismatches;
  [%expect {|
    grid points tested: 81
    mismatches: 0
    |}]
;;

(* ======================================================================= *)
(* Test A3: 200 random points, oracle vs dense reference                   *)
(* ======================================================================= *)

let%test_unit "resample oracle: bitwise equality vs dense ref (200 pts)" =
  let tree = circle ~cx:#16.s ~cy:#16.s ~r:#8.s in
  let region = square_region ~size:32 in
  let ref_sample = build_dense_reference tree region in
  let scheduler = Parallel_scheduler.create () in
  let prepared = prepare_oracle tree region scheduler in
  let rng = Random.State.make [| 42 |] in
  let mismatches = ref 0 in
  for _ = 1 to 200 do
    let x = Float32_u.of_float (Random.State.float rng 32.0) in
    let y = Float32_u.of_float (Random.State.float rng 32.0) in
    let oracle_v = Oracle.Prepared.sample prepared ~x ~y in
    let ref_v = ref_sample ~x ~y in
    if not (Int32_u.equal (Float32_u.to_bits oracle_v) (Float32_u.to_bits ref_v))
    then incr mismatches
  done;
  if !mismatches > 0
  then Error.raise_s [%message "bitwise mismatch" ~mismatches:(!mismatches : int)]
;;

(* ======================================================================= *)
(* Test A4: sample_range soundness — corners and centre inside range       *)
(* ======================================================================= *)

let%test_unit "resample oracle: sample_range sound for 100 random boxes" =
  let tree = circle ~cx:#16.s ~cy:#16.s ~r:#8.s in
  let region = square_region ~size:32 in
  let scheduler = Parallel_scheduler.create () in
  let prepared = prepare_oracle tree region scheduler in
  let rng = Random.State.make [| 7 |] in
  let failures = ref 0 in
  for _ = 1 to 100 do
    let x0 = Float32_u.of_float (Random.State.float rng 28.0) in
    let y0 = Float32_u.of_float (Random.State.float rng 28.0) in
    let w = Float32_u.of_float (1.0 +. Random.State.float rng 4.0) in
    let h = Float32_u.of_float (1.0 +. Random.State.float rng 4.0) in
    let x1 = Float32_u.(x0 + w) in
    let y1 = Float32_u.(y0 + h) in
    let x_iv = Interval.create ~lo:x0 ~hi:x1 in
    let y_iv = Interval.create ~lo:y0 ~hi:y1 in
    let range = Oracle.Prepared.sample_range prepared ~x:x_iv ~y:y_iv in
    let cx = Float32_u.((x0 + x1) * #0.5s) in
    let cy = Float32_u.((y0 + y1) * #0.5s) in
    let check px py =
      let v = Oracle.Prepared.sample prepared ~x:px ~y:py in
      if not (Interval.contains range v) then incr failures
    in
    check x0 y0;
    check x1 y0;
    check x0 y1;
    check x1 y1;
    check cx cy
  done;
  if !failures > 0
  then Error.raise_s [%message "sample_range containment failures" ~count:(!failures : int)]
;;
