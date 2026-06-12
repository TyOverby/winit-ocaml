open! Core
open Sdf

(* ---- Expr_tree helpers ---- *)

let here = Stdlib.Lexing.dummy_pos
let ok = Or_error.ok_exn
let f x = ok (Expr_tree.float_literal ~loc:here x)
let coord_x = ok (Expr_tree.coord_x ~loc:here)
let coord_y = ok (Expr_tree.coord_y ~loc:here)
let add a b = ok (Expr_tree.add ~loc:here a b)
let sub a b = ok (Expr_tree.sub ~loc:here a b)
let mul a b = ok (Expr_tree.mul ~loc:here a b)
let sqrt a = ok (Expr_tree.sqrt ~loc:here a)

let circle_tree ~cx ~cy ~r =
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

(* A circle of radius 20 centred at (32,32), rendered over a 64x64 grid. *)
let circle_source =
  {|
let x : float = var("x");
let y : float = var("y");
let dx = x - 32.0;
let dy = y - 32.0;
export sqrt(dx * dx + dy * dy) - 20.0;
|}
;;

let circle_region = square_region ~size:64

(* Sorted segment list helper — bitwise comparison. *)
let segment_list (segments : float32# array) ~length =
  List.init length ~f:(fun i ->
    ( Int32_u.to_int32 (Float32_u.to_bits segments.(i * 4))
    , Int32_u.to_int32 (Float32_u.to_bits segments.((i * 4) + 1))
    , Int32_u.to_int32 (Float32_u.to_bits segments.((i * 4) + 2))
    , Int32_u.to_int32 (Float32_u.to_bits segments.((i * 4) + 3)) ))
  |> List.sort ~compare:[%compare: Int32.t * Int32.t * Int32.t * Int32.t]
;;

(* Dense reference: sample the whole grid via the batch evaluator. *)
let dense_grid tree region =
  let module E = Sdf.Expr_graph_batch_eval in
  let prepared = E.Prepared.of_tree tree in
  let batch = E.Batch.create prepared region in
  let result = E.Batch.run batch ~oracles:(Map.empty (module Oracle.Key)) in
  let w = region.Sample_region.samples_x
  and h = region.Sample_region.samples_y in
  let grid : float32# array = Array.create ~len:(w * h) #0.0s in
  for i = 0 to (w * h) - 1 do
    grid.(i) <- Value.to_float (E.Result.get_output result ~px:i)
  done;
  grid
;;

(* Dense reference for scenes the helpers above can't evaluate directly (e.g. ones with
   oracles): a tiled run that culls nothing, so every sample is evaluated. *)
let dense_grid_via_runner runner ~region ~filename source =
  let w = region.Sample_region.samples_x
  and h = region.Sample_region.samples_y in
  let grid : float32# array = Array.create ~len:(w * h) #0.0s in
  let result =
    Sdf_runner.run_tiled runner ~region ~filename source ~cull:Tile_scheduler.Cull.Nothing
  in
  Tiled_eval.Result.iter
    result
    ~fill:(fun ~x0:_ ~y0:_ ~samples_x:_ ~samples_y:_ _ ->
      (* [Cull.Nothing] never culls a tile. *)
      assert false)
    ~draw:(fun ~x0 ~y0 ~samples_x ~samples_y ~get ->
      for dy = 0 to samples_y - 1 do
        for dx = 0 to samples_x - 1 do
          grid.(((y0 + dy) * w) + (x0 + dx))
          <- Value.to_float (get ((dy * samples_x) + dx))
        done
      done);
  grid
;;

(* Dense reference: sample the whole grid via the batch evaluator, then march it. *)
let dense_contour tree region =
  let w = region.Sample_region.samples_x
  and h = region.Sample_region.samples_y in
  let grid = dense_grid tree region in
  let out : float32# array = Array.create ~len:(w * h * 2 * 4) #0.0s in
  let length = March.run grid out w h in
  out, length
;;

(* ======================================================================= *)
(* B1: run_contour equals dense march *)
(* ======================================================================= *)

let%expect_test "run_contour equals dense march (circle)" =
  let tree = circle_tree ~cx:#32.s ~cy:#32.s ~r:#20.s in
  let region = circle_region in
  let dense_out, dense_len = dense_contour tree region in
  let dense = segment_list dense_out ~length:dense_len in
  let runner = Sdf_runner.create () in
  let ~segments, ~length, ~stats =
    Sdf_runner.run_contour runner ~region ~filename:"test.neo" circle_source
  in
  let tiled = segment_list segments ~length in
  printf "dense segments: %d\n" dense_len;
  printf "run_contour segments: %d\n" length;
  printf
    "bitwise equal: %b\n"
    ([%compare.equal: (Int32.t * Int32.t * Int32.t * Int32.t) list] dense tiled);
  print_s [%sexp (stats : Sdf_contour.Stats.t)];
  [%expect
    {|
    dense segments: 148
    run_contour segments: 148
    bitwise equal: true
    ((tiles_total 4) (tiles_culled 0) (samples_evaluated 4225))
    |}]
;;

(* ======================================================================= *)
(* B2: run_tiled equivalence + coverage *)
(* ======================================================================= *)

let%expect_test "run_tiled: active tiles bitwise equal, culled tiles interval-sound" =
  let region = circle_region in
  let runner = Sdf_runner.create () in
  (* Dense reference grid from the batch evaluator (the tree mirrors [circle_source]) *)
  let w = region.Sample_region.samples_x
  and h = region.Sample_region.samples_y in
  let dense_grid = dense_grid (circle_tree ~cx:#32.s ~cy:#32.s ~r:#20.s) region in
  (* Tiled eval *)
  let tiled =
    Sdf_runner.run_tiled
      runner
      ~region
      ~filename:"test.neo"
      circle_source
      ~cull:Tile_scheduler.Cull.No_contour
  in
  let tiled_grid : float32# array = Array.create ~len:(w * h) #0.0s in
  let coverage = Stdlib.Array.make (w * h) 0 in
  let all_active_match = ref true in
  let all_culled_sound = ref true in
  Tiled_eval.Result.iter
    tiled
    ~fill:(fun ~x0 ~y0 ~samples_x ~samples_y interval ->
      for dy = 0 to samples_y - 1 do
        for dx = 0 to samples_x - 1 do
          let px = x0 + dx
          and py = y0 + dy in
          let idx = (py * w) + px in
          coverage.(idx) <- coverage.(idx) + 1;
          let dv = dense_grid.(idx) in
          tiled_grid.(idx) <- dv;
          if not (Interval.contains interval dv) then all_culled_sound := false
        done
      done)
    ~draw:(fun ~x0 ~y0 ~samples_x ~samples_y ~get ->
      for dy = 0 to samples_y - 1 do
        for dx = 0 to samples_x - 1 do
          let px = x0 + dx
          and py = y0 + dy in
          let idx = (py * w) + px in
          coverage.(idx) <- coverage.(idx) + 1;
          let tv = Value.to_float (get ((dy * samples_x) + dx)) in
          tiled_grid.(idx) <- tv;
          let dv = dense_grid.(idx) in
          if not (Int32_u.equal (Float32_u.to_bits tv) (Float32_u.to_bits dv))
          then all_active_match := false
        done
      done);
  (* Every pixel must be covered at least once *)
  let all_covered = Stdlib.Array.for_all (fun c -> c >= 1) coverage in
  printf "active tiles bitwise equal: %b\n" !all_active_match;
  printf "culled tiles interval sound: %b\n" !all_culled_sound;
  printf "all pixels covered: %b\n" all_covered;
  [%expect
    {|
    active tiles bitwise equal: true
    culled tiles interval sound: true
    all pixels covered: true
    |}]
;;

(* ======================================================================= *)
(* B3: Caching *)
(* ======================================================================= *)

let%expect_test "caching: same args -> phys_equal, different cull -> not phys_equal" =
  let region = circle_region in
  let runner = Sdf_runner.create () in
  (* First run_tiled call *)
  let r1 =
    Sdf_runner.run_tiled
      runner
      ~region
      ~filename:"test.neo"
      circle_source
      ~cull:Tile_scheduler.Cull.No_contour
  in
  (* Second call: identical args -> should be phys_equal *)
  let r2 =
    Sdf_runner.run_tiled
      runner
      ~region
      ~filename:"test.neo"
      circle_source
      ~cull:Tile_scheduler.Cull.No_contour
  in
  printf "same args phys_equal: %b\n" (phys_equal r1 r2);
  (* Different cull -> new result *)
  let r3 =
    Sdf_runner.run_tiled
      runner
      ~region
      ~filename:"test.neo"
      circle_source
      ~cull:(Tile_scheduler.Cull.Constant_outside { below = 0.; above = 1. })
  in
  printf "different cull not phys_equal: %b\n" (not (phys_equal r1 r3));
  [%expect
    {|
    same args phys_equal: true
    different cull not phys_equal: true
    |}]
;;

let%expect_test "caching: run_contour caches across calls, invalidated on source change" =
  let region = circle_region in
  let runner = Sdf_runner.create () in
  let ~segments, ~length:_, ~stats:_ =
    Sdf_runner.run_contour runner ~region ~filename:"test.neo" circle_source
  in
  let ~segments:segments2, ~length:_, ~stats:_ =
    Sdf_runner.run_contour runner ~region ~filename:"test.neo" circle_source
  in
  printf "same source: cached phys_equal segments: %b\n" (phys_equal segments segments2);
  (* Change source: different radius *)
  let different_source =
    {|
let x : float = var("x");
let y : float = var("y");
let dx = x - 32.0;
let dy = y - 32.0;
export sqrt(dx * dx + dy * dy) - 10.0;
|}
  in
  let ~segments:segments3, ~length:len3, ~stats:_ =
    Sdf_runner.run_contour runner ~region ~filename:"test.neo" different_source
  in
  let ~segments:_, ~length:len1, ~stats:_ =
    Sdf_runner.run_contour runner ~region ~filename:"test.neo" circle_source
  in
  printf "changed source: not phys_equal: %b\n" (not (phys_equal segments segments3));
  printf "different segment counts: %b\n" (len1 <> len3);
  [%expect
    {|
    same source: cached phys_equal segments: true
    changed source: not phys_equal: true
    different segment counts: true
    |}]
;;

let%expect_test "caching: run_contour then run_tiled then run_contour — cache survives" =
  let region = circle_region in
  let runner = Sdf_runner.create () in
  let ~segments:s1, ~length:l1, ~stats:_ =
    Sdf_runner.run_contour runner ~region ~filename:"test.neo" circle_source
  in
  (* Interleave with run_tiled *)
  let _ =
    Sdf_runner.run_tiled
      runner
      ~region
      ~filename:"test.neo"
      circle_source
      ~cull:Tile_scheduler.Cull.No_contour
  in
  let ~segments:s3, ~length:l3, ~stats:_ =
    Sdf_runner.run_contour runner ~region ~filename:"test.neo" circle_source
  in
  (* An interleaved [run_tiled] on a clean runner must not evict the contour cache: the
     third call should return the exact cached array, not a recomputation. *)
  printf "contour cache survives run_tiled (phys_equal): %b\n" (phys_equal s1 s3);
  let sl1 = segment_list s1 ~length:l1 in
  let sl3 = segment_list s3 ~length:l3 in
  printf
    "contour after run_tiled still bitwise equal: %b\n"
    ([%compare.equal: (Int32.t * Int32.t * Int32.t * Int32.t) list] sl1 sl3);
  [%expect
    {|
    contour cache survives run_tiled (phys_equal): true
    contour after run_tiled still bitwise equal: true
    |}]
;;

(* ======================================================================= *)
(* B4: Scene with resample oracle through run_contour *)
(* ======================================================================= *)

let resample_circle_source =
  {|
fn circle(cx, cy, r) {
  fn(x, y) {
    let dx = x - cx;
    let dy = y - cy;
    sqrt(dx * dx + dy * dy) - r
  }
}
let x : float = var("x");
let y : float = var("y");
export resample(circle(32.0, 32.0, 20.0)(x, y));
|}
;;

let%expect_test "run_contour: scene with resample oracle produces segments" =
  let region = circle_region in
  let runner = Sdf_runner.create () in
  Sdf_runner.add_oracle runner ~name:"resample" (module Sdf_resample_oracle);
  let ~segments:_, ~length, ~stats =
    Sdf_runner.run_contour runner ~region ~filename:"test.neo" resample_circle_source
  in
  printf "segment count > 0: %b\n" (length > 0);
  printf "segment count: %d\n" length;
  print_s [%sexp (stats : Sdf_contour.Stats.t)];
  [%expect
    {|
    segment count > 0: true
    segment count: 148
    ((tiles_total 4) (tiles_culled 0) (samples_evaluated 4225))
    |}]
;;

(* ======================================================================= *)
(* B5: Resample oracle with boundary-crossing shape — run_contour bitwise *)
(* equal to dense pipeline *)
(* ======================================================================= *)

(* A circle whose contour crosses the sample-region boundary: cx=0, cy=32, r=20. The
   contour enters and exits through the left edge of the 64×64 region, so marching squares
   emits open chains with unsafe vertices at the boundary. The resample oracle must still
   produce a correct SDF, and run_contour must agree bitwise with a dense evaluation of
   the same scene. *)
let resample_boundary_source =
  {|
fn circle(cx, cy, r) {
  fn(x, y) {
    let dx = x - cx;
    let dy = y - cy;
    sqrt(dx * dx + dy * dy) - r
  }
}
let x : float = var("x");
let y : float = var("y");
export resample(circle(0.0, 32.0, 20.0)(x, y));
|}
;;

let%expect_test "run_contour: boundary-crossing resample oracle equals dense march" =
  let region = circle_region in
  (* Dense reference: evaluate the scene without tiling and march it. *)
  let runner_dense = Sdf_runner.create () in
  Sdf_runner.add_oracle runner_dense ~name:"resample" (module Sdf_resample_oracle);
  let w = region.Sample_region.samples_x
  and h = region.Sample_region.samples_y in
  let dense_grid =
    dense_grid_via_runner
      runner_dense
      ~region
      ~filename:"test.neo"
      resample_boundary_source
  in
  let dense_out : float32# array = Array.create ~len:(w * h * 2 * 4) #0.0s in
  let dense_len = March.run dense_grid dense_out w h in
  let dense_segs = segment_list dense_out ~length:dense_len in
  (* run_contour via the runner *)
  let runner = Sdf_runner.create () in
  Sdf_runner.add_oracle runner ~name:"resample" (module Sdf_resample_oracle);
  let ~segments, ~length, ~stats =
    Sdf_runner.run_contour runner ~region ~filename:"test.neo" resample_boundary_source
  in
  let tiled_segs = segment_list segments ~length in
  printf "dense segments: %d\n" dense_len;
  printf "run_contour segments: %d\n" length;
  printf
    "bitwise equal: %b\n"
    ([%compare.equal: (Int32.t * Int32.t * Int32.t * Int32.t) list] dense_segs tiled_segs);
  print_s [%sexp (stats : Sdf_contour.Stats.t)];
  [%expect
    {|
    dense segments: 74
    run_contour segments: 74
    bitwise equal: true
    ((tiles_total 4) (tiles_culled 0) (samples_evaluated 4225))
    |}]
;;

(* ======================================================================= *)
(* B6: Resample oracle with boundary-crossing shape — run_tiled soundness *)
(* ======================================================================= *)

let%expect_test "run_tiled: boundary-crossing resample oracle — active bitwise equal, \
                 culled sound"
  =
  let region = circle_region in
  let w = region.Sample_region.samples_x
  and h = region.Sample_region.samples_y in
  (* Dense reference grid *)
  let runner_dense = Sdf_runner.create () in
  Sdf_runner.add_oracle runner_dense ~name:"resample" (module Sdf_resample_oracle);
  let dense_grid =
    dense_grid_via_runner
      runner_dense
      ~region
      ~filename:"test.neo"
      resample_boundary_source
  in
  (* Tiled eval *)
  let runner = Sdf_runner.create () in
  Sdf_runner.add_oracle runner ~name:"resample" (module Sdf_resample_oracle);
  let tiled =
    Sdf_runner.run_tiled
      runner
      ~region
      ~filename:"test.neo"
      resample_boundary_source
      ~cull:Tile_scheduler.Cull.No_contour
  in
  let coverage = Stdlib.Array.make (w * h) 0 in
  let all_active_match = ref true in
  let all_culled_sound = ref true in
  Tiled_eval.Result.iter
    tiled
    ~fill:(fun ~x0 ~y0 ~samples_x ~samples_y interval ->
      for dy = 0 to samples_y - 1 do
        for dx = 0 to samples_x - 1 do
          let px = x0 + dx
          and py = y0 + dy in
          let idx = (py * w) + px in
          coverage.(idx) <- coverage.(idx) + 1;
          let dv = dense_grid.(idx) in
          if not (Interval.contains interval dv) then all_culled_sound := false
        done
      done)
    ~draw:(fun ~x0 ~y0 ~samples_x ~samples_y ~get ->
      for dy = 0 to samples_y - 1 do
        for dx = 0 to samples_x - 1 do
          let px = x0 + dx
          and py = y0 + dy in
          let idx = (py * w) + px in
          coverage.(idx) <- coverage.(idx) + 1;
          let tv = Value.to_float (get ((dy * samples_x) + dx)) in
          let dv = dense_grid.(idx) in
          if not (Int32_u.equal (Float32_u.to_bits tv) (Float32_u.to_bits dv))
          then all_active_match := false
        done
      done);
  let all_covered = Stdlib.Array.for_all (fun c -> c >= 1) coverage in
  printf "active tiles bitwise equal: %b\n" !all_active_match;
  printf "culled tiles interval sound: %b\n" !all_culled_sound;
  printf "all pixels covered: %b\n" all_covered;
  [%expect
    {|
    active tiles bitwise equal: true
    culled tiles interval sound: true
    all pixels covered: true
    |}]
;;
