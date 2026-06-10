(* Debug harness for the resample-oracle sign bug.

   Replicates the inner pipeline of Sdf_resample_oracle for the boxes.neo scene:
   sample the union pseudo-SDF on the expanded grid, run marching squares, build
   the nearest-segment index, then compare the sign of the resampled field
   against the analytically-known field at every grid point. *)

open! Core
module F = Float32_u

let rect rx ry w h px py =
  let hw = w /. 2.
  and hh = h /. 2. in
  let cx = rx +. hw
  and cy = ry +. hh in
  let dx = Float.abs (px -. cx) -. hw
  and dy = Float.abs (py -. cy) -. hh in
  let outside =
    Float.sqrt ((Float.max dx 0. *. Float.max dx 0.) +. (Float.max dy 0. *. Float.max dy 0.))
  in
  let inside = Float.min (Float.max dx dy) 0. in
  outside +. inside
;;

let union_boxes px py =
  Float.min (rect 50. 100. 100. 150. px py) (rect 150. 50. 200. 250. px py)
;;

(* Same union, rotated 30 degrees about (200, 175): diagonal edges, off-axis corners. *)
let rotated_boxes px py =
  let c = Float.cos (Float.pi /. 6.)
  and s = Float.sin (Float.pi /. 6.) in
  let dx = px -. 200.
  and dy = py -. 175. in
  union_boxes (200. +. (c *. dx) +. (s *. dy)) (175. -. (s *. dx) +. (c *. dy))
;;

(* A thin acute wedge (about 22 degrees at the apex), as the intersection of two
   half-planes and a bounding circle. Acute vertices are the stress case for the
   nearest-segment sign tie-break. *)
let wedge px py =
  let dx = px -. 100.
  and dy = py -. 175. in
  let half_plane nx ny = (dx *. nx) +. (dy *. ny) in
  let circle = Float.sqrt ((dx *. dx) +. (dy *. dy)) -. 200. in
  Float.max circle (Float.max (half_plane (-0.1) 0.995) (half_plane 0.3 (-0.954)))
;;

let fields = [ "union_boxes", union_boxes; "rotated_boxes", rotated_boxes; "wedge", wedge ]

let run_field name field =
  printf "\n##### field %s\n" name;
  (* svg repro region expanded by 2, step 1 *)
  let width = 804
  and height = 804 in
  let start_x = -80.0546875
  and start_y = -71.1796875 in
  let grid : float32# array = Array.create ~len:(width * height) #0.0s in
  for iy = 0 to height - 1 do
    for ix = 0 to width - 1 do
      let wx = start_x +. Float.of_int ix
      and wy = start_y +. Float.of_int iy in
      grid.((iy * width) + ix) <- F.of_float (field wx wy)
    done
  done;
  let out : float32# array = Array.create ~len:(width * height * 2 * 4) #0.0s in
  let count = March.run grid out width height in
  printf "march emitted %d segments\n" count;
  (* Check 1: winding. For each segment, probe the field on both sides; the supposed
     inside (right side of the directed segment) must read lower than the outside.
     Comparing the two sides rather than testing signs keeps sub-pixel contour features
     (e.g. single-sample diamonds at the tip of a thin sliver, where both probes
     overshoot into positive territory) from raising false alarms. *)
  let winding_bad = ref 0 in
  let probe_dist = 0.5 in
  for s = 0 to count - 1 do
    let x1 = F.to_float (Array.get out ((4 * s) + 0)) in
    let y1 = F.to_float (Array.get out ((4 * s) + 1)) in
    let x2 = F.to_float (Array.get out ((4 * s) + 2)) in
    let y2 = F.to_float (Array.get out ((4 * s) + 3)) in
    let dx = x2 -. x1
    and dy = y2 -. y1 in
    let len = Float.sqrt ((dx *. dx) +. (dy *. dy)) in
    if Float.(len > 1e-6)
    then (
      let mx = (x1 +. x2) /. 2.
      and my = (y1 +. y2) /. 2. in
      (* inside direction = (-dy, dx) / len, per the cross>0 convention *)
      let f_in =
        field
          (start_x +. mx +. (probe_dist *. (-.dy) /. len))
          (start_y +. my +. (probe_dist *. dx /. len))
      in
      let f_out =
        field
          (start_x +. mx -. (probe_dist *. (-.dy) /. len))
          (start_y +. my -. (probe_dist *. dx /. len))
      in
      if Float.(f_in >= f_out)
      then (
        incr winding_bad;
        if !winding_bad <= 10
        then
          printf
            "winding violation seg %d: (%.3f,%.3f)->(%.3f,%.3f) f_in=%.3f f_out=%.3f\n"
            s
            x1
            y1
            x2
            y2
            f_in
            f_out))
  done;
  printf "winding violations: %d / %d\n" !winding_bad count;
  (* Check 2: sign of the resampled field vs the true field, on the grid lattice.
     Query in segment (grid-index) space: index = world - start. *)
  let t = Nearest_seg.build out ~length:count in
  let dummy = Nearest_seg.Dummy.build out ~length:count in
  let flipped = ref 0 in
  let disagree = ref 0 in
  let minx = ref Float.infinity
  and maxx = ref Float.neg_infinity
  and miny = ref Float.infinity
  and maxy = ref Float.neg_infinity in
  let examples = ref [] in
  for iy = 0 to height - 1 do
    for ix = 0 to width - 1 do
      let wx = start_x +. Float.of_int ix
      and wy = start_y +. Float.of_int iy in
      let f = field wx wy in
      if Float.(abs f > 2.0)
      then (
        let qx = F.of_float (Float.of_int ix)
        and qy = F.of_float (Float.of_int iy) in
        let q = F.to_float (Nearest_seg.query t ~x:qx ~y:qy) in
        let qd = F.to_float (Nearest_seg.Dummy.query dummy ~x:qx ~y:qy) in
        if Float.(q *. qd < 0.) then incr disagree;
        if Float.(f *. q < 0.)
        then (
          incr flipped;
          minx := Float.min !minx wx;
          maxx := Float.max !maxx wx;
          miny := Float.min !miny wy;
          maxy := Float.max !maxy wy;
          if !flipped mod 97 = 1 && List.length !examples < 6
          then examples := (ix, iy, wx, wy, f, q, qd) :: !examples))
    done
  done;
  printf "flipped sign points: %d\n" !flipped;
  printf "real/dummy sign disagreements: %d\n" !disagree;
  if !flipped > 0
  then
    printf
      "flipped bbox (world): x[%.2f, %.2f] y[%.2f, %.2f]\n"
      !minx
      !maxx
      !miny
      !maxy;
  (* Check 3: for example flipped points, brute-force the nearest segments in
     float64 and show the top candidates: distance, parameter t, cross sign. *)
  List.iter (List.rev !examples) ~f:(fun (ix, iy, wx, wy, f, q, qd) ->
    printf
      "\n=== flipped point grid(%d,%d) world(%.2f,%.2f) true=%.4f query=%.4f dummy=%.4f\n"
      ix
      iy
      wx
      wy
      f
      q
      qd;
    let px = Float.of_int ix
    and py = Float.of_int iy in
    let cands = ref [] in
    for s = 0 to count - 1 do
      let x1 = F.to_float (Array.get out ((4 * s) + 0)) in
      let y1 = F.to_float (Array.get out ((4 * s) + 1)) in
      let x2 = F.to_float (Array.get out ((4 * s) + 2)) in
      let y2 = F.to_float (Array.get out ((4 * s) + 3)) in
      let abx = x2 -. x1
      and aby = y2 -. y1 in
      let apx = px -. x1
      and apy = py -. y1 in
      let len2 = (abx *. abx) +. (aby *. aby) in
      let tp =
        if Float.(len2 > 0.)
        then Float.max 0. (Float.min 1. (((apx *. abx) +. (apy *. aby)) /. len2))
        else 0.
      in
      let dx = px -. (x1 +. (tp *. abx))
      and dy = py -. (y1 +. (tp *. aby)) in
      let d2 = (dx *. dx) +. (dy *. dy) in
      let cross = (abx *. apy) -. (aby *. apx) in
      cands := (d2, s, x1, y1, x2, y2, tp, cross) :: !cands
    done;
    let sorted =
      List.sort !cands ~compare:(fun (d1, _, _, _, _, _, _, _) (d2, _, _, _, _, _, _, _) ->
        Float.compare d1 d2)
    in
    List.iteri (List.take sorted 6) ~f:(fun i (d2, s, x1, y1, x2, y2, tp, cross) ->
      printf
        "  #%d seg %d (%.4f,%.4f)->(%.4f,%.4f) d=%.6f t=%.3f cross=%+.4f sign=%s\n"
        i
        s
        x1
        y1
        x2
        y2
        (Float.sqrt d2)
        tp
        cross
        (if Float.(cross > 0.) then "inside" else "OUTSIDE")))
;;

let () = List.iter fields ~f:(fun (name, field) -> run_field name field)
