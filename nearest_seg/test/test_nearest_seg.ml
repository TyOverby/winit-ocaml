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
