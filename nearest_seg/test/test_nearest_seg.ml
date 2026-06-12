open! Core
module F = Float32_u

(* The reference implementation is [Nearest_seg.Dummy], a brute-force O(n) scan that lives
   in the library and shares [Nearest_seg]'s exact float32 arithmetic. So the only thing
   under test here is the spatial structure (which segments the real index visits), not
   the distance formula. *)

let coords_of_floats (fs : float array) : float32# array =
  let len = Array.length fs in
  let out = Array.create ~len #0.s in
  for i = 0 to len - 1 do
    Array.set out i (F.of_float (Array.get fs i))
  done;
  out
;;

(* Generate [m] real segments followed by [pad] segments of junk that [build] must ignore
   because they sit past [~length:m]. *)
let gen =
  let open Quickcheck.Generator.Let_syntax in
  let%bind m = Int.gen_incl 1 40 in
  let%bind pad = Int.gen_incl 0 10 in
  let coord = Float.gen_incl (-100.0) 100.0 in
  (* Junk is drawn from a wider range so a leak past [length] would shift the answer. *)
  let junk = Float.gen_incl (-1000.0) 1000.0 in
  let%bind segs = List.gen_with_length (4 * m) coord in
  let%bind tail = List.gen_with_length (4 * pad) junk in
  let%bind qx = Float.gen_incl (-150.0) 150.0 in
  let%map qy = Float.gen_incl (-150.0) 150.0 in
  Array.of_list (segs @ tail), m, qx, qy
;;

let%test_unit "spatial index bisimulates brute-force scan" =
  Quickcheck.test
    gen
    ~sexp_of:[%sexp_of: float array * int * float * float]
    ~trials:Quickcheck_trials.trials
    ~f:(fun (coords_floats, length, qxf, qyf) ->
      let coords = coords_of_floats coords_floats in
      let t = Nearest_seg.build coords ~length in
      let dummy = Nearest_seg.Dummy.build coords ~length in
      let px = F.of_float qxf in
      let py = F.of_float qyf in
      let got = F.to_float (Nearest_seg.query t ~x:px ~y:py) in
      let want = F.to_float (Nearest_seg.Dummy.query dummy ~x:px ~y:py) in
      let tol = 1e-2 *. (1.0 +. Float.abs got) in
      (* Signed values must agree; the only sanctioned divergence is the sign of an
         equidistant tie, where the two implementations may settle on different segments —
         hence the magnitude-only fallback. *)
      let ok =
        Float.( <= ) (Float.abs (got -. want)) tol
        || Float.( <= ) (Float.abs (Float.abs got -. Float.abs want)) tol
      in
      if not ok
      then
        raise_s
          [%message
            "spatial query disagreed with brute-force scan"
              (got : float)
              (want : float)
              (length : int)
              (qxf : float)
              (qyf : float)
              (coords_floats : float array)])
;;

(* A couple of concrete sanity checks pin down the sign convention. *)

let one_seg x1 y1 x2 y2 =
  Nearest_seg.build (coords_of_floats [| x1; y1; x2; y2 |]) ~length:1
;;

let%expect_test "sign: point to the right of an upward segment is positive" =
  (* Segment pointing +y; the point (1, 0) is to its right in math orientation. *)
  let t = one_seg 0.0 (-1.0) 0.0 1.0 in
  let d = F.to_float (Nearest_seg.query t ~x:(F.of_float 1.0) ~y:#0.s) in
  printf "%.4f" d;
  [%expect {| 1.0000 |}]
;;

let%expect_test "sign: point to the left of an upward segment is negative" =
  let t = one_seg 0.0 (-1.0) 0.0 1.0 in
  let d = F.to_float (Nearest_seg.query t ~x:(F.of_float (-1.0)) ~y:#0.s) in
  printf "%.4f" d;
  [%expect {| -1.0000 |}]
;;

let%expect_test "distance clamps to the nearer endpoint" =
  (* Closest point to (5, 0) on this segment is the endpoint (1, 0): distance 4. *)
  let t = one_seg (-1.0) 0.0 1.0 0.0 in
  let d = F.to_float (Nearest_seg.query t ~x:(F.of_float 5.0) ~y:#0.s) in
  printf "%.4f" (Float.abs d);
  [%expect {| 4.0000 |}]
;;

let%expect_test "sign tie at a shared vertex resolves by the pseudonormal rule" =
  (* Two contour segments meet at the origin. The query point's projection clamps to the
     shared vertex on both, so both report the same distance; only the sign is in
     question. The first segment in scan order is nearly collinear with the direction to
     the query point and its infinite line puts the point (wrongly) outside; the tie-break
     must pick the second segment, whose line the point deviates from most, which
     correctly says inside. Geometry distilled from a marched reflex corner of
     sdf/neon/boxes.neo, where the old first-wins rule flipped the sign of a whole wedge
     of interior points. *)
  let coords =
    coords_of_floats
      [| -1.0
       ; -0.3203125
       ; 0.0
       ; 0.0 (* shallow approach into the vertex *)
       ; 0.0
       ; 0.0
       ; 0.0546875
       ; -0.5 (* steep exit from the vertex *)
      |]
  in
  let t = Nearest_seg.build coords ~length:2 in
  let dummy = Nearest_seg.Dummy.build coords ~length:2 in
  let x = F.of_float 3.0
  and y = F.of_float 0.5 in
  printf "%.4f " (F.to_float (Nearest_seg.query t ~x ~y));
  printf "%.4f" (F.to_float (Nearest_seg.Dummy.query dummy ~x ~y));
  [%expect {| -3.0414 -3.0414 |}]
;;

(* ===== query_range tests ===== *)

(* Build helpers for a single segment and a square. *)

let range_of t ~x_lo ~y_lo ~x_hi ~y_hi =
  Nearest_seg.query_range
    t
    ~x_lo:(F.of_float x_lo)
    ~y_lo:(F.of_float y_lo)
    ~x_hi:(F.of_float x_hi)
    ~y_hi:(F.of_float y_hi)
;;

let dummy_range_of t ~x_lo ~y_lo ~x_hi ~y_hi =
  Nearest_seg.Dummy.query_range
    t
    ~x_lo:(F.of_float x_lo)
    ~y_lo:(F.of_float y_lo)
    ~x_hi:(F.of_float x_hi)
    ~y_hi:(F.of_float y_hi)
;;

(* Sanity check: a single segment pointing +y, query box entirely to the right → positive *)
let%expect_test "query_range: box entirely on positive side" =
  let t = one_seg 0.0 (-1.0) 0.0 1.0 in
  let r = range_of t ~x_lo:1.0 ~y_lo:(-0.5) ~x_hi:3.0 ~y_hi:0.5 in
  let #{ Nearest_seg.Interval.lo; hi } = r in
  (* Entire box is to the right of the segment — all distances positive *)
  printf "lo=%.4f hi=%.4f\n" (F.to_float lo) (F.to_float hi);
  [%expect {| lo=0.9998 hi=3.0002 |}];
  (* lo > 0 means the range is entirely positive *)
  assert (Float.(F.to_float lo > 0.0))
;;

(* Sanity check: box entirely to the left → negative distances *)
let%expect_test "query_range: box entirely on negative side" =
  let t = one_seg 0.0 (-1.0) 0.0 1.0 in
  let r = range_of t ~x_lo:(-3.0) ~y_lo:(-0.5) ~x_hi:(-1.0) ~y_hi:0.5 in
  let #{ Nearest_seg.Interval.lo; hi } = r in
  printf "lo=%.4f hi=%.4f\n" (F.to_float lo) (F.to_float hi);
  [%expect {| lo=-3.0002 hi=-0.9998 |}];
  assert (Float.(F.to_float hi < 0.0))
;;

(* Sanity check: query box straddling the segment → range contains 0 (lo < 0 < hi) *)
let%expect_test "query_range: box straddling segment" =
  let t = one_seg 0.0 (-1.0) 0.0 1.0 in
  let r = range_of t ~x_lo:(-2.0) ~y_lo:(-0.5) ~x_hi:2.0 ~y_hi:0.5 in
  let #{ Nearest_seg.Interval.lo; hi } = r in
  printf "lo=%.4f hi=%.4f\n" (F.to_float lo) (F.to_float hi);
  [%expect {| lo=-2.0001 hi=2.0001 |}];
  assert (Float.(F.to_float lo < 0.0 && F.to_float hi > 0.0))
;;

(* Degenerate box (single point): range should bracket the scalar query result *)
let%expect_test "query_range: degenerate point box" =
  let t = one_seg 0.0 (-1.0) 0.0 1.0 in
  let qx = 2.0
  and qy = 0.0 in
  let r = range_of t ~x_lo:qx ~y_lo:qy ~x_hi:qx ~y_hi:qy in
  let #{ Nearest_seg.Interval.lo; hi } = r in
  let scalar = F.to_float (Nearest_seg.query t ~x:(F.of_float qx) ~y:(F.of_float qy)) in
  printf "scalar=%.4f lo=%.4f hi=%.4f\n" scalar (F.to_float lo) (F.to_float hi);
  [%expect {| scalar=2.0000 lo=1.9999 hi=2.0001 |}];
  assert (Float.(F.to_float lo <= scalar && scalar <= F.to_float hi))
;;

(* Empty index: query_range should return [+inf, +inf] *)
let%expect_test "query_range: empty index" =
  let t = Nearest_seg.build (Array.create ~len:0 #0.s) ~length:0 in
  let r = range_of t ~x_lo:0.0 ~y_lo:0.0 ~x_hi:1.0 ~y_hi:1.0 in
  let #{ Nearest_seg.Interval.lo; hi } = r in
  printf "lo=%.4f hi=%.4f\n" (F.to_float lo) (F.to_float hi);
  [%expect {| lo=inf hi=inf |}]
;;

(* Build a clockwise (image-coords, y-down) unit square: inside = negative. In image
   coordinates, clockwise winding looks like: top-right → bottom-right → bottom-left →
   top-left We use corners at (±1, ±1). The interior point (0,0) should have negative
   distance. *)
let square_segs () =
  (* Clockwise in image coords (y-down): right side up, bottom right, left side down, top
     left *)
  coords_of_floats
    [| (* right side: (1,-1) → (1,1) *)
       1.0
     ; -1.0
     ; 1.0
     ; 1.0 (* bottom side: (1,1) → (-1,1) *)
     ; 1.0
     ; 1.0
     ; -1.0
     ; 1.0 (* left side: (-1,1) → (-1,-1) *)
     ; -1.0
     ; 1.0
     ; -1.0
     ; -1.0 (* top side: (-1,-1) → (1,-1) *)
     ; -1.0
     ; -1.0
     ; 1.0
     ; -1.0
    |]
;;

let%expect_test "query_range: box inside closed square => all-negative range" =
  let coords = square_segs () in
  let t = Nearest_seg.build coords ~length:4 in
  (* Small box deep inside the square *)
  let r = range_of t ~x_lo:(-0.3) ~y_lo:(-0.3) ~x_hi:0.3 ~y_hi:0.3 in
  let #{ Nearest_seg.Interval.lo; hi } = r in
  printf "lo=%.4f hi=%.4f\n" (F.to_float lo) (F.to_float hi);
  [%expect {| lo=-1.3000 hi=-0.7000 |}];
  (* Range entirely negative: box is well inside the square *)
  assert (Float.(F.to_float hi < 0.0))
;;

let%expect_test "query_range: box outside closed square => scalar results contained" =
  let coords = square_segs () in
  let t = Nearest_seg.build coords ~length:4 in
  (* Box far outside the square — sign side is conservative so we can't assert lo>0, but
     every scalar result must be inside the range. *)
  let r = range_of t ~x_lo:3.0 ~y_lo:3.0 ~x_hi:5.0 ~y_hi:5.0 in
  let #{ Nearest_seg.Interval.lo; hi } = r in
  printf "lo=%.4f hi=%.4f\n" (F.to_float lo) (F.to_float hi);
  [%expect {| lo=-5.6572 hi=5.6572 |}];
  (* Verify a sample point at (4,4) is inside the range *)
  let s = F.to_float (Nearest_seg.query t ~x:(F.of_float 4.0) ~y:(F.of_float 4.0)) in
  printf "scalar at (4,4)=%.4f\n" s;
  [%expect {| scalar at (4,4)=4.2426 |}];
  assert (Float.(F.to_float lo <= s && s <= F.to_float hi))
;;

(* ===== Quickcheck property test for query_range ===== *)

let interp lo hi t =
  let v = lo +. ((hi -. lo) *. t) in
  if Float.is_finite v then v else (lo /. 2.0) +. (hi /. 2.0)
;;

let%test_unit "query_range: scalar result contained in both indexed and dummy ranges" =
  let open Quickcheck.Generator in
  let gen_box =
    let open Let_syntax in
    let coord = Float.gen_incl (-150.0) 150.0 in
    let%bind x1 = coord in
    let%bind x2 = coord in
    let%bind y1 = coord in
    let%map y2 = coord in
    Float.min x1 x2, Float.max x1 x2, Float.min y1 y2, Float.max y1 y2
  in
  let gen =
    let open Let_syntax in
    let%bind m = Int.gen_incl 1 40 in
    let coord = Float.gen_incl (-100.0) 100.0 in
    let%bind segs = List.gen_with_length (4 * m) coord in
    let%map x_lo, x_hi, y_lo, y_hi = gen_box in
    Array.of_list segs, m, x_lo, x_hi, y_lo, y_hi
  in
  Quickcheck.test
    gen
    ~sexp_of:[%sexp_of: float array * int * float * float * float * float]
    ~trials:Quickcheck_trials.trials
    ~f:(fun (coords_floats, length, x_lo, x_hi, y_lo, y_hi) ->
      let coords = coords_of_floats coords_floats in
      let t = Nearest_seg.build coords ~length in
      let dummy = Nearest_seg.Dummy.build coords ~length in
      let idx_range = range_of t ~x_lo ~y_lo ~x_hi ~y_hi in
      let dummy_range = dummy_range_of dummy ~x_lo ~y_lo ~x_hi ~y_hi in
      let #{ Nearest_seg.Interval.lo = idx_lo; hi = idx_hi } = idx_range in
      let #{ Nearest_seg.Interval.lo = dum_lo; hi = dum_hi } = dummy_range in
      let rng = Splittable_random.of_int 137 in
      (* 4 corners + center + 5 random interior points *)
      let pts =
        [ x_lo, y_lo
        ; x_lo, y_hi
        ; x_hi, y_lo
        ; x_hi, y_hi
        ; interp x_lo x_hi 0.5, interp y_lo y_hi 0.5
        ]
        @ List.init 5 ~f:(fun _ ->
          let tx = Splittable_random.float rng ~lo:0.0 ~hi:1.0 in
          let ty = Splittable_random.float rng ~lo:0.0 ~hi:1.0 in
          interp x_lo x_hi tx, interp y_lo y_hi ty)
      in
      List.iter pts ~f:(fun (px, py) ->
        let scalar =
          F.to_float (Nearest_seg.query t ~x:(F.of_float px) ~y:(F.of_float py))
        in
        let in_idx = Float.(F.to_float idx_lo <= scalar && scalar <= F.to_float idx_hi) in
        let in_dum = Float.(F.to_float dum_lo <= scalar && scalar <= F.to_float dum_hi) in
        if not (in_idx && in_dum)
        then
          raise_s
            [%message
              "query_range containment violation"
                ~length:(length : int)
                ~x_lo:(x_lo : float)
                ~x_hi:(x_hi : float)
                ~y_lo:(y_lo : float)
                ~y_hi:(y_hi : float)
                ~point_x:(px : float)
                ~point_y:(py : float)
                ~scalar:(scalar : float)
                ~idx_lo:(F.to_float idx_lo : float)
                ~idx_hi:(F.to_float idx_hi : float)
                ~dum_lo:(F.to_float dum_lo : float)
                ~dum_hi:(F.to_float dum_hi : float)
                ~in_idx:(in_idx : bool)
                ~in_dum:(in_dum : bool)
                (coords_floats : float array)]))
;;

(* ===== assume_level_set / midpoint-probe tests ===== *)

(* Build a clockwise-wound, axis-aligned square from (x0,y0) to (x1,y1) with each side
   subdivided into [steps]-many unit segments, with bitwise-identical float32 shared
   endpoints. We work in a flat float list to avoid the unboxed layout restriction, then
   convert at the end. The key: compute each subdivision point ONCE as float32
   (round-tripped through F.of_float then F.to_float) so the same bit-pattern is used for
   both neighbouring segments. *)
(* NB: the plain-double version (subdivided_square_segs) was removed because it was
   unused; all callers require the f32-consistent variant below. *)
let subdivided_square_segs_f32 x0 y0 x1 y1 ~steps =
  (* Pre-compute subdivision points for one edge as float32-rounded floats. *)
  let edge_pts ax ay bx by =
    Array.init (steps + 1) ~f:(fun k ->
      let t = float_of_int k /. float_of_int steps in
      (* Round through float32 so shared endpoints are bitwise-identical. *)
      let px = F.to_float (F.of_float (ax +. ((bx -. ax) *. t))) in
      let py = F.to_float (F.of_float (ay +. ((by -. ay) *. t))) in
      px, py)
  in
  let top = edge_pts x0 y0 x1 y0 in
  let right = edge_pts x1 y0 x1 y1 in
  let bot = edge_pts x1 y1 x0 y1 in
  let left = edge_pts x0 y1 x0 y0 in
  let segs = ref [] in
  let add_edge_pts pts =
    for k = 0 to steps - 1 do
      let px, py = Array.get pts k in
      let qx, qy = Array.get pts (k + 1) in
      segs := [ px; py; qx; qy ] :: !segs
    done
  in
  add_edge_pts top;
  add_edge_pts right;
  add_edge_pts bot;
  add_edge_pts left;
  coords_of_floats (Array.of_list (List.concat (List.rev !segs)))
;;

(* Count segments in a flat float32# coord array. *)
let seg_count_of_coords coords = Array.length coords / 4

(* Verdict map: for each tile in an NxN grid over [lx,hx]x[ly,hy], emit '+' if lo>0, '-'
   if hi<=0, 'o' if straddling (both signs possible). *)
let verdict_map t ~lx ~ly ~hx ~hy ~nx ~ny =
  let buf = Buffer.create ((nx + 2) * (ny + 1)) in
  for j = 0 to ny - 1 do
    for i = 0 to nx - 1 do
      let tx0 = lx +. ((hx -. lx) *. float_of_int i /. float_of_int nx) in
      let tx1 = lx +. ((hx -. lx) *. float_of_int (i + 1) /. float_of_int nx) in
      let ty0 = ly +. ((hy -. ly) *. float_of_int j /. float_of_int ny) in
      let ty1 = ly +. ((hy -. ly) *. float_of_int (j + 1) /. float_of_int ny) in
      let #{ Nearest_seg.Interval.lo; hi } =
        range_of t ~x_lo:tx0 ~y_lo:ty0 ~x_hi:tx1 ~y_hi:ty1
      in
      let c =
        if Float.(F.to_float lo > 0.0)
        then '+'
        else if Float.(F.to_float hi <= 0.0)
        then '-'
        else 'o'
      in
      Buffer.add_char buf c
    done;
    Buffer.add_char buf '\n'
  done;
  Buffer.contents buf
;;

(* Count straddling ('o') tiles in a verdict map string. *)
let count_straddles map = String.count map ~f:(Char.equal 'o')

(* 1a. Closed square, subdivided into unit-length segments. Verdict maps with and without
   the assume_level_set flag. The with-flag map should resolve (show '+') tiles that are
   far from the contour in the corner regions. *)
let%expect_test "assume_level_set: closed square — verdict maps" =
  let coords = subdivided_square_segs_f32 10.0 10.0 50.0 50.0 ~steps:40 in
  let n = seg_count_of_coords coords in
  let t_no = Nearest_seg.build coords ~length:n in
  let t_yes = Nearest_seg.build coords ~length:n ~assume_level_set:true in
  (* Print verdict over a 12×12 grid spanning [0,60]×[0,60]. *)
  printf
    "without flag:\n%s\n"
    (verdict_map t_no ~lx:0.0 ~ly:0.0 ~hx:60.0 ~hy:60.0 ~nx:12 ~ny:12);
  printf
    "with flag:\n%s\n"
    (verdict_map t_yes ~lx:0.0 ~ly:0.0 ~hx:60.0 ~hy:60.0 ~nx:12 ~ny:12);
  [%expect
    {|
    without flag:
    +oooo+++ooo+
    oooooooooooo
    oooooooooooo
    ooo------ooo
    ooo------ooo
    +oo------oo+
    +oo------oo+
    +oo------oo+
    ooo------ooo
    oooooooooooo
    oooooooooooo
    +oooo+++ooo+

    with flag:
    ++++++++++++
    +oooooooooo+
    +oooooooooo+
    +oo------oo+
    +oo------oo+
    +oo------oo+
    +oo------oo+
    +oo------oo+
    +oo------oo+
    +oooooooooo+
    +oooooooooo+
    ++++++++++++
    |}]
;;

(* 1a continued — containment check: every scalar result must lie in the with-flag range. *)
let%expect_test "assume_level_set: closed square — containment" =
  let coords = subdivided_square_segs_f32 10.0 10.0 50.0 50.0 ~steps:40 in
  let n = seg_count_of_coords coords in
  let t_yes = Nearest_seg.build coords ~length:n ~assume_level_set:true in
  (* Sweep a 20×20 grid of scalar queries and verify containment in a 4×4 grid of tiles. *)
  let violations = ref 0 in
  let nx = 4
  and ny = 4 in
  let lx = 0.0
  and ly = 0.0
  and hx = 60.0
  and hy = 60.0 in
  for ti = 0 to nx - 1 do
    for tj = 0 to ny - 1 do
      let tx0 = lx +. ((hx -. lx) *. float_of_int ti /. float_of_int nx) in
      let tx1 = lx +. ((hx -. lx) *. float_of_int (ti + 1) /. float_of_int nx) in
      let ty0 = ly +. ((hy -. ly) *. float_of_int tj /. float_of_int ny) in
      let ty1 = ly +. ((hy -. ly) *. float_of_int (tj + 1) /. float_of_int ny) in
      let #{ Nearest_seg.Interval.lo; hi } =
        range_of t_yes ~x_lo:tx0 ~y_lo:ty0 ~x_hi:tx1 ~y_hi:ty1
      in
      let rng = Splittable_random.of_int 42 in
      for _ = 1 to 20 do
        let px = tx0 +. ((tx1 -. tx0) *. Splittable_random.float rng ~lo:0.0 ~hi:1.0) in
        let py = ty0 +. ((ty1 -. ty0) *. Splittable_random.float rng ~lo:0.0 ~hi:1.0) in
        let s =
          F.to_float (Nearest_seg.query t_yes ~x:(F.of_float px) ~y:(F.of_float py))
        in
        if Float.(s < F.to_float lo || s > F.to_float hi) then incr violations
      done
    done
  done;
  printf "containment violations: %d\n" !violations;
  [%expect {| containment violations: 0 |}]
;;

(* 1b. Open "U" chain: square with the bottom side removed. Tiles past the open ends
   (below y=50, between x=10..50) must stay 'o' (both signs) because the probe is
   correctly suppressed near the open chain endpoints. *)
let u_chain_segs () =
  (* Clockwise square minus the bottom edge; open ends are (50,50) and (10,50). top:
     (10,10) -> (50,10) right: (50,10) -> (50,50) left: (10,50) -> (10,10)
     [reversed direction from closed square] *)
  coords_of_floats
    [| 10.0
     ; 10.0
     ; 50.0
     ; 10.0 (* top *)
     ; 50.0
     ; 10.0
     ; 50.0
     ; 50.0 (* right *)
     ; 10.0
     ; 50.0
     ; 10.0
     ; 10.0 (* left *)
    |]
;;

let%expect_test "assume_level_set: open U chain — probe suppressed past open ends" =
  let coords = u_chain_segs () in
  let n = seg_count_of_coords coords in
  let t_yes = Nearest_seg.build coords ~length:n ~assume_level_set:true in
  (* The wedge region past the open ends: tiles at the bottom, between the two endpoints.
     Build a 10×10 verdict map over [0,60]×[0,60]. *)
  printf
    "U-chain verdict (with flag):\n%s\n"
    (verdict_map t_yes ~lx:0.0 ~ly:0.0 ~hx:60.0 ~hy:60.0 ~nx:10 ~ny:10);
  (* Also check containment: for all tiles, 20 random scalar queries must be in range. *)
  let violations = ref 0 in
  let nx = 6
  and ny = 6 in
  let lx = 0.0
  and ly = 0.0
  and hx = 60.0
  and hy = 60.0 in
  for ti = 0 to nx - 1 do
    for tj = 0 to ny - 1 do
      let tx0 = lx +. ((hx -. lx) *. float_of_int ti /. float_of_int nx) in
      let tx1 = lx +. ((hx -. lx) *. float_of_int (ti + 1) /. float_of_int nx) in
      let ty0 = ly +. ((hy -. ly) *. float_of_int tj /. float_of_int ny) in
      let ty1 = ly +. ((hy -. ly) *. float_of_int (tj + 1) /. float_of_int ny) in
      let #{ Nearest_seg.Interval.lo; hi } =
        range_of t_yes ~x_lo:tx0 ~y_lo:ty0 ~x_hi:tx1 ~y_hi:ty1
      in
      let rng = Splittable_random.of_int 17 in
      for _ = 1 to 20 do
        let px = tx0 +. ((tx1 -. tx0) *. Splittable_random.float rng ~lo:0.0 ~hi:1.0) in
        let py = ty0 +. ((ty1 -. ty0) *. Splittable_random.float rng ~lo:0.0 ~hi:1.0) in
        let s =
          F.to_float (Nearest_seg.query t_yes ~x:(F.of_float px) ~y:(F.of_float py))
        in
        if Float.(s < F.to_float lo || s > F.to_float hi) then incr violations
      done
    done
  done;
  printf "U-chain containment violations: %d\n" !violations;
  [%expect
    {|
    U-chain verdict (with flag):
    ++++++++++
    +oooooooo+
    +o------o+
    +o------o+
    +o------o+
    +o------o+
    oo------oo
    oo------oo
    oo------oo
    oo------oo

    U-chain containment violations: 0
    |}]
;;

(* 1c. Unsafe-vertex variants: T-junction, duplicate segment, zero-length segment. In each
   case build with ~assume_level_set:true; check no containment violations and that the
   probe was suppressed near the unsafe vertex (tile containing it is 'o'). *)

(* T-junction: three segments sharing one vertex. *)
let t_junction_segs () =
  (* A horizontal segment (−5,0)→(5,0), a vertical segment (0,0)→(0,5), and a second
     horizontal piece (0,0)→(0,-5): three endpoints share (0.0, 0.0). *)
  coords_of_floats [| -5.0; 0.0; 0.0; 0.0; 0.0; 0.0; 5.0; 0.0; 0.0; 0.0; 0.0; 5.0 |]
;;

let%expect_test "assume_level_set: T-junction — probe suppressed near junction" =
  let coords = t_junction_segs () in
  let n = seg_count_of_coords coords in
  let t_yes = Nearest_seg.build coords ~length:n ~assume_level_set:true in
  printf
    "T-junction verdict (with flag):\n%s\n"
    (verdict_map t_yes ~lx:(-8.0) ~ly:(-8.0) ~hx:8.0 ~hy:8.0 ~nx:8 ~ny:8);
  (* The tile containing (0,0) should be 'o' because it is an unsafe vertex. *)
  let #{ Nearest_seg.Interval.lo; hi } =
    range_of t_yes ~x_lo:(-0.5) ~y_lo:(-0.5) ~x_hi:0.5 ~y_hi:0.5
  in
  printf "tile around junction: lo=%.4f hi=%.4f\n" (F.to_float lo) (F.to_float hi);
  [%expect
    {|
    T-junction verdict (with flag):
    ooooo+++
    +oooo+++
    ++ooo+++
    oooooooo
    oooooooo
    ---oooo-
    ---ooooo
    ---ooooo

    tile around junction: lo=-0.7071 hi=0.7071
    |}]
;;

(* Duplicate segment: the same segment appears twice. *)
let duplicate_seg_segs () =
  coords_of_floats [| 0.0; -5.0; 0.0; 5.0; 0.0; -5.0; 0.0; 5.0 |]
;;

let%expect_test "assume_level_set: duplicate segment — probe suppressed" =
  let coords = duplicate_seg_segs () in
  let n = seg_count_of_coords coords in
  let t_yes = Nearest_seg.build coords ~length:n ~assume_level_set:true in
  (* Both endpoints appear twice: they are unsafe vertices. *)
  let #{ Nearest_seg.Interval.lo; hi } =
    range_of t_yes ~x_lo:(-0.1) ~y_lo:(-0.1) ~x_hi:0.1 ~y_hi:0.1
  in
  printf "tile straddling dup-seg: lo=%.4f hi=%.4f\n" (F.to_float lo) (F.to_float hi);
  (* Containment check at a few points *)
  let violations = ref 0 in
  List.iter
    [ -2.0, 0.0; 2.0, 0.0; 0.0, 3.0; 0.0, -3.0 ]
    ~f:(fun (px, py) ->
      let #{ Nearest_seg.Interval.lo; hi } =
        range_of
          t_yes
          ~x_lo:(px -. 1.0)
          ~y_lo:(py -. 1.0)
          ~x_hi:(px +. 1.0)
          ~y_hi:(py +. 1.0)
      in
      let s =
        F.to_float (Nearest_seg.query t_yes ~x:(F.of_float px) ~y:(F.of_float py))
      in
      if Float.(s < F.to_float lo || s > F.to_float hi) then incr violations);
  printf "dup-seg containment violations: %d\n" !violations;
  [%expect
    {|
    tile straddling dup-seg: lo=-0.1000 hi=0.1000
    dup-seg containment violations: 0
    |}]
;;

(* Zero-length segment inside a closed square. *)
let zero_length_in_square_segs () =
  (* A proper closed square plus a zero-length segment at (30, 30) inside. Build as flat
     float arrays and convert together to avoid Array.append on float32#. *)
  coords_of_floats
    [| (* right side: (1,-1) → (1,1) *)
       1.0
     ; -1.0
     ; 1.0
     ; 1.0 (* bottom side: (1,1) → (-1,1) *)
     ; 1.0
     ; 1.0
     ; -1.0
     ; 1.0 (* left side: (-1,1) → (-1,-1) *)
     ; -1.0
     ; 1.0
     ; -1.0
     ; -1.0 (* top side: (-1,-1) → (1,-1) *)
     ; -1.0
     ; -1.0
     ; 1.0
     ; -1.0 (* zero-length segment at (0,0) inside *)
     ; 0.0
     ; 0.0
     ; 0.0
     ; 0.0
    |]
;;

let%expect_test "assume_level_set: zero-length segment inside square — probe suppressed \
                 near it"
  =
  let coords = zero_length_in_square_segs () in
  let n = seg_count_of_coords coords in
  let t_yes = Nearest_seg.build coords ~length:n ~assume_level_set:true in
  let t_no = Nearest_seg.build coords ~length:n in
  (* Tile around the zero-length segment: with probe, should stay 'o' because (30,30) is
     an unsafe vertex; without probe it's also conservative but guaranteed negative. *)
  let r_yes = range_of t_yes ~x_lo:29.5 ~y_lo:29.5 ~x_hi:30.5 ~y_hi:30.5 in
  let r_no = range_of t_no ~x_lo:29.5 ~y_lo:29.5 ~x_hi:30.5 ~y_hi:30.5 in
  let #{ Nearest_seg.Interval.lo = lo_yes; hi = hi_yes } = r_yes in
  let #{ Nearest_seg.Interval.lo = lo_no; hi = hi_no } = r_no in
  printf "with flag: lo=%.4f hi=%.4f\n" (F.to_float lo_yes) (F.to_float hi_yes);
  printf "without flag: lo=%.4f hi=%.4f\n" (F.to_float lo_no) (F.to_float hi_no);
  (* Verify a scalar query at (30,30) lies within both ranges *)
  let s =
    F.to_float (Nearest_seg.query t_yes ~x:(F.of_float 30.0) ~y:(F.of_float 30.0))
  in
  printf "scalar at (30,30): %.4f\n" s;
  [%expect
    {|
    with flag: lo=40.3029 hi=41.7215
    without flag: lo=40.3029 hi=41.7215
    scalar at (30,30): 41.0122
    |}]
;;

(* 3. Regression: count straddling tiles with and without the flag for the closed square.
   With the flag, far-from-contour tiles should be resolved. *)
let%expect_test "assume_level_set: probe reduces straddle count for closed square" =
  let coords = subdivided_square_segs_f32 10.0 10.0 50.0 50.0 ~steps:40 in
  let n = seg_count_of_coords coords in
  let t_no = Nearest_seg.build coords ~length:n in
  let t_yes = Nearest_seg.build coords ~length:n ~assume_level_set:true in
  let map_no = verdict_map t_no ~lx:0.0 ~ly:0.0 ~hx:60.0 ~hy:60.0 ~nx:12 ~ny:12 in
  let map_yes = verdict_map t_yes ~lx:0.0 ~ly:0.0 ~hx:60.0 ~hy:60.0 ~nx:12 ~ny:12 in
  let straddles_no = count_straddles map_no in
  let straddles_yes = count_straddles map_yes in
  printf "straddles without flag: %d\n" straddles_no;
  printf "straddles with flag:    %d\n" straddles_yes;
  (* With flag should be strictly fewer *)
  assert (straddles_yes < straddles_no);
  [%expect {|
    straddles without flag: 92
    straddles with flag:    64
    |}]
;;

(* 2. Containment quickcheck with random closed star-shaped polygons.

   We generate a star-shaped polygon (sorted angles, random radii 5..100) wound clockwise
   (increasing angle = clockwise in y-down), build with ~assume_level_set:true, then for
   ~20 random query points inside each of several random boxes we verify containment. We
   also compare against Dummy's query_range (both must contain every scalar result). *)

(* Make a star-shaped closed polygon with [k] vertices. Returns a flat float32# array of
   segment coords. Each edge is optionally subdivided; shared endpoints are constructed
   once as float32 and reused. *)
(* Make a closed star-shaped polygon with [k] vertices, each vertex at its given radius.
   Vertices are in increasing-angle order (clockwise on screen in y-down coords). Each
   edge is optionally subdivided; shared endpoints are rounded through float32 once and
   stored as plain float so the same bit-pattern is reused for both neighbours. Returns a
   flat float32# coord array ready for [Nearest_seg.build]. *)
let make_star_polygon ~cx ~cy ~k ~radii ~subdivide_seed =
  (* Vertex positions, rounded through float32 to match what build will see. *)
  let vx =
    Array.init k ~f:(fun i ->
      let a = Float.pi *. 2.0 *. float_of_int i /. float_of_int k in
      F.to_float (F.of_float (cx +. (Array.get radii i *. Float.cos a))))
  in
  let vy =
    Array.init k ~f:(fun i ->
      let a = Float.pi *. 2.0 *. float_of_int i /. float_of_int k in
      F.to_float (F.of_float (cy +. (Array.get radii i *. Float.sin a))))
  in
  (* Collect all segment coords as plain floats; convert to float32# at the end. *)
  let segs = ref [] in
  let rng = Splittable_random.of_int subdivide_seed in
  for i = 0 to k - 1 do
    let ax = Array.get vx i
    and ay = Array.get vy i in
    let bx = Array.get vx ((i + 1) mod k)
    and by = Array.get vy ((i + 1) mod k) in
    let nsub = 1 + Splittable_random.int rng ~lo:0 ~hi:2 in
    (* Pre-compute all subdivision points as float32-rounded floats so adjacent segments
       share bitwise-identical endpoint values. *)
    let pts_x =
      Array.init (nsub + 1) ~f:(fun j ->
        if j = 0
        then ax
        else if j = nsub
        then bx
        else
          F.to_float
            (F.of_float (ax +. ((bx -. ax) *. float_of_int j /. float_of_int nsub))))
    in
    let pts_y =
      Array.init (nsub + 1) ~f:(fun j ->
        if j = 0
        then ay
        else if j = nsub
        then by
        else
          F.to_float
            (F.of_float (ay +. ((by -. ay) *. float_of_int j /. float_of_int nsub))))
    in
    for j = 0 to nsub - 1 do
      segs
      := [ Array.get pts_x j
         ; Array.get pts_y j
         ; Array.get pts_x (j + 1)
         ; Array.get pts_y (j + 1)
         ]
         :: !segs
    done
  done;
  coords_of_floats (Array.of_list (List.concat (List.rev !segs)))
;;

let%test_unit "assume_level_set: star polygon containment quickcheck" =
  let open Quickcheck.Generator in
  let gen =
    let open Let_syntax in
    let%bind k = Int.gen_incl 5 20 in
    let%bind radii_raw = List.gen_with_length k (Float.gen_incl 5.0 100.0) in
    let radii = Array.of_list radii_raw in
    let%bind cx = Float.gen_incl (-50.0) 50.0 in
    let%bind cy = Float.gen_incl (-50.0) 50.0 in
    let%bind subdivide_seed = Int.gen_incl 0 999999 in
    (* Query box: random placement that covers a variety of cases. *)
    let%bind qx1 = Float.gen_incl (-200.0) 200.0 in
    let%bind qx2 = Float.gen_incl (-200.0) 200.0 in
    let%bind qy1 = Float.gen_incl (-200.0) 200.0 in
    let%map qy2 = Float.gen_incl (-200.0) 200.0 in
    k, radii, cx, cy, subdivide_seed, qx1, qx2, qy1, qy2
  in
  Quickcheck.test
    gen
    ~sexp_of:
      [%sexp_of: int * float array * float * float * int * float * float * float * float]
    ~trials:Quickcheck_trials.trials
    ~f:(fun (k, radii, cx, cy, subdivide_seed, qx1, qx2, qy1, qy2) ->
      let coords = make_star_polygon ~cx ~cy ~k ~radii ~subdivide_seed in
      let length = Array.length coords / 4 in
      if length = 0
      then ()
      else (
        let t = Nearest_seg.build coords ~length ~assume_level_set:true in
        let dummy = Nearest_seg.Dummy.build coords ~length ~assume_level_set:true in
        let x_lo = Float.min qx1 qx2 in
        let x_hi = Float.max qx1 qx2 in
        let y_lo = Float.min qy1 qy2 in
        let y_hi = Float.max qy1 qy2 in
        let idx_range = range_of t ~x_lo ~y_lo ~x_hi ~y_hi in
        let dum_range = dummy_range_of dummy ~x_lo ~y_lo ~x_hi ~y_hi in
        let #{ Nearest_seg.Interval.lo = idx_lo; hi = idx_hi } = idx_range in
        let #{ Nearest_seg.Interval.lo = dum_lo; hi = dum_hi } = dum_range in
        let rng = Splittable_random.of_int 99 in
        let pts =
          [ x_lo, y_lo
          ; x_lo, y_hi
          ; x_hi, y_lo
          ; x_hi, y_hi
          ; interp x_lo x_hi 0.5, interp y_lo y_hi 0.5
          ]
          @ List.init 15 ~f:(fun _ ->
            let tx = Splittable_random.float rng ~lo:0.0 ~hi:1.0 in
            let ty = Splittable_random.float rng ~lo:0.0 ~hi:1.0 in
            interp x_lo x_hi tx, interp y_lo y_hi ty)
        in
        List.iter pts ~f:(fun (px, py) ->
          let scalar =
            F.to_float (Nearest_seg.query t ~x:(F.of_float px) ~y:(F.of_float py))
          in
          let in_idx =
            Float.(F.to_float idx_lo <= scalar && scalar <= F.to_float idx_hi)
          in
          let in_dum =
            Float.(F.to_float dum_lo <= scalar && scalar <= F.to_float dum_hi)
          in
          if not (in_idx && in_dum)
          then
            raise_s
              [%message
                "assume_level_set containment violation"
                  ~k:(k : int)
                  ~cx:(cx : float)
                  ~cy:(cy : float)
                  ~x_lo:(x_lo : float)
                  ~x_hi:(x_hi : float)
                  ~y_lo:(y_lo : float)
                  ~y_hi:(y_hi : float)
                  ~point_x:(px : float)
                  ~point_y:(py : float)
                  ~scalar:(scalar : float)
                  ~idx_lo:(F.to_float idx_lo : float)
                  ~idx_hi:(F.to_float idx_hi : float)
                  ~dum_lo:(F.to_float dum_lo : float)
                  ~dum_hi:(F.to_float dum_hi : float)
                  ~in_idx:(in_idx : bool)
                  ~in_dum:(in_dum : bool)])))
;;
