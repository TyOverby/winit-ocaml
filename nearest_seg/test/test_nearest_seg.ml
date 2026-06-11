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
    ~trials:5000
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
     the query point and its infinite line puts the point (wrongly) outside; the
     tie-break must pick the second segment, whose line the point deviates from most,
     which correctly says inside. Geometry distilled from a marched reflex corner of
     sdf/neon/boxes.neo, where the old first-wins rule flipped the sign of a whole wedge
     of interior points. *)
  let coords =
    coords_of_floats
      [| -1.0; -0.3203125; 0.0; 0.0 (* shallow approach into the vertex *)
       ; 0.0; 0.0; 0.0546875; -0.5 (* steep exit from the vertex *)
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
  assert Float.(F.to_float lo > 0.0)
;;

(* Sanity check: box entirely to the left → negative distances *)
let%expect_test "query_range: box entirely on negative side" =
  let t = one_seg 0.0 (-1.0) 0.0 1.0 in
  let r = range_of t ~x_lo:(-3.0) ~y_lo:(-0.5) ~x_hi:(-1.0) ~y_hi:0.5 in
  let #{ Nearest_seg.Interval.lo; hi } = r in
  printf "lo=%.4f hi=%.4f\n" (F.to_float lo) (F.to_float hi);
  [%expect {| lo=-3.0002 hi=-0.9998 |}];
  assert Float.(F.to_float hi < 0.0)
;;

(* Sanity check: query box straddling the segment → range contains 0 (lo < 0 < hi) *)
let%expect_test "query_range: box straddling segment" =
  let t = one_seg 0.0 (-1.0) 0.0 1.0 in
  let r = range_of t ~x_lo:(-2.0) ~y_lo:(-0.5) ~x_hi:2.0 ~y_hi:0.5 in
  let #{ Nearest_seg.Interval.lo; hi } = r in
  printf "lo=%.4f hi=%.4f\n" (F.to_float lo) (F.to_float hi);
  [%expect {| lo=-2.0001 hi=2.0001 |}];
  assert Float.(F.to_float lo < 0.0 && F.to_float hi > 0.0)
;;

(* Degenerate box (single point): range should bracket the scalar query result *)
let%expect_test "query_range: degenerate point box" =
  let t = one_seg 0.0 (-1.0) 0.0 1.0 in
  let qx = 2.0 and qy = 0.0 in
  let r = range_of t ~x_lo:qx ~y_lo:qy ~x_hi:qx ~y_hi:qy in
  let #{ Nearest_seg.Interval.lo; hi } = r in
  let scalar = F.to_float (Nearest_seg.query t ~x:(F.of_float qx) ~y:(F.of_float qy)) in
  printf "scalar=%.4f lo=%.4f hi=%.4f\n" scalar (F.to_float lo) (F.to_float hi);
  [%expect {| scalar=2.0000 lo=1.9999 hi=2.0001 |}];
  assert Float.(F.to_float lo <= scalar && scalar <= F.to_float hi)
;;

(* Empty index: query_range should return [+inf, +inf] *)
let%expect_test "query_range: empty index" =
  let t = Nearest_seg.build (Array.create ~len:0 #0.s) ~length:0 in
  let r = range_of t ~x_lo:0.0 ~y_lo:0.0 ~x_hi:1.0 ~y_hi:1.0 in
  let #{ Nearest_seg.Interval.lo; hi } = r in
  printf "lo=%.4f hi=%.4f\n" (F.to_float lo) (F.to_float hi);
  [%expect {| lo=inf hi=inf |}]
;;

(* Build a clockwise (image-coords, y-down) unit square: inside = negative.
   In image coordinates, clockwise winding looks like: top-right → bottom-right → bottom-left → top-left
   We use corners at (±1, ±1). The interior point (0,0) should have negative distance. *)
let square_segs () =
  (* Clockwise in image coords (y-down): right side up, bottom right, left side down, top left *)
  coords_of_floats
    [| (* right side: (1,-1) → (1,1) *)
       1.0; -1.0; 1.0; 1.0
       (* bottom side: (1,1) → (-1,1) *)
     ; 1.0; 1.0; -1.0; 1.0
       (* left side: (-1,1) → (-1,-1) *)
     ; -1.0; 1.0; -1.0; -1.0
       (* top side: (-1,-1) → (1,-1) *)
     ; -1.0; -1.0; 1.0; -1.0
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
  assert Float.(F.to_float hi < 0.0)
;;

let%expect_test "query_range: box outside closed square => scalar results contained" =
  let coords = square_segs () in
  let t = Nearest_seg.build coords ~length:4 in
  (* Box far outside the square — sign side is conservative so we can't assert lo>0,
     but every scalar result must be inside the range. *)
  let r = range_of t ~x_lo:3.0 ~y_lo:3.0 ~x_hi:5.0 ~y_hi:5.0 in
  let #{ Nearest_seg.Interval.lo; hi } = r in
  printf "lo=%.4f hi=%.4f\n" (F.to_float lo) (F.to_float hi);
  [%expect {| lo=-5.6572 hi=5.6572 |}];
  (* Verify a sample point at (4,4) is inside the range *)
  let s = F.to_float (Nearest_seg.query t ~x:(F.of_float 4.0) ~y:(F.of_float 4.0)) in
  printf "scalar at (4,4)=%.4f\n" s;
  [%expect {| scalar at (4,4)=4.2426 |}];
  assert Float.(F.to_float lo <= s && s <= F.to_float hi)
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
    ~trials:2000
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
        let scalar = F.to_float (Nearest_seg.query t ~x:(F.of_float px) ~y:(F.of_float py)) in
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
