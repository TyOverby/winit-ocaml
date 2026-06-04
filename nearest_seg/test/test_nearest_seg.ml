open! Core
module F = Float32_u

(* Reference implementation: scan every segment, keep the closest. Uses the exact same
   float32 arithmetic as [Nearest_seg] so the only thing under test is the spatial
   structure (which segments get visited), not the distance formula. *)

let seg_dist2 px py x1 y1 x2 y2 =
  let abx = F.sub x2 x1 in
  let aby = F.sub y2 y1 in
  let apx = F.sub px x1 in
  let apy = F.sub py y1 in
  let len2 = F.add (F.mul abx abx) (F.mul aby aby) in
  let dot = F.add (F.mul apx abx) (F.mul apy aby) in
  let tparam =
    if F.compare len2 #0.s > 0
    then begin
      let q = F.div dot len2 in
      if F.compare q #0.s < 0 then #0.s else if F.compare q #1.s > 0 then #1.s else q
    end
    else #0.s
  in
  let dx = F.sub px (F.add x1 (F.mul tparam abx)) in
  let dy = F.sub py (F.add y1 (F.mul tparam aby)) in
  F.add (F.mul dx dx) (F.mul dy dy)

let seg_sign px py x1 y1 x2 y2 =
  let abx = F.sub x2 x1 in
  let aby = F.sub y2 y1 in
  let apx = F.sub px x1 in
  let apy = F.sub py y1 in
  let cross = F.sub (F.mul abx apy) (F.mul aby apx) in
  if F.compare cross #0.s > 0 then -1.0 else 1.0

(* Naively compute, for the query point, the minimum squared distance over all segments
   and the signed distances of every segment achieving that minimum (within a small
   tolerance). Returns floats for easy comparison. *)
let naive coords px py =
  let n = Array.length coords / 4 in
  let min_d2 = ref Float.infinity in
  let signed = ref [] in
  for s = 0 to n - 1 do
    let x1 = Array.get coords ((4 * s) + 0) in
    let y1 = Array.get coords ((4 * s) + 1) in
    let x2 = Array.get coords ((4 * s) + 2) in
    let y2 = Array.get coords ((4 * s) + 3) in
    let d2 = F.to_float (seg_dist2 px py x1 y1 x2 y2) in
    let sgn = seg_sign px py x1 y1 x2 y2 in
    signed := (d2, sgn) :: !signed;
    if Float.( < ) d2 !min_d2 then min_d2 := d2
  done;
  let tol = 1e-4 *. (1.0 +. !min_d2) in
  let candidates =
    List.filter_map !signed ~f:(fun (d2, sgn) ->
      if Float.( <= ) (Float.abs (d2 -. !min_d2)) tol
      then Some (sgn *. Float.sqrt d2)
      else None)
  in
  !min_d2, candidates

let coords_of_floats (fs : float array) : float32# array =
  let len = Array.length fs in
  let out = Array.create ~len #0.s in
  for i = 0 to len - 1 do
    Array.set out i (F.of_float (Array.get fs i))
  done;
  out

let gen =
  let open Quickcheck.Generator.Let_syntax in
  let%bind m = Int.gen_incl 1 40 in
  let coord = Float.gen_incl (-100.0) 100.0 in
  let%bind segs = List.gen_with_length (4 * m) coord in
  let%bind qx = Float.gen_incl (-150.0) 150.0 in
  let%map qy = Float.gen_incl (-150.0) 150.0 in
  Array.of_list segs, qx, qy

let%test_unit "spatial index matches naive nearest-segment scan" =
  Quickcheck.test
    gen
    ~sexp_of:[%sexp_of: float array * float * float]
    ~trials:5000
    ~f:(fun (segs, qxf, qyf) ->
      let coords = coords_of_floats segs in
      let t = Nearest_seg.build coords in
      let px = F.of_float qxf in
      let py = F.of_float qyf in
      let got = F.to_float (Nearest_seg.query t ~x:px ~y:py) in
      let _min_d2, candidates = naive coords px py in
      let tol = 1e-2 *. (1.0 +. Float.abs got) in
      let ok =
        List.exists candidates ~f:(fun c -> Float.( <= ) (Float.abs (got -. c)) tol)
      in
      if not ok
      then
        raise_s
          [%message
            "spatial query disagreed with naive scan"
              (got : float)
              (candidates : float list)
              (qxf : float)
              (qyf : float)
              (segs : float array)])

(* A couple of concrete sanity checks pin down the sign convention. *)

let one_seg x1 y1 x2 y2 =
  Nearest_seg.build (coords_of_floats [| x1; y1; x2; y2 |])

let%expect_test "sign: point to the right of an upward segment is positive" =
  (* Segment pointing +y; the point (1, 0) is to its right in math orientation. *)
  let t = one_seg 0.0 (-1.0) 0.0 1.0 in
  let d = F.to_float (Nearest_seg.query t ~x:(F.of_float 1.0) ~y:#0.s) in
  printf "%.4f" d;
  [%expect {| 1.0000 |}]

let%expect_test "sign: point to the left of an upward segment is negative" =
  let t = one_seg 0.0 (-1.0) 0.0 1.0 in
  let d = F.to_float (Nearest_seg.query t ~x:(F.of_float (-1.0)) ~y:#0.s) in
  printf "%.4f" d;
  [%expect {| -1.0000 |}]

let%expect_test "distance clamps to the nearer endpoint" =
  (* Closest point to (5, 0) on this segment is the endpoint (1, 0): distance 4. *)
  let t = one_seg (-1.0) 0.0 1.0 0.0 in
  let d = F.to_float (Nearest_seg.query t ~x:(F.of_float 5.0) ~y:#0.s) in
  printf "%.4f" (Float.abs d);
  [%expect {| 4.0000 |}]
