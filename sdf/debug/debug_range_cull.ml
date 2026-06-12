(* Scratch harness: why do tiles far from the boxes.neo rectangle fail to cull?

   Replicates the resample pipeline for the boxes.neo scene (single rectangle),
   then runs Nearest_seg.query_range over a 32px tile grid and prints the
   No_contour verdict map. For straddling tiles far from the contour, dissects
   the range query in float64: which segments are sign candidates, and what are
   their cross-product ranges over the tile? *)

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

let run_field name field =
  printf "\n##### %s\n" name;
  (* ui-like region: 512x512 starting at origin, step 1, expanded by 2 *)
  let width = 516
  and height = 516 in
  let start_x = -2.0
  and start_y = -2.0 in
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
  let t = Nearest_seg.build out ~length:count in
  (* Tile grid in segment (grid-index) space, 32px tiles. *)
  let tile = 32 in
  let tiles = width / tile in
  printf "\nverdict map (%dx%d tiles of %dpx): '+' all-positive, '-' all-negative, 'o' straddle\n" tiles tiles tile;
  for ty = 0 to tiles - 1 do
    for tx = 0 to tiles - 1 do
      let x_lo = F.of_float (Float.of_int (tx * tile))
      and x_hi = F.of_float (Float.of_int ((tx + 1) * tile))
      and y_lo = F.of_float (Float.of_int (ty * tile))
      and y_hi = F.of_float (Float.of_int ((ty + 1) * tile)) in
      let #{ Nearest_seg.Interval.lo; hi } =
        Nearest_seg.query_range t ~x_lo ~y_lo ~x_hi ~y_hi
      in
      let c =
        if F.compare lo #0.s > 0 then '+' else if F.compare hi #0.s <= 0 then '-' else 'o'
      in
      printf "%c" c
    done;
    printf "\n"
  done;
  (* Dissect a few interesting tiles: one far above the box (in the column band),
     one far to the left (row band), one diagonal. Box in grid space: the rect is
     at world (150,50)-(350,300), grid = world - start = world + 2. *)
  let dissect name tx ty =
    let qx0 = Float.of_int (tx * tile)
    and qx1 = Float.of_int ((tx + 1) * tile)
    and qy0 = Float.of_int (ty * tile)
    and qy1 = Float.of_int ((ty + 1) * tile) in
    let #{ Nearest_seg.Interval.lo; hi } =
      Nearest_seg.query_range
        t
        ~x_lo:(F.of_float qx0)
        ~y_lo:(F.of_float qy0)
        ~x_hi:(F.of_float qx1)
        ~y_hi:(F.of_float qy1)
    in
    printf
      "\n=== %s tile (%d,%d) grid box x[%.0f,%.0f] y[%.0f,%.0f] -> [%.4f, %.4f]\n"
      name
      tx
      ty
      qx0
      qx1
      qy0
      qy1
      (F.to_float lo)
      (F.to_float hi);
    (* float64 brute force: per-segment box min/max distance, then sign candidacy
       exactly as process_seg_range does. *)
    let pt_seg_d2 px py x1 y1 x2 y2 =
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
      (dx *. dx) +. (dy *. dy)
    in
    let aabb_d2 px py minx miny maxx maxy =
      let dx = Float.max 0. (Float.max (minx -. px) (px -. maxx)) in
      let dy = Float.max 0. (Float.max (miny -. py) (py -. maxy)) in
      (dx *. dx) +. (dy *. dy)
    in
    (* First pass: dmin2 / dub2 *)
    let dmin2 = ref Float.infinity
    and dub2 = ref Float.infinity in
    let seg s =
      ( F.to_float (Array.get out ((4 * s) + 0))
      , F.to_float (Array.get out ((4 * s) + 1))
      , F.to_float (Array.get out ((4 * s) + 2))
      , F.to_float (Array.get out ((4 * s) + 3)) )
    in
    let segmin2 = Array.create ~len:count 0.
    and segmax2 = Array.create ~len:count 0. in
    for s = 0 to count - 1 do
      let x1, y1, x2, y2 = seg s in
      let d00 = pt_seg_d2 qx0 qy0 x1 y1 x2 y2 in
      let d10 = pt_seg_d2 qx1 qy0 x1 y1 x2 y2 in
      let d01 = pt_seg_d2 qx0 qy1 x1 y1 x2 y2 in
      let d11 = pt_seg_d2 qx1 qy1 x1 y1 x2 y2 in
      let mx = Float.max (Float.max d00 d10) (Float.max d01 d11) in
      let mn = Float.min (Float.min d00 d10) (Float.min d01 d11) in
      let e1 = aabb_d2 x1 y1 qx0 qy0 qx1 qy1 in
      let e2 = aabb_d2 x2 y2 qx0 qy0 qx1 qy1 in
      (* note: ignoring the overlap test; fine for far tiles *)
      let smin = Float.min mn (Float.min e1 e2) in
      segmin2.(s) <- smin;
      segmax2.(s) <- mx;
      if Float.(smin < !dmin2) then dmin2 := smin;
      if Float.(mx < !dub2) then dub2 := mx
    done;
    printf "  dmin=%.4f dub=%.4f\n" (Float.sqrt !dmin2) (Float.sqrt !dub2);
    (* Second pass: sign candidates *)
    let window = 1.0003 in
    let shown = ref 0 in
    for s = 0 to count - 1 do
      if Float.(segmin2.(s) <= !dub2 *. window)
      then (
        let x1, y1, x2, y2 = seg s in
        let abx = x2 -. x1
        and aby = y2 -. y1 in
        let cross px py = (abx *. (py -. y1)) -. (aby *. (px -. x1)) in
        let c00 = cross qx0 qy0
        and c10 = cross qx1 qy0
        and c01 = cross qx0 qy1
        and c11 = cross qx1 qy1 in
        let cmin = Float.min (Float.min c00 c10) (Float.min c01 c11)
        and cmax = Float.max (Float.max c00 c10) (Float.max c01 c11) in
        let tol = 1e-4 *. Float.max (Float.abs cmin) (Float.abs cmax) in
        let can_neg = Float.(cmax > -.tol)
        and can_pos = Float.(cmin <= tol) in
        incr shown;
        if !shown <= 12
        then
          printf
            "  cand seg %d (%.3f,%.3f)->(%.3f,%.3f) dmin=%.3f cross[%.2f,%.2f] %s%s\n"
            s
            x1
            y1
            x2
            y2
            (Float.sqrt segmin2.(s))
            cmin
            cmax
            (if can_neg then "can_neg " else "")
            (if can_pos then "can_pos" else ""))
    done;
    printf "  (%d sign candidates total)\n" !shown
  in
  ignore dissect;
  (* The real fix: an index built with ~assume_level_set:true resolves ambiguous
     signs with a midpoint probe inside query_range. *)
  let tp = Nearest_seg.build ~assume_level_set:true out ~length:count in
  printf "\nverdict map with ~assume_level_set:true:\n";
  let active_before = ref 0
  and active_after = ref 0 in
  for ty = 0 to tiles - 1 do
    for tx = 0 to tiles - 1 do
      let x_lo = F.of_float (Float.of_int (tx * tile))
      and x_hi = F.of_float (Float.of_int ((tx + 1) * tile))
      and y_lo = F.of_float (Float.of_int (ty * tile))
      and y_hi = F.of_float (Float.of_int ((ty + 1) * tile)) in
      let straddle (t : Nearest_seg.t) =
        let #{ Nearest_seg.Interval.lo; hi } =
          Nearest_seg.query_range t ~x_lo ~y_lo ~x_hi ~y_hi
        in
        F.compare lo #0.s <= 0 && F.compare hi #0.s > 0
      in
      if straddle t then incr active_before;
      let #{ Nearest_seg.Interval.lo; hi } =
        Nearest_seg.query_range tp ~x_lo ~y_lo ~x_hi ~y_hi
      in
      let c =
        if F.compare lo #0.s > 0
        then '+'
        else if F.compare hi #0.s <= 0
        then '-'
        else (
          incr active_after;
          'o')
      in
      printf "%c" c
    done;
    printf "\n"
  done;
  printf
    "\nactive tiles: %d without probe, %d with probe (of %d)\n"
    !active_before
    !active_after
    (tiles * tiles);
  (* Soundness sweep: every culled tile's claimed sign must agree with the scalar
     query at every grid point inside the tile. *)
  let violations = ref 0 in
  for ty = 0 to tiles - 1 do
    for tx = 0 to tiles - 1 do
      let x_lo = F.of_float (Float.of_int (tx * tile))
      and x_hi = F.of_float (Float.of_int ((tx + 1) * tile))
      and y_lo = F.of_float (Float.of_int (ty * tile))
      and y_hi = F.of_float (Float.of_int ((ty + 1) * tile)) in
      let #{ Nearest_seg.Interval.lo; hi } =
        Nearest_seg.query_range tp ~x_lo ~y_lo ~x_hi ~y_hi
      in
      for gy = ty * tile to (ty + 1) * tile do
        for gx = tx * tile to (tx + 1) * tile do
          let q =
            Nearest_seg.query
              tp
              ~x:(F.of_float (Float.of_int gx))
              ~y:(F.of_float (Float.of_int gy))
          in
          if F.compare q lo < 0 || F.compare q hi > 0
          then (
            incr violations;
            if !violations <= 5
            then
              printf
                "CONTAINMENT VIOLATION tile (%d,%d) point (%d,%d): q=%.4f not in [%.4f, %.4f]\n"
                tx
                ty
                gx
                gy
                (F.to_float q)
                (F.to_float lo)
                (F.to_float hi))
        done
      done
    done
  done;
  printf "containment violations: %d\n" !violations
;;

let () =
  run_field "interior box (closed contour)" (fun px py -> rect 150. 50. 200. 250. px py);
  (* Adversary: the rectangle extends past the right region boundary, so march clips
     it there, leaving open chain ends. Tiles in the sign-flip wedge past those ends
     must keep both signs. *)
  run_field "box clipped at right boundary (open ends)" (fun px py ->
    rect 150. 50. 600. 250. px py);
  (* Adversary: clipped at top AND bottom: two separate vertical strips of contour. *)
  run_field "box clipped top and bottom" (fun px py -> rect 150. (-50.) 200. 700. px py)
;;
