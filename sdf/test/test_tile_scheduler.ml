open! Core
open Sdf
open Helpers

let empty_vars = Map.empty (module Expr_graph_range_eval.Variable_idx)
let no_oracles = Map.empty (module Oracle.Key)
let single_vars = Map.empty (module Expr_graph_eval.Single.Variable_idx)

let schedule ?(tile_cells = 8) ?(cull = Tile_scheduler.Cull.No_contour) tree ~region =
  let range = Expr_graph_range_eval.of_tree tree in
  Tile_scheduler.schedule
    range
    ~vars:empty_vars
    ~oracles:no_oracles
    ~region
    ~tile_cells
    ~cull
;;

let region ~size =
  { Sample_region.start_x = #0.s
  ; end_x = Float32_u.of_int size
  ; samples_x = size
  ; start_y = #0.s
  ; end_y = Float32_u.of_int size
  ; samples_y = size
  }
;;

(* sqrt ((x - cx)^2 + (y - cy)^2) - r *)
let circle ~cx ~cy ~r =
  let dx = sub coord_x (f cx) in
  let dy = sub coord_y (f cy) in
  sub (sqrt (add (mul dx dx) (mul dy dy))) (f r)
;;

let%expect_test "circle verdict map" =
  let t = schedule (circle ~cx:#32.s ~cy:#32.s ~r:#20.s) ~region:(region ~size:64) in
  print_endline (Tile_scheduler.to_string_hum t);
  printf
    "tiles: %d, active: %d\n"
    (Tile_scheduler.num_tiles t)
    (Tile_scheduler.num_active t);
  [%expect
    {|
    ++++++++
    ++....++
    +..--..+
    +.----.+
    +.----.+
    +..--..+
    ++....++
    ++++++++
    tiles: 64, active: 20
    |}]
;;

let%expect_test "everything positive culls at the root" =
  let t = schedule (add (f #5.s) (abs coord_x)) ~region:(region ~size:64) in
  print_endline (Tile_scheduler.to_string_hum t);
  [%expect
    {|
    ++++++++
    ++++++++
    ++++++++
    ++++++++
    ++++++++
    ++++++++
    ++++++++
    ++++++++
    |}]
;;

let%expect_test "top stays fully active" =
  (* inf - inf = NaN everywhere: the bound is [top], which never culls. *)
  let t =
    schedule (sub (f Float32_u.infinity) (f Float32_u.infinity)) ~region:(region ~size:32)
  in
  print_endline (Tile_scheduler.to_string_hum t);
  [%expect {|
    ....
    ....
    ....
    ....
    |}]
;;

let%expect_test "grayscale band cull" =
  let t =
    schedule
      (circle ~cx:#32.s ~cy:#32.s ~r:#20.s)
      ~region:(region ~size:64)
      ~cull:(Constant_outside { below = 0.; above = 1. })
  in
  print_endline (Tile_scheduler.to_string_hum t);
  [%expect
    {|
    ++++++++
    ++....++
    +..--..+
    +.----.+
    +.----.+
    +..--..+
    ++....++
    ++++++++
    |}]
;;

(* ===== Scalar evaluator helper (matches test_range_eval.ml) ===== *)

let eval_scalar tree ~x ~y =
  let t = Expr_graph_eval.Single.of_tree tree in
  let v =
    Expr_graph_eval.Single.run
      t
      ~vars:single_vars
      ~oracles:no_oracles
      ~x:(Float32_u.of_float x)
      ~y:(Float32_u.of_float y)
  in
  Value.to_float v
;;

(* ===== Quickcheck: cull soundness for No_contour ===== *)

(* Generate a random Sample_region.t with small sample counts (1..40 per axis) and
   arbitrary start/end coordinates including flipped (start > end). *)
let gen_region =
  let open Quickcheck.Generator.Let_syntax in
  let coord =
    Quickcheck.Generator.union [ Float.gen_incl (-1e6) 1e6; Float.quickcheck_generator ]
  in
  let%bind samples_x = Int.gen_incl 1 40 in
  let%bind samples_y = Int.gen_incl 1 40 in
  let%bind start_x = coord in
  let%bind end_x = coord in
  let%bind start_y = coord in
  let%map end_y = coord in
  { Sample_region.start_x = Float32_u.of_float start_x
  ; end_x = Float32_u.of_float end_x
  ; samples_x
  ; start_y = Float32_u.of_float start_y
  ; end_y = Float32_u.of_float end_y
  ; samples_y
  }
;;

let gen_tile_cells = Int.gen_incl 1 8

(* Check that every sample in the tile's footprint is contained in the culled interval,
   and that the sign-uniformity promised by No_contour holds. *)
let check_no_contour_culled_tile tree region sched ~tx ~ty interval =
  let x0 = Tile_scheduler.tile_x0 sched ~tx in
  let y0 = Tile_scheduler.tile_y0 sched ~ty in
  let sx = Tile_scheduler.tile_samples_x sched ~tx in
  let sy = Tile_scheduler.tile_samples_y sched ~ty in
  let #{ Interval.lo; hi } = interval in
  for di = 0 to sx - 1 do
    for dj = 0 to sy - 1 do
      let col = x0 + di in
      let row = y0 + dj in
      let x = Float32_u.to_float (Sample_region.x_at region col) in
      let y = Float32_u.to_float (Sample_region.y_at region row) in
      if Float.is_finite x && Float.is_finite y
      then (
        let v = eval_scalar tree ~x ~y in
        let v32 = Float32_u.of_float (Float32_u.to_float v) in
        if not (Interval.contains interval v32)
        then
          Error.raise_s
            [%message
              "No_contour: culled tile sample outside interval"
                ~tree:(Expr_tree.sexp_of_t tree : Sexp.t)
                ~region:(Sample_region.sexp_of_t region : Sexp.t)
                ~tx:(tx : int)
                ~ty:(ty : int)
                ~col:(col : int)
                ~row:(row : int)
                ~value:(Float32_u.to_string v : string)
                ~interval:(Interval.to_string interval : string)];
        (* Sign-uniformity: all values > 0, or all <= 0. *)
        let open Float32_u.O in
        if lo > #0.s
        then (
          if not Float.(Float32_u.to_float v > 0.0)
          then
            Error.raise_s
              [%message
                "No_contour: lo>0 but sample <= 0"
                  ~value:(Float32_u.to_string v : string)
                  ~interval:(Interval.to_string interval : string)])
        else if hi <= #0.s
        then
          if Float.(Float32_u.to_float v > 0.0)
          then
            Error.raise_s
              [%message
                "No_contour: hi<=0 but sample > 0"
                  ~value:(Float32_u.to_string v : string)
                  ~interval:(Interval.to_string interval : string)])
    done
  done
;;

let%test_unit "quickcheck: No_contour culled tiles contain all scalar samples" =
  Quickcheck.test
    (Quickcheck.Generator.tuple3
       (Test_bisimulation.gen_float_expr ~depth:3)
       gen_region
       gen_tile_cells)
    ~sexp_of:[%sexp_of: Expr_tree.t * Sample_region.t * int]
    ~trials:500
    ~f:(fun (tree, region, tile_cells) ->
      let range = Expr_graph_range_eval.of_tree tree in
      let sched =
        Tile_scheduler.schedule
          range
          ~vars:empty_vars
          ~oracles:no_oracles
          ~region
          ~tile_cells
          ~cull:Tile_scheduler.Cull.No_contour
      in
      for ty = 0 to Tile_scheduler.tiles_y sched - 1 do
        for tx = 0 to Tile_scheduler.tiles_x sched - 1 do
          match Tile_scheduler.verdict sched ~tx ~ty with
          | Tile_scheduler.Verdict.Active -> ()
          | Tile_scheduler.Verdict.Culled interval ->
            check_no_contour_culled_tile tree region sched ~tx ~ty interval
        done
      done)
;;

(* ===== Quickcheck: cull soundness for Constant_outside ===== *)

let check_constant_outside_culled_tile tree region sched ~tx ~ty interval ~below ~above =
  let x0 = Tile_scheduler.tile_x0 sched ~tx in
  let y0 = Tile_scheduler.tile_y0 sched ~ty in
  let sx = Tile_scheduler.tile_samples_x sched ~tx in
  let sy = Tile_scheduler.tile_samples_y sched ~ty in
  let #{ Interval.lo; hi } = interval in
  let below32 = Float32_u.of_float below in
  let above32 = Float32_u.of_float above in
  for di = 0 to sx - 1 do
    for dj = 0 to sy - 1 do
      let col = x0 + di in
      let row = y0 + dj in
      let x = Float32_u.to_float (Sample_region.x_at region col) in
      let y = Float32_u.to_float (Sample_region.y_at region row) in
      if Float.is_finite x && Float.is_finite y
      then (
        let v = eval_scalar tree ~x ~y in
        let v32 = Float32_u.of_float (Float32_u.to_float v) in
        if not (Interval.contains interval v32)
        then
          Error.raise_s
            [%message
              "Constant_outside: culled tile sample outside interval"
                ~tree:(Expr_tree.sexp_of_t tree : Sexp.t)
                ~region:(Sample_region.sexp_of_t region : Sexp.t)
                ~tx:(tx : int)
                ~ty:(ty : int)
                ~col:(col : int)
                ~row:(row : int)
                ~value:(Float32_u.to_string v : string)
                ~interval:(Interval.to_string interval : string)];
        (* Constant_outside: all <= below or all > above *)
        let open Float32_u.O in
        if hi <= below32
        then (
          if Float.(Float32_u.to_float v > below)
          then
            Error.raise_s
              [%message
                "Constant_outside: hi<=below but sample > below"
                  ~value:(Float32_u.to_string v : string)
                  ~below:(below : float)
                  ~interval:(Interval.to_string interval : string)])
        else if lo > above32
        then
          if Float.(Float32_u.to_float v <= above)
          then
            Error.raise_s
              [%message
                "Constant_outside: lo>above but sample <= above"
                  ~value:(Float32_u.to_string v : string)
                  ~above:(above : float)
                  ~interval:(Interval.to_string interval : string)])
    done
  done
;;

let%test_unit "quickcheck: Constant_outside culled tiles satisfy range predicate" =
  let below = 0.
  and above = 1. in
  Quickcheck.test
    (Quickcheck.Generator.tuple3
       (Test_bisimulation.gen_float_expr ~depth:3)
       gen_region
       gen_tile_cells)
    ~sexp_of:[%sexp_of: Expr_tree.t * Sample_region.t * int]
    ~trials:500
    ~f:(fun (tree, region, tile_cells) ->
      let range = Expr_graph_range_eval.of_tree tree in
      let sched =
        Tile_scheduler.schedule
          range
          ~vars:empty_vars
          ~oracles:no_oracles
          ~region
          ~tile_cells
          ~cull:(Tile_scheduler.Cull.Constant_outside { below; above })
      in
      for ty = 0 to Tile_scheduler.tiles_y sched - 1 do
        for tx = 0 to Tile_scheduler.tiles_x sched - 1 do
          match Tile_scheduler.verdict sched ~tx ~ty with
          | Tile_scheduler.Verdict.Active -> ()
          | Tile_scheduler.Verdict.Culled interval ->
            check_constant_outside_culled_tile
              tree
              region
              sched
              ~tx
              ~ty
              interval
              ~below
              ~above
        done
      done)
;;

(* ===== Geometry expect tests ===== *)

let print_geometry sched ~label =
  printf
    "%s: tiles_x=%d tiles_y=%d\n"
    label
    (Tile_scheduler.tiles_x sched)
    (Tile_scheduler.tiles_y sched);
  for tx = 0 to Tile_scheduler.tiles_x sched - 1 do
    printf
      "  tile x%d: x0=%d samples_x=%d\n"
      tx
      (Tile_scheduler.tile_x0 sched ~tx)
      (Tile_scheduler.tile_samples_x sched ~tx)
  done;
  for ty = 0 to Tile_scheduler.tiles_y sched - 1 do
    printf
      "  tile y%d: y0=%d samples_y=%d\n"
      ty
      (Tile_scheduler.tile_y0 sched ~ty)
      (Tile_scheduler.tile_samples_y sched ~ty)
  done
;;

let all_active_geom ~samples_x ~samples_y ~tile_cells =
  let region =
    { Sample_region.start_x = #0.s
    ; end_x = #1.s
    ; samples_x
    ; start_y = #0.s
    ; end_y = #1.s
    ; samples_y
    }
  in
  Tile_scheduler.all_active ~region ~tile_cells
;;

let%expect_test "geometry: single-sample grid (1x1)" =
  let sched = all_active_geom ~samples_x:1 ~samples_y:1 ~tile_cells:4 in
  print_geometry sched ~label:"1x1/tile4";
  [%expect
    {|
    1x1/tile4: tiles_x=1 tiles_y=1
      tile x0: x0=0 samples_x=1
      tile y0: y0=0 samples_y=1
    |}]
;;

let%expect_test "geometry: 1xN strip" =
  let sched = all_active_geom ~samples_x:1 ~samples_y:5 ~tile_cells:4 in
  print_geometry sched ~label:"1x5/tile4";
  [%expect
    {|
    1x5/tile4: tiles_x=1 tiles_y=1
      tile x0: x0=0 samples_x=1
      tile y0: y0=0 samples_y=5
    |}]
;;

let%expect_test "geometry: samples smaller than one tile" =
  let sched = all_active_geom ~samples_x:3 ~samples_y:3 ~tile_cells:8 in
  print_geometry sched ~label:"3x3/tile8";
  [%expect
    {|
    3x3/tile8: tiles_x=1 tiles_y=1
      tile x0: x0=0 samples_x=3
      tile y0: y0=0 samples_y=3
    |}]
;;

let%expect_test "geometry: size not a multiple of tile_cells" =
  (* 10 samples, tile_cells=3: ceil(9/3)=3 tiles in x. Tile 0: x0=0, samples=4 (covers
     cols 0..3) Tile 1: x0=3, samples=4 (covers cols 3..6) Tile 2: x0=6, samples=4 (covers
     cols 6..9) *)
  let sched = all_active_geom ~samples_x:10 ~samples_y:4 ~tile_cells:3 in
  print_geometry sched ~label:"10x4/tile3";
  [%expect
    {|
    10x4/tile3: tiles_x=3 tiles_y=1
      tile x0: x0=0 samples_x=4
      tile x1: x0=3 samples_x=4
      tile x2: x0=6 samples_x=4
      tile y0: y0=0 samples_y=4
    |}]
;;

let%expect_test "geometry: last sample of last tile is samples_x-1" =
  (* For any tiling, the last sample column covered by the last x-tile must be exactly
     samples_x - 1. *)
  let check ~samples ~tile_cells =
    let sched = all_active_geom ~samples_x:samples ~samples_y:1 ~tile_cells in
    let last_tx = Tile_scheduler.tiles_x sched - 1 in
    let x0 = Tile_scheduler.tile_x0 sched ~tx:last_tx in
    let sx = Tile_scheduler.tile_samples_x sched ~tx:last_tx in
    let last_col = x0 + sx - 1 in
    printf
      "samples=%d tile_cells=%d last_col=%d expected=%d %s\n"
      samples
      tile_cells
      last_col
      (samples - 1)
      (if Int.equal last_col (samples - 1) then "OK" else "FAIL")
  in
  check ~samples:1 ~tile_cells:1;
  check ~samples:4 ~tile_cells:8;
  check ~samples:8 ~tile_cells:4;
  check ~samples:9 ~tile_cells:4;
  check ~samples:16 ~tile_cells:4;
  check ~samples:17 ~tile_cells:4;
  [%expect
    {|
    samples=1 tile_cells=1 last_col=0 expected=0 OK
    samples=4 tile_cells=8 last_col=3 expected=3 OK
    samples=8 tile_cells=4 last_col=7 expected=7 OK
    samples=9 tile_cells=4 last_col=8 expected=8 OK
    samples=16 tile_cells=4 last_col=15 expected=15 OK
    samples=17 tile_cells=4 last_col=16 expected=16 OK
    |}]
;;

let%expect_test "geometry: adjacent tiles share boundary sample" =
  (* For a 9-sample, tile_cells=4 grid: tiles are [0..4], [4..8]. The last sample of tile
     0 equals the first sample of tile 1 (col 4). *)
  let sched = all_active_geom ~samples_x:9 ~samples_y:1 ~tile_cells:4 in
  for tx = 0 to Tile_scheduler.tiles_x sched - 2 do
    let x0_curr = Tile_scheduler.tile_x0 sched ~tx in
    let sx_curr = Tile_scheduler.tile_samples_x sched ~tx in
    let last_of_curr = x0_curr + sx_curr - 1 in
    let x0_next = Tile_scheduler.tile_x0 sched ~tx:(tx + 1) in
    printf
      "tile %d last=%d, tile %d first=%d %s\n"
      tx
      last_of_curr
      (tx + 1)
      x0_next
      (if Int.equal last_of_curr x0_next then "shared" else "GAP")
  done;
  [%expect {| tile 0 last=4, tile 1 first=4 shared |}]
;;

(* ===== Flipped region expect test ===== *)

let%expect_test "flipped region: circle verdict map" =
  (* start_x > end_x — the scheduler should still produce a sensible verdict. *)
  let region =
    { Sample_region.start_x = Float32_u.of_int 64
    ; end_x = Float32_u.of_int 0
    ; samples_x = 64
    ; start_y = Float32_u.of_int 64
    ; end_y = Float32_u.of_int 0
    ; samples_y = 64
    }
  in
  let tree = circle ~cx:#32.s ~cy:#32.s ~r:#20.s in
  let range = Expr_graph_range_eval.of_tree tree in
  let sched =
    Tile_scheduler.schedule
      range
      ~vars:empty_vars
      ~oracles:no_oracles
      ~region
      ~tile_cells:8
      ~cull:Tile_scheduler.Cull.No_contour
  in
  printf
    "tiles: %d active: %d\n"
    (Tile_scheduler.num_tiles sched)
    (Tile_scheduler.num_active sched);
  print_endline (Tile_scheduler.to_string_hum sched);
  [%expect
    {|
    tiles: 64 active: 20
    ++++++++
    ++....++
    +..--..+
    +.----.+
    +.----.+
    +..--..+
    ++....++
    ++++++++
    |}]
;;
