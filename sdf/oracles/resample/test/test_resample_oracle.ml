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
           ~trace:(Phase_trace.null ())
           ~oracles:empty_oracles
           ~sample_region:region
    in
    let prepared_box = Stdlib.Obj.magic_uncontended prepared_box in
    prepared_box := Some p);
  Option.value_exn !prepared_box
;;

(* ======================================================================= *)
(* Test A1: Smoke — sample_range containment *)
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
(* Test A2: Dense reference pipeline vs. oracle sample at 9x9 grid points *)
(* ======================================================================= *)

(* Replicate sdf_resample_oracle.ml's make logic to build a reference sampler. *)
let build_dense_reference tree region =
  let expand_by = 2 in
  let expanded = Sample_region.expand region ~by_:expand_by in
  let module E = Sdf.Expr_graph_batch_eval in
  let pb = E.Prepared.of_tree tree in
  let batch = E.Batch.create pb expanded in
  let result = E.Batch.run batch ~oracles:(Map.empty (module Oracle.Key)) in
  let ew = expanded.samples_x
  and eh = expanded.samples_y in
  let grid : float32# array = Array.create ~len:(ew * eh) #0.0s in
  for i = 0 to (ew * eh) - 1 do
    grid.(i) <- Value.to_float (E.Result.get_output result ~px:i)
  done;
  let march_out : float32# array = Array.create ~len:(ew * eh * 2 * 4) #0.0s in
  let length = March.run grid march_out ew eh in
  let ref_segs = Nearest_seg.build march_out ~length in
  let open Float32_u in
  let step_x = Sample_region.step_x region
  and step_y = Sample_region.step_y region in
  let inv_step_x = #1.s / step_x
  and inv_step_y = #1.s / step_y in
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
(* Test A3: 200 random points, oracle vs dense reference *)
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
(* Test A4: sample_range soundness — corners and centre inside range *)
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
  then
    Error.raise_s [%message "sample_range containment failures" ~count:(!failures : int)]
;;

(* ======================================================================= *)
(* A helper: sweep random boxes over a prepared oracle and check *)
(* containment at corners, centre, and random interior points. *)
(* ======================================================================= *)

(* [check_containment_sweep ~prepared ~region_size ~rng ~num_boxes ~max_box_size ~num_random_pts]
   sweeps [num_boxes] random boxes whose corners lie in [0, region_size] and whose side
   lengths are at most [max_box_size]. For each box it checks the 4 corners, the centre,
   and [num_random_pts] random interior points. Returns the total failure count. *)
let check_containment_sweep
  ~prepared
  ~region_size
  ~rng
  ~num_boxes
  ~max_box_size
  ~num_random_pts
  =
  let failures = ref 0 in
  for _ = 1 to num_boxes do
    let x0 = Float32_u.of_float (Random.State.float rng region_size) in
    let y0 = Float32_u.of_float (Random.State.float rng region_size) in
    let w = Float32_u.of_float (Random.State.float rng max_box_size) in
    let h = Float32_u.of_float (Random.State.float rng max_box_size) in
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
    (* 4 corners + centre *)
    check x0 y0;
    check x1 y0;
    check x0 y1;
    check x1 y1;
    check cx cy;
    (* random interior points *)
    for _ = 1 to num_random_pts do
      let tx = Random.State.float rng 1.0 in
      let ty = Random.State.float rng 1.0 in
      let px =
        Float32_u.((x0 * Float32_u.of_float (1.0 -. tx)) + (x1 * Float32_u.of_float tx))
      in
      let py =
        Float32_u.((y0 * Float32_u.of_float (1.0 -. ty)) + (y1 * Float32_u.of_float ty))
      in
      check px py
    done
  done;
  !failures
;;

(* ======================================================================= *)
(* Test A5: Boundary-crossing shapes — containment with open chain ends *)
(* ======================================================================= *)

(* Circle clipped at the LEFT edge: centre x=0, y=16, radius=12. Contour crosses x=0 so
   there are open chain ends at the left boundary. *)
let%test_unit "resample oracle: boundary-crossing circle (left edge) containment" =
  let tree = circle ~cx:#0.s ~cy:#16.s ~r:#12.s in
  let region = square_region ~size:32 in
  let scheduler = Parallel_scheduler.create () in
  let prepared = prepare_oracle tree region scheduler in
  let rng = Random.State.make [| 101 |] in
  let failures =
    check_containment_sweep
      ~prepared
      ~region_size:32.0
      ~rng
      ~num_boxes:200
      ~max_box_size:16.0
      ~num_random_pts:10
  in
  if failures > 0
  then
    Error.raise_s
      [%message
        "left-edge clipped circle: sample_range containment failures"
          ~count:(failures : int)]
;;

(* Circle clipped at the TOP edge: centre x=16, y=0, radius=10. Contour crosses y=0 so
   there are open chain ends at the top boundary. *)
let%test_unit "resample oracle: boundary-crossing circle (top edge) containment" =
  let tree = circle ~cx:#16.s ~cy:#0.s ~r:#10.s in
  let region = square_region ~size:32 in
  let scheduler = Parallel_scheduler.create () in
  let prepared = prepare_oracle tree region scheduler in
  let rng = Random.State.make [| 202 |] in
  let failures =
    check_containment_sweep
      ~prepared
      ~region_size:32.0
      ~rng
      ~num_boxes:200
      ~max_box_size:16.0
      ~num_random_pts:10
  in
  if failures > 0
  then
    Error.raise_s
      [%message
        "top-edge clipped circle: sample_range containment failures"
          ~count:(failures : int)]
;;

(* Circle crossing a CORNER: centre x=0, y=0, radius=14. Contour is clipped at both x=0
   and y=0 simultaneously. *)
let%test_unit "resample oracle: boundary-crossing circle (corner) containment" =
  let tree = circle ~cx:#0.s ~cy:#0.s ~r:#14.s in
  let region = square_region ~size:32 in
  let scheduler = Parallel_scheduler.create () in
  let prepared = prepare_oracle tree region scheduler in
  let rng = Random.State.make [| 303 |] in
  let failures =
    check_containment_sweep
      ~prepared
      ~region_size:32.0
      ~rng
      ~num_boxes:200
      ~max_box_size:16.0
      ~num_random_pts:10
  in
  if failures > 0
  then
    Error.raise_s
      [%message
        "corner-clipped circle: sample_range containment failures" ~count:(failures : int)]
;;

(* Also test each clipped circle with boxes that deliberately hug the boundary or span
   from far inside to the boundary, in a dedicated expect test so we can see the violation
   count directly. *)
let%expect_test "resample oracle: boundary-clipped circles — violation count" =
  let scheduler = Parallel_scheduler.create () in
  let region = square_region ~size:32 in
  let check_shape name tree =
    let prepared = prepare_oracle tree region scheduler in
    let rng = Random.State.make [| 999 |] in
    (* Targeted sweep: small boxes hugging x=0 / y=0 boundaries *)
    let failures = ref 0 in
    let check_box x0 y0 x1 y1 =
      let x_iv = Interval.create ~lo:x0 ~hi:x1 in
      let y_iv = Interval.create ~lo:y0 ~hi:y1 in
      let range = Oracle.Prepared.sample_range prepared ~x:x_iv ~y:y_iv in
      let check px py =
        let v = Oracle.Prepared.sample prepared ~x:px ~y:py in
        if not (Interval.contains range v) then incr failures
      in
      let cx = Float32_u.((x0 + x1) * #0.5s) in
      let cy = Float32_u.((y0 + y1) * #0.5s) in
      check x0 y0;
      check x1 y0;
      check x0 y1;
      check x1 y1;
      check cx cy;
      for _ = 1 to 10 do
        let tx = Random.State.float rng 1.0 in
        let ty = Random.State.float rng 1.0 in
        let px =
          Float32_u.((x0 * Float32_u.of_float (1.0 -. tx)) + (x1 * Float32_u.of_float tx))
        in
        let py =
          Float32_u.((y0 * Float32_u.of_float (1.0 -. ty)) + (y1 * Float32_u.of_float ty))
        in
        check px py
      done
    in
    (* Boxes straddling x=0 boundary: negative lo clamped to 0 in world coords but
       actually just small boxes starting at 0 *)
    for i = 0 to 15 do
      let y_lo = Float32_u.of_float (Float.of_int i *. 2.0) in
      let y_hi = Float32_u.(y_lo + #2.s) in
      check_box #0.s y_lo #2.s y_hi
    done;
    (* Boxes straddling y=0 boundary *)
    for i = 0 to 15 do
      let x_lo = Float32_u.of_float (Float.of_int i *. 2.0) in
      let x_hi = Float32_u.(x_lo + #2.s) in
      check_box x_lo #0.s x_hi #2.s
    done;
    (* Boxes far from contour but overlapping contour bounding box in one axis *)
    for i = 0 to 15 do
      let x_lo = Float32_u.of_float (Float.of_int i *. 2.0) in
      let x_hi = Float32_u.(x_lo + #2.s) in
      check_box x_lo #20.s x_hi #28.s
    done;
    printf "%s violations: %d\n" name !failures
  in
  check_shape "left-edge circle (cx=0,cy=16,r=12)" (circle ~cx:#0.s ~cy:#16.s ~r:#12.s);
  check_shape "top-edge circle (cx=16,cy=0,r=10)" (circle ~cx:#16.s ~cy:#0.s ~r:#10.s);
  check_shape "corner circle (cx=0,cy=0,r=14)" (circle ~cx:#0.s ~cy:#0.s ~r:#14.s);
  [%expect
    {|
    left-edge circle (cx=0,cy=16,r=12) violations: 0
    top-edge circle (cx=16,cy=0,r=10) violations: 0
    corner circle (cx=0,cy=0,r=14) violations: 0
    |}]
;;

(* ======================================================================= *)
(* Test A6: Probe is active — interior box far from contour reports lo > 0 *)
(* ======================================================================= *)

(* For the INTERIOR circle (cx=16, cy=16, r=8), the box x∈[14,18], y∈[28,31] is far above
   the circle (min distance to contour ≈ 28-24 = 4 world units). Without the midpoint
   probe the interval would straddle zero because the contour's horizontal extent [8,24]
   overlaps [14,18]. With the probe, lo > 0 (every point in the box is outside). *)
let%expect_test "resample oracle: sample_range interval lo > 0 far above interior circle" =
  let tree = circle ~cx:#16.s ~cy:#16.s ~r:#8.s in
  let region = square_region ~size:32 in
  let scheduler = Parallel_scheduler.create () in
  let prepared = prepare_oracle tree region scheduler in
  let x_iv = Interval.create ~lo:#14.s ~hi:#18.s in
  let y_iv = Interval.create ~lo:#28.s ~hi:#31.s in
  let range = Oracle.Prepared.sample_range prepared ~x:x_iv ~y:y_iv in
  let #{ Interval.lo; hi } = range in
  let lo = Float32_u.to_float lo in
  let hi = Float32_u.to_float hi in
  printf "sample_range for x=[14,18] y=[28,31]: [%.4f, %.4f]\n" lo hi;
  printf "lo > 0 (probe resolved sign): %b\n" (Float.( > ) lo 0.0);
  [%expect
    {|
    sample_range for x=[14,18] y=[28,31]: [3.9988, 7.2813]
    lo > 0 (probe resolved sign): true
    |}]
;;
