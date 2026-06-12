open! Core
open Sdf
open Sdf_for_testing
open Helpers

(* ===== Helpers ===== *)

let no_oracles = Map.empty (module Oracle.Key)

(* A simple grid region: [0,1] x [0,1] with given sample counts. *)
let make_region ~samples_x ~samples_y =
  { Sample_region.start_x = #0.s
  ; end_x = #1.s
  ; start_y = #0.s
  ; end_y = #1.s
  ; samples_x
  ; samples_y
  }
;;

(* Evaluate a tree over a full region, returning a flat float array (row-major). *)
let run_full (module E : Executor.S_batch) tree region =
  let prepared = E.Prepared.of_tree tree in
  let batch = E.Batch.create prepared region in
  let result = E.Batch.run batch ~oracles:no_oracles in
  let n = region.samples_x * region.samples_y in
  Array.init n ~f:(fun px ->
    Float32_u.to_float (Value.to_float (E.Result.get_output result ~px)))
;;

(* Evaluate a tree over a sub-rectangle of region, returning a flat float array. *)
let run_sub (module E : Executor.S_batch) tree region ~x0 ~y0 ~samples_x ~samples_y =
  let prepared = E.Prepared.of_tree tree in
  let batch = E.Batch.create_sub prepared region ~x0 ~y0 ~samples_x ~samples_y in
  let result = E.Batch.run batch ~oracles:no_oracles in
  let n = samples_x * samples_y in
  Array.init n ~f:(fun px ->
    Float32_u.to_float (Value.to_float (E.Result.get_output result ~px)))
;;

(* Pull out the value at (col, row) from a full-batch flat array. *)
let full_value full region ~col ~row = full.((row * region.Sample_region.samples_x) + col)

(* ===== Functor to instantiate the tests for a given backend ===== *)

module Make_tests (E : Executor.S_batch) = struct
  let impl = (module E : Executor.S_batch)

  let check_sub_matches_full tree region ~x0 ~y0 ~samples_x ~samples_y =
    let full = run_full impl tree region in
    let sub = run_sub impl tree region ~x0 ~y0 ~samples_x ~samples_y in
    for dj = 0 to samples_y - 1 do
      for di = 0 to samples_x - 1 do
        let px = (dj * samples_x) + di in
        let sub_v = sub.(px) in
        let full_v = full_value full region ~col:(x0 + di) ~row:(y0 + dj) in
        (* Compare bit-for-bit via int32 reinterpretation to catch signed-zero and NaN
           disagreements. *)
        let sub_bits = Int32.bits_of_float sub_v in
        let full_bits = Int32.bits_of_float full_v in
        if not (Int32.equal sub_bits full_bits)
        then
          Error.raise_s
            [%message
              "create_sub: sub-batch value differs from full-batch"
                ~x0:(x0 : int)
                ~y0:(y0 : int)
                ~di:(di : int)
                ~dj:(dj : int)
                ~col:(x0 + di : int)
                ~row:(y0 + dj : int)
                ~sub_value:(sub_v : float)
                ~full_value:(full_v : float)]
      done
    done
  ;;

  (* ── expect tests for concrete cases ── *)

  let%expect_test "sub=full: x0=0 y0=0 is identical to create" =
    let region = make_region ~samples_x:4 ~samples_y:4 in
    let tree = add coord_x coord_y in
    let full = run_full impl tree region in
    let sub = run_sub impl tree region ~x0:0 ~y0:0 ~samples_x:4 ~samples_y:4 in
    let eq =
      Array.for_all2_exn full sub ~f:(fun a b ->
        Int32.equal (Int32.bits_of_float a) (Int32.bits_of_float b))
    in
    printf "equal: %b\n" eq;
    [%expect {| equal: true |}]
  ;;

  let%expect_test "sub 2x2 top-left corner matches full" =
    let region = make_region ~samples_x:4 ~samples_y:4 in
    let tree = add coord_x coord_y in
    check_sub_matches_full tree region ~x0:0 ~y0:0 ~samples_x:2 ~samples_y:2;
    [%expect {||}]
  ;;

  let%expect_test "sub 2x2 bottom-right corner matches full" =
    let region = make_region ~samples_x:4 ~samples_y:4 in
    let tree = add coord_x coord_y in
    check_sub_matches_full tree region ~x0:2 ~y0:2 ~samples_x:2 ~samples_y:2;
    [%expect {||}]
  ;;

  let%expect_test "sub single sample in the middle matches full" =
    let region = make_region ~samples_x:5 ~samples_y:5 in
    let tree = mul coord_x coord_y in
    check_sub_matches_full tree region ~x0:2 ~y0:3 ~samples_x:1 ~samples_y:1;
    [%expect {||}]
  ;;

  let%expect_test "sub matches full: circle SDF offset window" =
    let cx = #32.s
    and cy = #32.s
    and r = #20.s in
    let dx = sub coord_x (f cx) in
    let dy = sub coord_y (f cy) in
    let tree = sub (sqrt (add (mul dx dx) (mul dy dy))) (f r) in
    let region =
      { Sample_region.start_x = #0.s
      ; end_x = Float32_u.of_int 64
      ; start_y = #0.s
      ; end_y = Float32_u.of_int 64
      ; samples_x = 64
      ; samples_y = 64
      }
    in
    (* Check a 16x16 window starting at (24, 24), which straddles the circle boundary. *)
    check_sub_matches_full tree region ~x0:24 ~y0:24 ~samples_x:16 ~samples_y:16;
    [%expect {||}]
  ;;

  let%expect_test "sub values are correct for x+y (spot check)" =
    (* region [0,1] 3x3: step = 1/3. x_at(0)=0, x_at(1)=1/3, x_at(2)=2/3. sub at x0=1,
       y0=1, 2x2 → pixels (1,1),(2,1),(1,2),(2,2). *)
    let region = make_region ~samples_x:3 ~samples_y:3 in
    let tree = add coord_x coord_y in
    let sub = run_sub impl tree region ~x0:1 ~y0:1 ~samples_x:2 ~samples_y:2 in
    (* print all sub values *)
    Array.iter sub ~f:(fun v -> printf "%.6f\n" v);
    [%expect {|
      0.666667
      1.000000
      1.000000
      1.333333
      |}]
  ;;

  (* ── quickcheck: sub-batch always matches full-batch ── *)

  let%test_unit "quickcheck: create_sub values match full batch for all evaluators" =
    let gen_region =
      let open Quickcheck.Generator.Let_syntax in
      let%bind samples_x = Int.gen_incl 1 16 in
      let%bind samples_y = Int.gen_incl 1 16 in
      let%bind start_x = Float.gen_incl (-10.) 10. in
      let%bind end_x = Float.gen_incl (-10.) 10. in
      let%bind start_y = Float.gen_incl (-10.) 10. in
      let%map end_y = Float.gen_incl (-10.) 10. in
      { Sample_region.start_x = Float32_u.of_float start_x
      ; end_x = Float32_u.of_float end_x
      ; start_y = Float32_u.of_float start_y
      ; end_y = Float32_u.of_float end_y
      ; samples_x
      ; samples_y
      }
    in
    let gen_sub_rect region =
      let open Quickcheck.Generator.Let_syntax in
      let sx = region.Sample_region.samples_x in
      let sy = region.Sample_region.samples_y in
      let%bind x0 = Int.gen_incl 0 (sx - 1) in
      let%bind y0 = Int.gen_incl 0 (sy - 1) in
      let%bind sub_sx = Int.gen_incl 1 (sx - x0) in
      let%map sub_sy = Int.gen_incl 1 (sy - y0) in
      x0, y0, sub_sx, sub_sy
    in
    Quickcheck.test
      (Quickcheck.Generator.bind gen_region ~f:(fun region ->
         Quickcheck.Generator.map (gen_sub_rect region) ~f:(fun rect -> region, rect)))
      ~sexp_of:[%sexp_of: Sample_region.t * (int * int * int * int)]
      ~trials:Quickcheck_trials.trials
      ~f:(fun (region, (x0, y0, samples_x, samples_y)) ->
        (* Use a tree that exercises arithmetic and coordinates. *)
        let tree = add (mul coord_x coord_x) (neg coord_y) in
        check_sub_matches_full tree region ~x0 ~y0 ~samples_x ~samples_y)
  ;;
end

module _ = Make_tests (Expr_graph_batch_eval)
module _ = Make_tests (Executor.Single_to_batch (Expr_graph_eval.Single))
module _ = Make_tests (Expr_tree_eval.Batch)
