open! Core

let make_grid ~width ~height ~(f : x:int -> y:int -> float32#) : float32# array =
  let n = width * height in
  let arr = Array.create ~len:n #0.0s in
  for i = 0 to n - 1 do
    arr.(i) <- f ~x:(i mod width) ~y:(i / width)
  done;
  arr
;;

let make_output ~width ~height : float32# array =
  Array.create ~len:(width * height * 2 * 4) #0.0s
;;

let pp_f32 (f : float32#) = Sexp.to_string (Float32_u.sexp_of_t f)

let print_lines (output : float32# array) count =
  for i = 0 to count - 1 do
    printf
      "  (%s, %s) -> (%s, %s)\n"
      (pp_f32 output.(i * 4))
      (pp_f32 output.((i * 4) + 1))
      (pp_f32 output.((i * 4) + 2))
      (pp_f32 output.((i * 4) + 3))
  done
;;

let%expect_test "uniform positive - no contour" =
  let w = 4
  and h = 4 in
  let input = make_grid ~width:w ~height:h ~f:(fun ~x:_ ~y:_ -> #1.0s) in
  let output = make_output ~width:w ~height:h in
  let count = March.run input output w h in
  printf "lines: %d\n" count;
  [%expect {| lines: 0 |}]
;;

let%expect_test "uniform negative - no contour" =
  let w = 4
  and h = 4 in
  let input = make_grid ~width:w ~height:h ~f:(fun ~x:_ ~y:_ -> Float32_u.neg #1.0s) in
  let output = make_output ~width:w ~height:h in
  let count = March.run input output w h in
  printf "lines: %d\n" count;
  [%expect {| lines: 0 |}]
;;

let%expect_test "vertical boundary" =
  let w = 4
  and h = 4 in
  let input =
    make_grid ~width:w ~height:h ~f:(fun ~x ~y:_ ->
      if x < 2 then Float32_u.neg #1.0s else #1.0s)
  in
  let output = make_output ~width:w ~height:h in
  let count = March.run input output w h in
  printf "lines: %d\n" count;
  print_lines output count;
  [%expect
    {|
    lines: 3
      (1.5, 0) -> (1.5, 1)
      (1.5, 1) -> (1.5, 2)
      (1.5, 2) -> (1.5, 3)
    |}]
;;

let%expect_test "horizontal boundary" =
  let w = 4
  and h = 4 in
  let input =
    make_grid ~width:w ~height:h ~f:(fun ~x:_ ~y ->
      if y < 2 then Float32_u.neg #1.0s else #1.0s)
  in
  let output = make_output ~width:w ~height:h in
  let count = March.run input output w h in
  printf "lines: %d\n" count;
  print_lines output count;
  [%expect
    {|
    lines: 3
      (1, 1.5) -> (0, 1.5)
      (2, 1.5) -> (1, 1.5)
      (3, 1.5) -> (2, 1.5)
    |}]
;;

let%expect_test "single negative cell in positive field" =
  let w = 3
  and h = 3 in
  let input =
    make_grid ~width:w ~height:h ~f:(fun ~x ~y ->
      if x = 1 && y = 1 then Float32_u.neg #1.0s else #1.0s)
  in
  let output = make_output ~width:w ~height:h in
  let count = March.run input output w h in
  printf "lines: %d\n" count;
  print_lines output count;
  [%expect
    {|
    lines: 4
      (0.5, 1) -> (1, 0.5)
      (1, 0.5) -> (1.5, 1)
      (1, 1.5) -> (0.5, 1)
      (1.5, 1) -> (1, 1.5)
    |}]
;;

let%expect_test "single positive cell in negative field" =
  let w = 3
  and h = 3 in
  let input =
    make_grid ~width:w ~height:h ~f:(fun ~x ~y ->
      if x = 1 && y = 1 then #1.0s else Float32_u.neg #1.0s)
  in
  let output = make_output ~width:w ~height:h in
  let count = March.run input output w h in
  printf "lines: %d\n" count;
  print_lines output count;
  [%expect
    {|
    lines: 4
      (1, 0.5) -> (0.5, 1)
      (1.5, 1) -> (1, 0.5)
      (0.5, 1) -> (1, 1.5)
      (1, 1.5) -> (1.5, 1)
    |}]
;;

let%expect_test "diagonal boundary" =
  let w = 5
  and h = 5 in
  let input =
    make_grid ~width:w ~height:h ~f:(fun ~x ~y ->
      if x + y < 4 then Float32_u.neg #1.0s else #1.0s)
  in
  let output = make_output ~width:w ~height:h in
  let count = March.run input output w h in
  printf "lines: %d\n" count;
  print_lines output count;
  [%expect
    {|
    lines: 7
      (3, 0.5) -> (2.5, 1)
      (3.5, 0) -> (3, 0.5)
      (2, 1.5) -> (1.5, 2)
      (2.5, 1) -> (2, 1.5)
      (1, 2.5) -> (0.5, 3)
      (1.5, 2) -> (1, 2.5)
      (0.5, 3) -> (0, 3.5)
    |}]
;;

let%expect_test "2x2 minimal grid - one corner negative" =
  let input : float32# array = [| Float32_u.neg #1.0s; #1.0s; #1.0s; #1.0s |] in
  let output = make_output ~width:2 ~height:2 in
  let count = March.run input output 2 2 in
  printf "lines: %d\n" count;
  print_lines output count;
  [%expect {|
    lines: 1
      (0.5, 0) -> (0, 0.5)
    |}]
;;

let%expect_test "2x2 minimal grid - all corners negative" =
  let input : float32# array =
    [| Float32_u.neg #1.0s
     ; Float32_u.neg #1.0s
     ; Float32_u.neg #1.0s
     ; Float32_u.neg #1.0s
    |]
  in
  let output = make_output ~width:2 ~height:2 in
  let count = March.run input output 2 2 in
  printf "lines: %d\n" count;
  [%expect {| lines: 0 |}]
;;

let%expect_test "checkerboard produces ambiguous cases" =
  let w = 3
  and h = 3 in
  let input =
    make_grid ~width:w ~height:h ~f:(fun ~x ~y ->
      if (x + y) mod 2 = 0 then Float32_u.neg #1.0s else #1.0s)
  in
  let output = make_output ~width:w ~height:h in
  let count = March.run input output w h in
  printf "lines: %d\n" count;
  print_lines output count;
  [%expect
    {|
    lines: 8
      (0.5, 1) -> (1, 0.5)
      (0.5, 0) -> (0, 0.5)
      (2, 0.5) -> (1.5, 0)
      (1, 0.5) -> (1.5, 1)
      (1, 1.5) -> (0.5, 1)
      (0, 1.5) -> (0.5, 2)
      (1.5, 2) -> (2, 1.5)
      (1.5, 1) -> (1, 1.5)
    |}]
;;

let%expect_test "varying sdf values affect interpolation" =
  (* Use non-uniform values so lerp produces different positions *)
  let input : float32# array = [| Float32_u.neg #2.0s; #1.0s; #1.0s; #1.0s |] in
  let output = make_output ~width:2 ~height:2 in
  let count = March.run input output 2 2 in
  printf "lines: %d\n" count;
  print_lines output count;
  (* Compare with uniform ±1 to show interpolation differs *)
  let input2 : float32# array = [| Float32_u.neg #1.0s; #1.0s; #1.0s; #1.0s |] in
  let output2 = make_output ~width:2 ~height:2 in
  let count2 = March.run input2 output2 2 2 in
  printf "lines: %d\n" count2;
  print_lines output2 count2;
  [%expect
    {|
    lines: 1
      (0.666666687, 0) -> (0, 0.666666687)
    lines: 1
      (0.5, 0) -> (0, 0.5)
    |}]
;;

(* ===== run_offset tests =====
   The contract: [run_offset grid out w h ~ox ~oy] is identical to [run] except
   that every emitted coordinate is shifted by (ox, oy).  In particular, marching
   a tile sub-grid with the tile's global origin as the offset must produce
   segments bitwise-identical to the corresponding segments of a dense [run] over
   the full grid — which is what lets [line_join] stitch segments across tile
   seams by exact point equality. *)

let%expect_test "run_offset ox=0 oy=0 equals run" =
  let w = 4 and h = 4 in
  let input =
    make_grid ~width:w ~height:h ~f:(fun ~x ~y:_ ->
      if x < 2 then Float32_u.neg #1.0s else #1.0s)
  in
  let out_run = make_output ~width:w ~height:h in
  let out_off = make_output ~width:w ~height:h in
  let count_run = March.run input out_run w h in
  let count_off = March.run_offset input out_off w h ~ox:0 ~oy:0 in
  printf "run lines: %d, offset lines: %d\n" count_run count_off;
  (* Verify bitwise equality of all emitted coordinates. *)
  let equal =
    count_run = count_off
    && (let n = count_run * 4 in
        let rec check i =
          if i >= n
          then true
          else (
            let a = Float32_u.to_float out_run.(i) in
            let b = Float32_u.to_float out_off.(i) in
            Int32.equal (Int32.bits_of_float a) (Int32.bits_of_float b) && check (i + 1))
        in
        check 0)
  in
  printf "bitwise equal: %b\n" equal;
  [%expect {|
    run lines: 3, offset lines: 3
    bitwise equal: true
    |}]
;;

let%expect_test "run_offset translates segments by (ox, oy)" =
  (* A 2x2 one-cell grid with one negative corner: the segment is at
     (0.5, 0) -> (0, 0.5) under run.  With ox=10 oy=20 it should be
     (10.5, 20) -> (10, 20.5). *)
  let input : float32# array = [| Float32_u.neg #1.0s; #1.0s; #1.0s; #1.0s |] in
  let output = make_output ~width:2 ~height:2 in
  let count = March.run_offset input output 2 2 ~ox:10 ~oy:20 in
  printf "lines: %d\n" count;
  print_lines output count;
  [%expect {|
    lines: 1
      (10.5, 20) -> (10, 20.5)
    |}]
;;

let%expect_test "run_offset: tile of full grid yields bitwise-identical segments" =
  (* Build a 4x4 full grid with a vertical boundary at x=2.
     Then extract the left 3x4 tile (ox=0,oy=0) and the right 3x4 tile (ox=2,oy=0),
     each from their respective sub-arrays.  Segments shared at x=2 must be
     bitwise identical between the two partial runs and the full run. *)
  let w = 4 and h = 4 in
  let full =
    make_grid ~width:w ~height:h ~f:(fun ~x ~y:_ ->
      if x < 2 then Float32_u.neg #1.0s else #1.0s)
  in
  (* Full run *)
  let out_full = make_output ~width:w ~height:h in
  let count_full = March.run full out_full w h in
  (* Left tile: columns 0..2 (width=3), no x-offset *)
  let left_w = 3 in
  let left =
    make_grid ~width:left_w ~height:h ~f:(fun ~x ~y ->
      full.((y * w) + x))
  in
  let out_left = make_output ~width:left_w ~height:h in
  let count_left = March.run_offset left out_left left_w h ~ox:0 ~oy:0 in
  (* Right tile: columns 2..3 (width=2), x-offset=2 *)
  let right_w = 2 in
  let right =
    make_grid ~width:right_w ~height:h ~f:(fun ~x ~y ->
      full.((y * w) + (x + 2)))
  in
  let out_right = make_output ~width:right_w ~height:h in
  let count_right = March.run_offset right out_right right_w h ~ox:2 ~oy:0 in
  printf "full: %d  left: %d  right: %d\n" count_full count_left count_right;
  (* The boundary segments (at x=1.5 in local coords, or x=2..2 in global) are the
     ones emitted by both the left tile and the full run at x=1.5 local = x=1.5
     in full (column 1->2 boundary).  Print them for comparison. *)
  printf "full segments:\n";
  print_lines out_full count_full;
  printf "left tile segments:\n";
  print_lines out_left count_left;
  printf "right tile segments:\n";
  print_lines out_right count_right;
  [%expect {|
    full: 3  left: 3  right: 0
    full segments:
      (1.5, 0) -> (1.5, 1)
      (1.5, 1) -> (1.5, 2)
      (1.5, 2) -> (1.5, 3)
    left tile segments:
      (1.5, 0) -> (1.5, 1)
      (1.5, 1) -> (1.5, 2)
      (1.5, 2) -> (1.5, 3)
    right tile segments:
    |}]
;;

let%expect_test "run_offset: large offset preserves segment structure" =
  (* A 3x3 diagonal-boundary grid run at offset (100, 200).
     Segment coordinates should equal the zero-offset coords + (100, 200). *)
  let w = 3 and h = 3 in
  let input =
    make_grid ~width:w ~height:h ~f:(fun ~x ~y ->
      if x + y < 2 then Float32_u.neg #1.0s else #1.0s)
  in
  let out0 = make_output ~width:w ~height:h in
  let count0 = March.run input out0 w h in
  let outN = make_output ~width:w ~height:h in
  let countN = March.run_offset input outN w h ~ox:100 ~oy:200 in
  printf "zero-offset lines: %d, offset lines: %d\n" count0 countN;
  (* Every segment from the offset run should equal the zero-offset run's
     coordinates shifted by (100, 200). *)
  let all_shifted =
    count0 = countN
    && (let ok = ref true in
        for i = 0 to count0 - 1 do
          let x1_0 = Float32_u.to_float out0.(i * 4 + 0) in
          let y1_0 = Float32_u.to_float out0.(i * 4 + 1) in
          let x2_0 = Float32_u.to_float out0.(i * 4 + 2) in
          let y2_0 = Float32_u.to_float out0.(i * 4 + 3) in
          let x1_n = Float32_u.to_float outN.(i * 4 + 0) in
          let y1_n = Float32_u.to_float outN.(i * 4 + 1) in
          let x2_n = Float32_u.to_float outN.(i * 4 + 2) in
          let y2_n = Float32_u.to_float outN.(i * 4 + 3) in
          (* Allow tiny float rounding but the offset is an exact integer *)
          if Float.(abs (x1_n - (x1_0 + 100.)) > 1e-4
                    || abs (y1_n - (y1_0 + 200.)) > 1e-4
                    || abs (x2_n - (x2_0 + 100.)) > 1e-4
                    || abs (y2_n - (y2_0 + 200.)) > 1e-4)
          then ok := false
        done;
        !ok)
  in
  printf "all correctly shifted: %b\n" all_shifted;
  [%expect {|
    zero-offset lines: 3, offset lines: 3
    all correctly shifted: true
    |}]
;;

let%expect_test "run_offset: bitwise identity - tile boundary shared vertex" =
  (* The doc says: 'marching a tile of a larger grid produces segments bitwise
     identical to the corresponding segments of a dense run over the whole grid.'
     Verify this for the shared edge at column 2 of a 4-wide grid. *)
  let w = 4 and h = 3 in
  let full =
    make_grid ~width:w ~height:h ~f:(fun ~x ~y:_ ->
      if x < 2 then Float32_u.neg #1.0s else #1.0s)
  in
  let out_full = make_output ~width:w ~height:h in
  let count_full = March.run full out_full w h in
  (* Right tile: columns 2..3 run at offset ox=2 *)
  let tile_w = 2 in
  let tile =
    make_grid ~width:tile_w ~height:h ~f:(fun ~x ~y ->
      full.((y * w) + (x + 2)))
  in
  let out_tile = make_output ~width:tile_w ~height:h in
  let count_tile = March.run_offset tile out_tile tile_w h ~ox:2 ~oy:0 in
  (* Find the segments at x1=1.5 (full) and x1=1.5 (tile with ox=0) — actually
     tile at ox=2 has no boundary because both columns are positive.
     The left tile: columns 0..2 run at offset ox=0 *)
  let ltile_w = 3 in
  let ltile =
    make_grid ~width:ltile_w ~height:h ~f:(fun ~x ~y ->
      full.((y * w) + x))
  in
  let out_ltile = make_output ~width:ltile_w ~height:h in
  let count_ltile = March.run_offset ltile out_ltile ltile_w h ~ox:0 ~oy:0 in
  (* The boundary segments from full and left-tile must be bitwise identical.
     Both emit vertical segments at x=1.5, crossing from y=0 to y=2. *)
  (* Collect boundary segments (x1 = 1.5) from full run *)
  let segs_of out count =
    Array.init count ~f:(fun i ->
      ( Float32_u.to_float out.(i * 4 + 0)
      , Float32_u.to_float out.(i * 4 + 1)
      , Float32_u.to_float out.(i * 4 + 2)
      , Float32_u.to_float out.(i * 4 + 3) ))
  in
  let boundary_segs segs =
    Array.filter segs ~f:(fun (x1, _, x2, _) ->
      Float.(abs (x1 - 1.5) < 0.01 && abs (x2 - 1.5) < 0.01))
  in
  let full_segs = boundary_segs (segs_of out_full count_full) in
  let ltile_segs = boundary_segs (segs_of out_ltile count_ltile) in
  let right_segs = segs_of out_tile count_tile in
  printf "full boundary count: %d\n" (Array.length full_segs);
  printf "left-tile boundary count: %d\n" (Array.length ltile_segs);
  printf "right-tile (all): %d\n" (Array.length right_segs);
  let all_match =
    Array.length full_segs = Array.length ltile_segs
    && Array.for_all2_exn full_segs ltile_segs ~f:(fun (a1, a2, a3, a4) (b1, b2, b3, b4) ->
         let bits_eq a b =
           Int32.equal (Int32.bits_of_float a) (Int32.bits_of_float b)
         in
         bits_eq a1 b1 && bits_eq a2 b2 && bits_eq a3 b3 && bits_eq a4 b4)
  in
  printf "boundary segments bitwise identical: %b\n" all_match;
  [%expect {|
    full boundary count: 2
    left-tile boundary count: 2
    right-tile (all): 0
    boundary segments bitwise identical: true
    |}]
;;
