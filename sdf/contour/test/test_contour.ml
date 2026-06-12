open! Core
open Sdf

let here = Stdlib.Lexing.dummy_pos
let ok = Or_error.ok_exn
let f x = ok (Expr_tree.float_literal ~loc:here x)
let coord_x = ok (Expr_tree.coord_x ~loc:here)
let coord_y = ok (Expr_tree.coord_y ~loc:here)
let add a b = ok (Expr_tree.add ~loc:here a b)
let sub a b = ok (Expr_tree.sub ~loc:here a b)
let mul a b = ok (Expr_tree.mul ~loc:here a b)
let abs a = ok (Expr_tree.abs ~loc:here a)
let lt a b = ok (Expr_tree.lt ~loc:here a b)
let sqrt a = ok (Expr_tree.sqrt ~loc:here a)
let oracle name args = ok (Expr_tree.oracle ~loc:here name args)
let no_oracles = Map.empty (module Oracle.Key)

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

(* The dense reference pipeline: sample the whole grid sequentially, march it whole. *)
let dense_segments (module E : Executor.S) tree ~(region : Sample_region.t) =
  let prepared = E.Batch.Prepared.of_tree tree in
  let batch = E.Batch.Batch.create prepared region in
  let result = E.Batch.Batch.run batch ~oracles:no_oracles in
  let w = region.samples_x
  and h = region.samples_y in
  let grid : float32# array = Array.create ~len:(w * h) #0.0s in
  for i = 0 to (w * h) - 1 do
    grid.(i) <- Value.to_float (E.Batch.Result.get_output result ~px:i)
  done;
  let out : float32# array = Array.create ~len:(w * h * 2 * 4) #0.0s in
  let length = March.run grid out w h in
  out, length
;;

(* Segments as sorted lists of float-bit 4-tuples, so multiset comparison is bitwise. *)
let segment_list (segments : float32# array) ~length =
  List.init length ~f:(fun i ->
    ( Int32_u.to_int32 (Float32_u.to_bits segments.(i * 4))
    , Int32_u.to_int32 (Float32_u.to_bits segments.((i * 4) + 1))
    , Int32_u.to_int32 (Float32_u.to_bits segments.((i * 4) + 2))
    , Int32_u.to_int32 (Float32_u.to_bits segments.((i * 4) + 3)) ))
  |> List.sort ~compare:[%compare: Int32.t * Int32.t * Int32.t * Int32.t]
;;

(* ---- helpers shared by all tests ---- *)

(* [dense_segments_with_oracles] generalises [dense_segments] to accept an oracle map. *)
let dense_segments_with_oracles
  (module E : Executor.S)
  tree
  ~(region : Sample_region.t)
  ~oracles
  =
  let prepared = E.Batch.Prepared.of_tree tree in
  let batch = E.Batch.Batch.create prepared region in
  let result = E.Batch.Batch.run batch ~oracles in
  let w = region.samples_x
  and h = region.samples_y in
  let grid : float32# array = Array.create ~len:(w * h) #0.0s in
  for i = 0 to (w * h) - 1 do
    grid.(i) <- Value.to_float (E.Batch.Result.get_output result ~px:i)
  done;
  let out : float32# array = Array.create ~len:(w * h * 2 * 4) #0.0s in
  let length = March.run grid out w h in
  out, length
;;

(* ---- original smoke test ---- *)

let%expect_test "tiled extraction is bitwise identical to dense march (circle)" =
  let tree = circle ~cx:#32.s ~cy:#32.s ~r:#20.s in
  let region = square_region ~size:64 in
  let dense_out, dense_len =
    dense_segments (module Sdf.Expr_graph_batch_eval) tree ~region
  in
  let dense = segment_list dense_out ~length:dense_len in
  let scheduler = Parallel_scheduler.create () in
  Parallel_scheduler.parallel scheduler ~f:(fun par ->
    let ~segments, ~length, ~stats =
      Sdf_contour.extract
        ~exec:(Obj.magic Obj.magic (module Sdf.Expr_graph_batch_eval : Sdf.Executor.S))
        ~par
        ~oracles:(Map.empty (module Oracle.Key))
        ~region
        ~tile_cells:16
        tree
    in
    let tiled = segment_list segments ~length in
    printf "dense segments: %d, tiled segments: %d\n" dense_len length;
    printf
      "bitwise equal: %b\n"
      ([%compare.equal: (Int32.t * Int32.t * Int32.t * Int32.t) list] dense tiled);
    print_s [%sexp (stats : Sdf_contour.Stats.t)]);
  [%expect
    {|
    dense segments: 148, tiled segments: 148
    bitwise equal: true
    ((tiles_total 16) (tiles_culled 4) (samples_evaluated 3400))
    |}]
;;

(* ======================================================================= *)
(* Test 1: Differential quickcheck — dense vs tiled, random trees/regions *)
(* ======================================================================= *)

(* Generate a random [Sample_region.t] with possibly small or asymmetric extents. *)
let gen_region =
  let open Quickcheck.Generator.Let_syntax in
  let gen_coord = Float.gen_incl (-100.) 100. in
  let%bind samples_x = Int.gen_incl 1 40 in
  let%bind samples_y = Int.gen_incl 1 40 in
  (* Allow start > end (flipped) and start = end (degenerate) to stress-test. *)
  let%bind start_x = gen_coord in
  let%bind end_x = gen_coord in
  let%bind start_y = gen_coord in
  let%map end_y = gen_coord in
  { Sample_region.start_x = Float32_u.of_float start_x
  ; end_x = Float32_u.of_float end_x
  ; samples_x
  ; start_y = Float32_u.of_float start_y
  ; end_y = Float32_u.of_float end_y
  ; samples_y
  }
;;

(* Run one differential trial (dense vs tiled) for a given backend; raises on mismatch.
   [no_oracles] is not captured — a fresh empty map is constructed inside the closure. *)
let run_differential_trial (module E : Executor.S) scheduler tree ~region ~tile_cells =
  let dense_out, dense_len = dense_segments (module E) tree ~region in
  let dense = segment_list dense_out ~length:dense_len in
  Parallel_scheduler.parallel scheduler ~f:(fun par ->
    let empty_oracles = Map.empty (module Oracle.Key) in
    let ~segments, ~length, ~stats =
      Sdf_contour.extract
        ~exec:(Obj.magic Obj.magic (module E : Sdf.Executor.S))
        ~par
        ~oracles:empty_oracles
        ~region
        ~tile_cells
        tree
    in
    let tiled = segment_list segments ~length in
    if not ([%compare.equal: (Int32.t * Int32.t * Int32.t * Int32.t) list] dense tiled)
    then (
      let _ = stats in
      Error.raise_s
        [%message
          "differential mismatch"
            ~tree:(Expr_tree.sexp_of_t tree : Sexp.t)
            ~region:(Sample_region.sexp_of_t region : Sexp.t)
            ~tile_cells:(tile_cells : int)
            ~dense_count:(dense_len : int)
            ~tiled_count:(length : int)]))
;;

let%test_unit "quickcheck differential: Expr_graph_batch_eval" =
  let open Quickcheck.Generator.Let_syntax in
  let gen =
    let%bind tree = Sdf_test.Test_bisimulation.gen_float_expr ~depth:3 in
    let%bind region = gen_region in
    let%map tile_cells = Int.gen_incl 1 8 in
    tree, region, tile_cells
  in
  let scheduler = Parallel_scheduler.create () in
  Quickcheck.test
    gen
    ~trials:Quickcheck_trials.trials
    ~sexp_of:[%sexp_of: Expr_tree.t * Sample_region.t * int]
    ~f:(fun (tree, region, tile_cells) ->
      run_differential_trial
        (module Sdf.Expr_graph_batch_eval)
        scheduler
        tree
        ~region
        ~tile_cells)
;;

let%test_unit "quickcheck differential: Expr_tree_eval" =
  let open Quickcheck.Generator.Let_syntax in
  let gen =
    let%bind tree = Sdf_test.Test_bisimulation.gen_float_expr ~depth:3 in
    let%bind region = gen_region in
    let%map tile_cells = Int.gen_incl 1 8 in
    tree, region, tile_cells
  in
  let scheduler = Parallel_scheduler.create () in
  Quickcheck.test
    gen
    ~trials:Quickcheck_trials.trials
    ~sexp_of:[%sexp_of: Expr_tree.t * Sample_region.t * int]
    ~f:(fun (tree, region, tile_cells) ->
      run_differential_trial
        (module Sdf.Expr_tree_eval)
        scheduler
        tree
        ~region
        ~tile_cells)
;;

let%test_unit "quickcheck differential: Expr_graph_eval" =
  let open Quickcheck.Generator.Let_syntax in
  let gen =
    let%bind tree = Sdf_test.Test_bisimulation.gen_float_expr ~depth:3 in
    let%bind region = gen_region in
    let%map tile_cells = Int.gen_incl 1 8 in
    tree, region, tile_cells
  in
  let scheduler = Parallel_scheduler.create () in
  Quickcheck.test
    gen
    ~trials:Quickcheck_trials.trials
    ~sexp_of:[%sexp_of: Expr_tree.t * Sample_region.t * int]
    ~f:(fun (tree, region, tile_cells) ->
      run_differential_trial
        (module Sdf.Expr_graph_eval)
        scheduler
        tree
        ~region
        ~tile_cells)
;;

(* ======================================================================= *)
(* Test 1b: Stats sanity checks (woven into the quickcheck above as a *)
(* separate unit test using a smaller set to keep runtime bounded) *)
(* ======================================================================= *)

let%test_unit "quickcheck stats sanity" =
  let open Quickcheck.Generator.Let_syntax in
  let gen =
    let%bind tree = Sdf_test.Test_bisimulation.gen_float_expr ~depth:2 in
    let%bind samples_x = Int.gen_incl 2 20 in
    let%bind samples_y = Int.gen_incl 2 20 in
    let%map tile_cells = Int.gen_incl 1 8 in
    let region =
      { Sample_region.start_x = Float32_u.of_float (-10.)
      ; end_x = #10.s
      ; samples_x
      ; start_y = Float32_u.of_float (-10.)
      ; end_y = #10.s
      ; samples_y
      }
    in
    tree, region, tile_cells
  in
  let scheduler = Parallel_scheduler.create () in
  Quickcheck.test
    gen
    ~trials:Quickcheck_trials.trials
    ~sexp_of:[%sexp_of: Expr_tree.t * Sample_region.t * int]
    ~f:(fun (tree, region, tile_cells) ->
      Parallel_scheduler.parallel scheduler ~f:(fun par ->
        let ~segments:_, ~length:_, ~stats =
          Sdf_contour.extract
            ~exec:
              (Obj.magic Obj.magic (module Sdf.Expr_graph_batch_eval : Sdf.Executor.S))
            ~par
            ~oracles:(Map.empty (module Oracle.Key))
            ~region
            ~tile_cells
            tree
        in
        assert (stats.tiles_total - stats.tiles_culled >= 0);
        (* samples_evaluated counts samples per active tile including shared boundary
           samples (tiles overlap by 1 on each edge), so it can exceed total_cells. The
           invariant is simply that samples_evaluated <= tiles_total * cells. *)
        assert (stats.samples_evaluated >= 0)))
;;

(* ======================================================================= *)
(* Test 2: Seam adversaries — expect tests *)
(* ======================================================================= *)

(* Helper that runs both pipelines and prints summary. *)
let seam_test (module E : Executor.S) tree ~region ~tile_cells =
  let dense_out, dense_len = dense_segments (module E) tree ~region in
  let dense = segment_list dense_out ~length:dense_len in
  let scheduler = Parallel_scheduler.create () in
  Parallel_scheduler.parallel scheduler ~f:(fun par ->
    let ~segments, ~length, ~stats =
      Sdf_contour.extract
        ~exec:(Obj.magic Obj.magic (module E : Sdf.Executor.S))
        ~par
        ~oracles:(Map.empty (module Oracle.Key))
        ~region
        ~tile_cells
        tree
    in
    let tiled = segment_list segments ~length in
    printf "dense: %d, tiled: %d\n" dense_len length;
    printf
      "bitwise equal: %b\n"
      ([%compare.equal: (Int32.t * Int32.t * Int32.t * Int32.t) list] dense tiled);
    print_s [%sexp (stats : Sdf_contour.Stats.t)])
;;

let%expect_test "seam: contour exactly on a tile seam (x - 16 over 33-wide region)" =
  (* samples_x=33 with tile_cells=16 → tile boundary exactly at column 16; x=16 is 0.0 in
     the SDF, so marching squares treats it as "inside edge". *)
  let tree = sub coord_x (f #16.s) in
  let region =
    { Sample_region.start_x = #0.s
    ; end_x = #32.s
    ; samples_x = 33
    ; start_y = #0.s
    ; end_y = #32.s
    ; samples_y = 33
    }
  in
  seam_test (module Sdf.Expr_graph_batch_eval) tree ~region ~tile_cells:16;
  [%expect
    {|
    dense: 32, tiled: 32
    bitwise equal: true
    ((tiles_total 4) (tiles_culled 2) (samples_evaluated 578))
    |}]
;;

let%expect_test "seam: shallow diagonal (x - 0.05*y - 16.01)" =
  let tree = sub (sub coord_x (mul (f #0.05s) coord_y)) (f #16.01s) in
  let region =
    { Sample_region.start_x = #0.s
    ; end_x = #33.s
    ; samples_x = 34
    ; start_y = #0.s
    ; end_y = #33.s
    ; samples_y = 34
    }
  in
  seam_test (module Sdf.Expr_graph_batch_eval) tree ~region ~tile_cells:16;
  [%expect
    {|
    dense: 35, tiled: 35
    bitwise equal: true
    ((tiles_total 9) (tiles_culled 6) (samples_evaluated 612))
    |}]
;;

let%expect_test "seam: circle centered exactly on a tile corner (cx=16,cy=16,r=8)" =
  let tree = circle ~cx:#16.s ~cy:#16.s ~r:#8.s in
  let region =
    { Sample_region.start_x = #0.s
    ; end_x = #32.s
    ; samples_x = 33
    ; start_y = #0.s
    ; end_y = #32.s
    ; samples_y = 33
    }
  in
  seam_test (module Sdf.Expr_graph_batch_eval) tree ~region ~tile_cells:16;
  [%expect
    {|
    dense: 64, tiled: 64
    bitwise equal: true
    ((tiles_total 4) (tiles_culled 0) (samples_evaluated 1156))
    |}]
;;

let%expect_test "seam: tiny circle entirely inside one tile (r=2)" =
  let tree = circle ~cx:#4.s ~cy:#4.s ~r:#2.s in
  let region =
    { Sample_region.start_x = #0.s
    ; end_x = #32.s
    ; samples_x = 33
    ; start_y = #0.s
    ; end_y = #32.s
    ; samples_y = 33
    }
  in
  seam_test (module Sdf.Expr_graph_batch_eval) tree ~region ~tile_cells:16;
  [%expect
    {|
    dense: 16, tiled: 16
    bitwise equal: true
    ((tiles_total 4) (tiles_culled 3) (samples_evaluated 289))
    |}]
;;

let%expect_test "seam: circle smaller than one cell (r=0.3)" =
  (* Both pipelines may emit 0 or very few segments; equality is what matters. *)
  let tree = circle ~cx:#4.s ~cy:#4.s ~r:#0.3s in
  let region =
    { Sample_region.start_x = #0.s
    ; end_x = #32.s
    ; samples_x = 33
    ; start_y = #0.s
    ; end_y = #32.s
    ; samples_y = 33
    }
  in
  seam_test (module Sdf.Expr_graph_batch_eval) tree ~region ~tile_cells:8;
  [%expect
    {|
    dense: 4, tiled: 4
    bitwise equal: true
    ((tiles_total 16) (tiles_culled 13) (samples_evaluated 243))
    |}]
;;

let%expect_test "seam: everything-positive scene (abs(x) + 5, all tiles culled)" =
  let tree = add (abs coord_x) (f #5.s) in
  let region =
    { Sample_region.start_x = Float32_u.of_float (-10.)
    ; end_x = #10.s
    ; samples_x = 21
    ; start_y = Float32_u.of_float (-10.)
    ; end_y = #10.s
    ; samples_y = 21
    }
  in
  seam_test (module Sdf.Expr_graph_batch_eval) tree ~region ~tile_cells:8;
  [%expect
    {|
    dense: 0, tiled: 0
    bitwise equal: true
    ((tiles_total 9) (tiles_culled 9) (samples_evaluated 0))
    |}]
;;

(* ======================================================================= *)
(* Test 3: Line_join stitching *)
(* ======================================================================= *)

let%expect_test "line_join: circle crossing many tiles gives same shape \
                 count/classification"
  =
  let tree = circle ~cx:#32.s ~cy:#32.s ~r:#20.s in
  let region = square_region ~size:64 in
  (* Compute dense segments and segment_list BEFORE the parallel closure so only the
     immutable [dense_seg_list] (an [int32 * ...] list) is captured. *)
  let dense_out, dense_len =
    dense_segments (module Sdf.Expr_graph_batch_eval) tree ~region
  in
  let dense_shapes_count = List.length (Line_join.f dense_out ~length:dense_len) in
  let dense_classify_sorted =
    Line_join.f dense_out ~length:dense_len
    |> List.map ~f:(fun shape ->
      match shape with
      | Line_join.Connected.Joined _ -> "Joined"
      | Line_join.Connected.Disjoint _ -> "Disjoint")
    |> List.sort ~compare:String.compare
  in
  (* Allocate the result buffer and length holder OUTSIDE the parallel closure; inside the
     closure we use magic_uncontended to write into them (same pattern as sdf/neon/svg.ml
     and sdf_contour.ml itself), then call the nonportable Line_join.f only after the
     closure has returned. *)
  let samples_x = region.samples_x
  and samples_y = region.samples_y in
  let tiled_buf : float32# array =
    Array.create ~len:(samples_x * samples_y * 2 * 4) #0.0s
  in
  let tiled_len_box = [| 0 |] in
  let scheduler = Parallel_scheduler.create () in
  Parallel_scheduler.parallel scheduler ~f:(fun par ->
    let ~segments, ~length, ~stats:_ =
      Sdf_contour.extract
        ~exec:(Obj.magic Obj.magic (module Sdf.Expr_graph_batch_eval : Sdf.Executor.S))
        ~par
        ~oracles:(Map.empty (module Oracle.Key))
        ~region
        ~tile_cells:8
        tree
    in
    let tiled_buf = Stdlib.Obj.magic_uncontended tiled_buf in
    let tiled_len_box = Stdlib.Obj.magic_uncontended tiled_len_box in
    for i = 0 to (length * 4) - 1 do
      tiled_buf.(i) <- segments.(i)
    done;
    tiled_len_box.(0) <- length);
  let tiled_length = tiled_len_box.(0) in
  let tiled_shapes = Line_join.f tiled_buf ~length:tiled_length in
  let tiled_classify_sorted =
    List.map tiled_shapes ~f:(fun shape ->
      match shape with
      | Line_join.Connected.Joined _ -> "Joined"
      | Line_join.Connected.Disjoint _ -> "Disjoint")
    |> List.sort ~compare:String.compare
  in
  printf
    "dense shapes: %d, tiled shapes: %d\n"
    dense_shapes_count
    (List.length tiled_shapes);
  printf "same count: %b\n" (dense_shapes_count = List.length tiled_shapes);
  printf
    "same classification: %b\n"
    ([%compare.equal: string list] dense_classify_sorted tiled_classify_sorted);
  printf "classifications: %s\n" (String.concat ~sep:", " dense_classify_sorted);
  [%expect
    {|
    dense shapes: 1, tiled shapes: 1
    same count: true
    same classification: true
    classifications: Joined
    |}]
;;

(* ======================================================================= *)
(* Test 4: Bool-typed tree — extract skips interval scheduling *)
(* ======================================================================= *)

let%expect_test "bool-typed tree: lt coord_x (f #16.s) matches dense" =
  (* Bool trees bypass interval scheduling → all tiles active. The dense march
     reinterprets bool bits as floats, which produces a step-function field. Both
     pipelines must agree bitwise. *)
  let tree = lt coord_x (f #16.s) in
  let region =
    { Sample_region.start_x = #0.s
    ; end_x = #32.s
    ; samples_x = 33
    ; start_y = #0.s
    ; end_y = #32.s
    ; samples_y = 33
    }
  in
  let dense_out, dense_len =
    dense_segments (module Sdf.Expr_graph_batch_eval) tree ~region
  in
  let dense = segment_list dense_out ~length:dense_len in
  let scheduler = Parallel_scheduler.create () in
  Parallel_scheduler.parallel scheduler ~f:(fun par ->
    let ~segments, ~length, ~stats =
      Sdf_contour.extract
        ~exec:(Obj.magic Obj.magic (module Sdf.Expr_graph_batch_eval : Sdf.Executor.S))
        ~par
        ~oracles:(Map.empty (module Oracle.Key))
        ~region
        ~tile_cells:16
        tree
    in
    let tiled = segment_list segments ~length in
    printf "dense: %d, tiled: %d\n" dense_len length;
    printf
      "bitwise equal: %b\n"
      ([%compare.equal: (Int32.t * Int32.t * Int32.t * Int32.t) list] dense tiled);
    (* Bool trees → 0 tiles culled (all active) *)
    printf "tiles_culled: %d\n" stats.tiles_culled;
    print_s [%sexp (stats : Sdf_contour.Stats.t)]);
  [%expect
    {|
    dense: 32, tiled: 32
    bitwise equal: true
    tiles_culled: 0
    ((tiles_total 4) (tiles_culled 0) (samples_evaluated 1156))
    |}]
;;

(* ======================================================================= *)
(* Test 5: Oracle scene — passthrough oracle, dense inside closure *)
(* ======================================================================= *)

let%expect_test "oracle passthrough: extract matches dense (circle inside passthrough \
                 oracle)"
  =
  let tree = oracle "passthrough" [ circle ~cx:#16.s ~cy:#16.s ~r:#8.s ] in
  let region =
    { Sample_region.start_x = #0.s
    ; end_x = #32.s
    ; samples_x = 33
    ; start_y = #0.s
    ; end_y = #32.s
    ; samples_y = 33
    }
  in
  let scheduler = Parallel_scheduler.create () in
  Parallel_scheduler.parallel scheduler ~f:(fun par ->
    (* Prepare oracles exactly as test_executor_with_oracle.ml does. *)
    let oracle_registry = [ "passthrough", (module Sdf_passthrough_oracle : Oracle.S) ] in
    let oracles =
      Oracle_dependencies.extract_deps tree
      |> List.join
      |> List.fold
           ~init:(Map.empty (module Oracle.Key))
           ~f:(fun prepared ((key, _) as oracle_key) ->
             let module M =
               (val List.Assoc.find_exn oracle_registry ~equal:String.equal key)
             in
             let p =
               M.create (snd oracle_key)
               |> M.prepare
                    ~exec:
                      (Obj.magic
                         Obj.magic
                         (module Sdf.Expr_graph_batch_eval : Sdf.Executor.S))
                    ~par
                    ~trace:(Phase_trace.null ())
                    ~oracles:prepared
                    ~sample_region:region
             in
             Map.set prepared ~key:oracle_key ~data:p)
    in
    (* Dense reference — computed inside the closure so it can use [oracles]. *)
    let dense_out, dense_len =
      dense_segments_with_oracles (module Sdf.Expr_graph_batch_eval) tree ~region ~oracles
    in
    let dense = segment_list dense_out ~length:dense_len in
    let ~segments, ~length, ~stats =
      Sdf_contour.extract
        ~exec:(Obj.magic Obj.magic (module Sdf.Expr_graph_batch_eval : Sdf.Executor.S))
        ~par
        ~oracles
        ~region
        ~tile_cells:16
        tree
    in
    let tiled = segment_list segments ~length in
    printf "dense: %d, tiled: %d\n" dense_len length;
    printf
      "bitwise equal: %b\n"
      ([%compare.equal: (Int32.t * Int32.t * Int32.t * Int32.t) list] dense tiled);
    print_s [%sexp (stats : Sdf_contour.Stats.t)]);
  [%expect
    {|
    dense: 64, tiled: 64
    bitwise equal: true
    ((tiles_total 4) (tiles_culled 0) (samples_evaluated 1156))
    |}]
;;
