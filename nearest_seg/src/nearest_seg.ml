open! Core
module F = Float32_u

(* Number of segments packed into a single leaf. Leaves are scanned linearly, so a small
   value keeps the branch-and-bound pruning tight; a value > 1 keeps the tree shallow. *)
let leaf_size = 4
let zero = #0.s
let half = #0.5s
let one = #1.s
let neg_one = F.neg #1.s

(* Relative width of the distance-tie window used when deciding which segment supplies
   the *sign* of the result (see [scan_leaf]). Squared distances within this relative
   margin of the minimum are treated as ties: float32 evaluation of d2 is only accurate
   to a few ulps (~1e-7 relative), so candidates whose true distances differ by less than
   that can compare in an arbitrary order. The window is far below any meaningful
   geometric separation (a relative 4e-6 in squared distance), so it only ever groups
   candidates that touch what is effectively the same contour point. *)
let one_plus_eps = #1.000004s
let one_minus_eps = #0.999996s

type inner =
  { (* Segment endpoints, reordered into leaf order (so each leaf owns a contiguous
       range). Indexed by reordered segment position, not original input position. *)
    sx1 : float32# array
  ; sy1 : float32# array
  ; sx2 : float32# array
  ; sy2 : float32# array
  ; (* Per-node axis-aligned bounding box. *)
    nminx : float32# array
  ; nminy : float32# array
  ; nmaxx : float32# array
  ; nmaxy : float32# array
  ; (* Tree structure. For an internal node [nleft] / [nright] are child node indices and
       [nstart] is -1. For a leaf [nleft] is -1 and [nstart] / [ncount] give the half-open
       range of segments it owns. The root is node 0. *)
    nleft : int array
  ; nright : int array
  ; nstart : int array
  ; ncount : int array
  ; seg_count : int
  }

type t = inner portended

let empty =
  let f = Array.create ~len:0 zero in
  let i = Array.create ~len:0 0 in
  { portended =
      Obj.magic_portable__contended
        { sx1 = f
        ; sy1 = f
        ; sx2 = f
        ; sy2 = f
        ; nminx = f
        ; nminy = f
        ; nmaxx = f
        ; nmaxy = f
        ; nleft = i
        ; nright = i
        ; nstart = i
        ; ncount = i
        ; seg_count = 0
        }
  }
;;

let build (coords : float32# array) ~length : t =
  let n = length in
  if n <= 0
  then empty
  else (
    (* Per-segment bounding boxes and centroids, indexed by *original* segment id. *)
    let segminx = Array.create ~len:n zero in
    let segminy = Array.create ~len:n zero in
    let segmaxx = Array.create ~len:n zero in
    let segmaxy = Array.create ~len:n zero in
    let cx = Array.create ~len:n zero in
    let cy = Array.create ~len:n zero in
    for s = 0 to n - 1 do
      let x1 = Array.get coords ((4 * s) + 0) in
      let y1 = Array.get coords ((4 * s) + 1) in
      let x2 = Array.get coords ((4 * s) + 2) in
      let y2 = Array.get coords ((4 * s) + 3) in
      Array.set segminx s (F.min x1 x2);
      Array.set segminy s (F.min y1 y2);
      Array.set segmaxx s (F.max x1 x2);
      Array.set segmaxy s (F.max y1 y2);
      Array.set cx s (F.mul (F.add x1 x2) half);
      Array.set cy s (F.mul (F.add y1 y2) half)
    done;
    (* [perm] is reordered in place by the splitting passes; leaves own contiguous ranges
       of the final ordering. *)
    let perm = Array.init n ~f:Fn.id in
    (* A binary tree with [n] leaves of size >= 1 has at most [2n - 1] nodes. *)
    let nmax = (2 * n) - 1 in
    let nminx = Array.create ~len:nmax zero in
    let nminy = Array.create ~len:nmax zero in
    let nmaxx = Array.create ~len:nmax zero in
    let nmaxy = Array.create ~len:nmax zero in
    let nleft = Array.create ~len:nmax (-1) in
    let nright = Array.create ~len:nmax (-1) in
    let nstart = Array.create ~len:nmax (-1) in
    let ncount = Array.create ~len:nmax 0 in
    let node_ctr = ref 0 in
    (* Scratch box for the centroid bounds of the range being split. *)
    let cb = Array.create ~len:4 zero in
    let rec build_node lo hi =
      let id = !node_ctr in
      incr node_ctr;
      (* Node bounding box = union of the segment boxes in [lo, hi). *)
      let s0 = Array.get perm lo in
      Array.set nminx id (Array.get segminx s0);
      Array.set nminy id (Array.get segminy s0);
      Array.set nmaxx id (Array.get segmaxx s0);
      Array.set nmaxy id (Array.get segmaxy s0);
      for i = lo + 1 to hi - 1 do
        let s = Array.get perm i in
        Array.set nminx id (F.min (Array.get nminx id) (Array.get segminx s));
        Array.set nminy id (F.min (Array.get nminy id) (Array.get segminy s));
        Array.set nmaxx id (F.max (Array.get nmaxx id) (Array.get segmaxx s));
        Array.set nmaxy id (F.max (Array.get nmaxy id) (Array.get segmaxy s))
      done;
      if hi - lo <= leaf_size
      then (
        Array.set nleft id (-1);
        Array.set nstart id lo;
        Array.set ncount id (hi - lo))
      else (
        (* Centroid bounds, to choose the split axis. *)
        Array.set cb 0 (Array.get cx s0);
        Array.set cb 1 (Array.get cy s0);
        Array.set cb 2 (Array.get cx s0);
        Array.set cb 3 (Array.get cy s0);
        for i = lo + 1 to hi - 1 do
          let s = Array.get perm i in
          Array.set cb 0 (F.min (Array.get cb 0) (Array.get cx s));
          Array.set cb 1 (F.min (Array.get cb 1) (Array.get cy s));
          Array.set cb 2 (F.max (Array.get cb 2) (Array.get cx s));
          Array.set cb 3 (F.max (Array.get cb 3) (Array.get cy s))
        done;
        let ex = F.sub (Array.get cb 2) (Array.get cb 0) in
        let ey = F.sub (Array.get cb 3) (Array.get cb 1) in
        let axis_x = F.compare ex ey >= 0 in
        let mid =
          if axis_x
          then F.mul (F.add (Array.get cb 0) (Array.get cb 2)) half
          else F.mul (F.add (Array.get cb 1) (Array.get cb 3)) half
        in
        (* Partition [perm] in place: centroid-on-axis < mid goes left. *)
        let i = ref lo in
        let j = ref (hi - 1) in
        while !i <= !j do
          let s = Array.get perm !i in
          let c = if axis_x then Array.get cx s else Array.get cy s in
          if F.compare c mid < 0
          then incr i
          else (
            Array.set perm !i (Array.get perm !j);
            Array.set perm !j s;
            decr j)
        done;
        let split = !i in
        (* Degenerate split (e.g. all centroids coincide): fall back to a halfway cut so
           recursion still makes progress. The BVH stays correct regardless of split. *)
        let split = if split <= lo || split >= hi then (lo + hi) / 2 else split in
        let l = build_node lo split in
        let r = build_node split hi in
        Array.set nleft id l;
        Array.set nright id r;
        Array.set nstart id (-1));
      id
    in
    let (_root : int) = build_node 0 n in
    (* Materialise segment endpoints in leaf order. *)
    let sx1 = Array.create ~len:n zero in
    let sy1 = Array.create ~len:n zero in
    let sx2 = Array.create ~len:n zero in
    let sy2 = Array.create ~len:n zero in
    for i = 0 to n - 1 do
      let s = Array.get perm i in
      Array.set sx1 i (Array.get coords ((4 * s) + 0));
      Array.set sy1 i (Array.get coords ((4 * s) + 1));
      Array.set sx2 i (Array.get coords ((4 * s) + 2));
      Array.set sy2 i (Array.get coords ((4 * s) + 3))
    done;
    { portended =
        Obj.magic_portable__contended
          { sx1
          ; sy1
          ; sx2
          ; sy2
          ; nminx
          ; nminy
          ; nmaxx
          ; nmaxy
          ; nleft
          ; nright
          ; nstart
          ; ncount
          ; seg_count = n
          }
    })
;;

(* Squared distance from [(px, py)] to a node's bounding box. This is a *lower bound* on
   the distance to any segment in the node (the box contains the segments), so it is safe
   for branch-and-bound pruning. *)
let[@inline] aabb_dist2 px py minx miny maxx maxy =
  let dx = F.max zero (F.max (F.sub minx px) (F.sub px maxx)) in
  let dy = F.max zero (F.max (F.sub miny py) (F.sub py maxy)) in
  F.add (F.mul dx dx) (F.mul dy dy)
;;

(* Scan a leaf's segments, updating the running best. [best] holds the best squared
   distance at index 0, the sign (+1 / -1) of the winning segment at index 1, and the
   squared perpendicular distance from the query point to the winning segment's infinite
   line at index 2 (the tie-break metric, see below). *)
let scan_leaf t s c px py best =
  for k = s to s + c - 1 do
    let x1 = Array.get t.sx1 k in
    let y1 = Array.get t.sy1 k in
    let x2 = Array.get t.sx2 k in
    let y2 = Array.get t.sy2 k in
    let abx = F.sub x2 x1 in
    let aby = F.sub y2 y1 in
    let apx = F.sub px x1 in
    let apy = F.sub py y1 in
    let len2 = F.add (F.mul abx abx) (F.mul aby aby) in
    let dot = F.add (F.mul apx abx) (F.mul apy aby) in
    (* Project the point onto the segment, clamping to the endpoints. *)
    let tparam =
      if F.compare len2 zero > 0
      then (
        let q = F.div dot len2 in
        if F.compare q zero < 0 then zero else if F.compare q one > 0 then one else q)
      else zero
    in
    (* When the projection clamps, take the endpoint verbatim from the segment data
       rather than computing [x1 + t * abx]: two segments sharing a vertex then measure
       the distance to that vertex from bitwise-identical coordinates, so their squared
       distances tie *exactly* and the tie-break below can see the tie. *)
    let interior = F.compare tparam zero > 0 && F.compare tparam one < 0 in
    let cpx =
      if interior
      then F.add x1 (F.mul tparam abx)
      else if F.compare tparam zero > 0
      then x2
      else x1
    in
    let cpy =
      if interior
      then F.add y1 (F.mul tparam aby)
      else if F.compare tparam zero > 0
      then y2
      else y1
    in
    let dx = F.sub px cpx in
    let dy = F.sub py cpy in
    let d2 = F.add (F.mul dx dx) (F.mul dy dy) in
    if F.compare d2 (F.mul (Array.get best 0) one_plus_eps) <= 0
    then (
      (* Sidedness from the cross product of the directed segment with the point. For
         contours wound clockwise on screen (image coords, y down) around solid regions,
         cross > 0 is the inside, so it gets a negative sign: negative inside, positive
         outside, the standard SDF convention. See [query] in the .mli.

         When two segments share a vertex and the query point's nearest contour point is
         that vertex (or an interior projection within rounding error of it), they report
         the same distance up to float32 noise but can disagree on the side: the point
         lies beyond a segment's extent, where the infinite-line test is meaningless for
         the segment whose line the point is nearly collinear with. Resolve distance ties
         toward the segment whose infinite line the point deviates from the most (largest
         perpendicular distance) - the 2D angle-weighted-pseudonormal rule, which gives
         the correct sign at vertices of a consistently wound contour. *)
      let cross = F.sub (F.mul abx apy) (F.mul aby apx) in
      let line_d2 =
        if F.compare len2 zero > 0 then F.div (F.mul cross cross) len2 else zero
      in
      if F.compare d2 (F.mul (Array.get best 0) one_minus_eps) < 0
         || F.compare line_d2 (Array.get best 2) > 0
      then (
        let sign = if F.compare cross zero > 0 then neg_one else one in
        Array.set best 1 sign;
        Array.set best 2 line_d2);
      if F.compare d2 (Array.get best 0) < 0 then Array.set best 0 d2)
  done
;;

let rec visit t node px py best =
  let left = Array.get t.nleft node in
  if left < 0
  then scan_leaf t (Array.get t.nstart node) (Array.get t.ncount node) px py best
  else (
    let right = Array.get t.nright node in
    let dl =
      aabb_dist2
        px
        py
        (Array.get t.nminx left)
        (Array.get t.nminy left)
        (Array.get t.nmaxx left)
        (Array.get t.nmaxy left)
    in
    let dr =
      aabb_dist2
        px
        py
        (Array.get t.nminx right)
        (Array.get t.nminy right)
        (Array.get t.nmaxx right)
        (Array.get t.nmaxy right)
    in
    (* Descend into the nearer child first to tighten [best] before pruning the other.
       Re-read [best] for the second child since the first may have improved it. Pruning
       must keep nodes inside the distance-tie window ([<= best * (1 + eps)], not
       [< best]): a near-equidistant segment in another node may win the sign tie-break
       in [scan_leaf]. *)
    if F.compare dl dr <= 0
    then (
      if F.compare dl (F.mul (Array.get best 0) one_plus_eps) <= 0
      then visit t left px py best;
      if F.compare dr (F.mul (Array.get best 0) one_plus_eps) <= 0
      then visit t right px py best)
    else (
      if F.compare dr (F.mul (Array.get best 0) one_plus_eps) <= 0
      then visit t right px py best;
      if F.compare dl (F.mul (Array.get best 0) one_plus_eps) <= 0
      then visit t left px py best))
;;

let query { portended = t } ~x ~y =
  let t = Obj.magic Obj.magic t in
  if t.seg_count = 0
  then F.infinity
  else (
    let best = Array.create ~len:3 F.infinity in
    Array.set best 1 one;
    Array.set best 2 zero;
    visit t 0 x y best;
    F.mul (Array.get best 1) (F.sqrt (Array.get best 0)))
;;

let query @ portable = Obj.magic_portable query

(* ---------- Range queries ---------- *)

module Interval = struct
  type t = #{ lo : float32#
            ; hi : float32#
            }
end

(* Mutable accumulator threaded through a range query.

   [dmin2] is the minimum over segments of the squared distance from the query box to
   the segment: a lower bound on |query p| anywhere in the box (and exact at the point
   of the box closest to the contour).

   [dub2] is the minimum over segments of (maximum over the box's corners of the squared
   point-to-segment distance). For any point p, |query p| = min over segments of
   d(p, s) <= d(p, s') <= corner-max(s') for every segment s', so [dub2] upper-bounds
   |query|^2 over the whole box (point-to-segment distance is convex, so its max over the
   box is attained at a corner).

   [can_pos] / [can_neg] record which signs the query could return somewhere in the box,
   derived from the cross-product range of every segment close enough to be the nearest
   (and hence supply the sign) for some point of the box. *)
type range_acc =
  { mutable dmin2 : float32#
  ; mutable dub2 : float32#
  ; mutable can_pos : bool
  ; mutable can_neg : bool
  }

(* Slightly wider than [one_plus_eps]: candidates for supplying the sign must cover the
   scalar query's distance-tie window plus float32 noise from computing box distances by
   a different formula than [scan_leaf]'s per-point one. *)
let range_sign_window = #1.0003s

(* Relative tolerance on the corner cross-product test, absorbing float32 rounding when a
   box point sits essentially on a segment's infinite line. *)
let cross_tol_rel = #1e-4s

(* Outward padding applied to the final distance bounds, relative to the magnitudes
   involved, so that scalar queries (computed by a different float32 expression) can
   never land outside the reported range by mere rounding. *)
let range_pad_rel = #3e-5s

let[@inline] min4 a b c d = F.min (F.min a b) (F.min c d)
let[@inline] max4 a b c d = F.max (F.max a b) (F.max c d)

(* Squared point-to-segment distance; same projection-and-clamp construction as
   [scan_leaf]. *)
let[@inline] pt_seg_dist2 px py x1 y1 x2 y2 =
  let abx = F.sub x2 x1 in
  let aby = F.sub y2 y1 in
  let apx = F.sub px x1 in
  let apy = F.sub py y1 in
  let len2 = F.add (F.mul abx abx) (F.mul aby aby) in
  let dot = F.add (F.mul apx abx) (F.mul apy aby) in
  let tparam =
    if F.compare len2 zero > 0
    then (
      let q = F.div dot len2 in
      if F.compare q zero < 0 then zero else if F.compare q one > 0 then one else q)
    else zero
  in
  let interior = F.compare tparam zero > 0 && F.compare tparam one < 0 in
  let cpx =
    if interior
    then F.add x1 (F.mul tparam abx)
    else if F.compare tparam zero > 0
    then x2
    else x1
  in
  let cpy =
    if interior
    then F.add y1 (F.mul tparam aby)
    else if F.compare tparam zero > 0
    then y2
    else y1
  in
  let dx = F.sub px cpx in
  let dy = F.sub py cpy in
  F.add (F.mul dx dx) (F.mul dy dy)
;;

(* Squared gap between the query box and an axis-aligned box: a lower bound on the
   distance from any query-box point to anything inside the node box. *)
let[@inline] box_box_gap2 qx0 qy0 qx1 qy1 minx miny maxx maxy =
  let dx = F.max zero (F.max (F.sub minx qx1) (F.sub qx0 maxx)) in
  let dy = F.max zero (F.max (F.sub miny qy1) (F.sub qy0 maxy)) in
  F.add (F.mul dx dx) (F.mul dy dy)
;;

(* Separating-axis test between a segment and the query box: the candidate axes for a
   segment vs. an AABB are x, y, and the segment's normal. *)
let[@inline] seg_intersects_box x1 y1 x2 y2 qx0 qy0 qx1 qy1 =
  F.compare (F.min x1 x2) qx1 <= 0
  && F.compare (F.max x1 x2) qx0 >= 0
  && F.compare (F.min y1 y2) qy1 <= 0
  && F.compare (F.max y1 y2) qy0 >= 0
  &&
  let nx = F.neg (F.sub y2 y1) in
  let ny = F.sub x2 x1 in
  let c = F.add (F.mul nx x1) (F.mul ny y1) in
  let p1 = F.add (F.mul nx qx0) (F.mul ny qy0) in
  let p2 = F.add (F.mul nx qx1) (F.mul ny qy0) in
  let p3 = F.add (F.mul nx qx0) (F.mul ny qy1) in
  let p4 = F.add (F.mul nx qx1) (F.mul ny qy1) in
  F.compare (min4 p1 p2 p3 p4) c <= 0 && F.compare c (max4 p1 p2 p3 p4) <= 0
;;

let process_seg_range x1 y1 x2 y2 qx0 qy0 qx1 qy1 acc =
  let d00 = pt_seg_dist2 qx0 qy0 x1 y1 x2 y2 in
  let d10 = pt_seg_dist2 qx1 qy0 x1 y1 x2 y2 in
  let d01 = pt_seg_dist2 qx0 qy1 x1 y1 x2 y2 in
  let d11 = pt_seg_dist2 qx1 qy1 x1 y1 x2 y2 in
  let segmax2 = max4 d00 d10 d01 d11 in
  (* Min distance between two convex sets is attained vertex-to-edge or vertex-to-vertex
     (or is zero on overlap): box corners against the segment, segment endpoints against
     the box, and an overlap test. *)
  let corner_min2 = min4 d00 d10 d01 d11 in
  let e1 = aabb_dist2 x1 y1 qx0 qy0 qx1 qy1 in
  let e2 = aabb_dist2 x2 y2 qx0 qy0 qx1 qy1 in
  let segmin2 =
    if seg_intersects_box x1 y1 x2 y2 qx0 qy0 qx1 qy1
    then zero
    else F.min corner_min2 (F.min e1 e2)
  in
  if F.compare segmin2 acc.dmin2 < 0 then acc.dmin2 <- segmin2;
  if F.compare segmax2 acc.dub2 < 0 then acc.dub2 <- segmax2;
  (* This segment is the nearest one (within the scalar query's sign tie window) for
     *some* point of the box only if its min distance is within the running upper bound.
     [acc.dub2] may shrink later, making this check conservative — that only ever lets
     extra segments contribute sign possibilities, never excludes a real winner. For each
     candidate, the cross product is linear in the query point, so its range over the box
     is spanned by the corners; cross > 0 makes the scalar query report negative. *)
  if F.compare segmin2 (F.mul acc.dub2 range_sign_window) <= 0
  then (
    let abx = F.sub x2 x1 in
    let aby = F.sub y2 y1 in
    let[@inline] cross px py =
      F.sub (F.mul abx (F.sub py y1)) (F.mul aby (F.sub px x1))
    in
    let c00 = cross qx0 qy0 in
    let c10 = cross qx1 qy0 in
    let c01 = cross qx0 qy1 in
    let c11 = cross qx1 qy1 in
    let cmin = min4 c00 c10 c01 c11 in
    let cmax = max4 c00 c10 c01 c11 in
    let tol = F.mul cross_tol_rel (F.max (F.abs cmin) (F.abs cmax)) in
    if F.compare cmax (F.neg tol) > 0 then acc.can_neg <- true;
    if F.compare cmin tol <= 0 then acc.can_pos <- true)
;;

let rec visit_range t node qx0 qy0 qx1 qy1 acc =
  let left = Array.get t.nleft node in
  if left < 0
  then (
    let s = Array.get t.nstart node in
    let c = Array.get t.ncount node in
    for k = s to s + c - 1 do
      process_seg_range
        (Array.get t.sx1 k)
        (Array.get t.sy1 k)
        (Array.get t.sx2 k)
        (Array.get t.sy2 k)
        qx0
        qy0
        qx1
        qy1
        acc
    done)
  else (
    let right = Array.get t.nright node in
    let[@inline] gap2 n =
      box_box_gap2
        qx0
        qy0
        qx1
        qy1
        (Array.get t.nminx n)
        (Array.get t.nminy n)
        (Array.get t.nmaxx n)
        (Array.get t.nmaxy n)
    in
    let dl = gap2 left in
    let dr = gap2 right in
    (* A node is interesting only if some segment in it can either improve [dub2] or be a
       sign candidate; both require its gap to the box to be within
       [dub2 * range_sign_window] (the gap lower-bounds every per-segment quantity we
       track, including [dmin2 <= dub2]). Descend nearer child first so the bounds
       tighten before the farther child is tested; re-read [acc.dub2] for the second
       child. *)
    if F.compare dl dr <= 0
    then (
      if F.compare dl (F.mul acc.dub2 range_sign_window) <= 0
      then visit_range t left qx0 qy0 qx1 qy1 acc;
      if F.compare dr (F.mul acc.dub2 range_sign_window) <= 0
      then visit_range t right qx0 qy0 qx1 qy1 acc)
    else (
      if F.compare dr (F.mul acc.dub2 range_sign_window) <= 0
      then visit_range t right qx0 qy0 qx1 qy1 acc;
      if F.compare dl (F.mul acc.dub2 range_sign_window) <= 0
      then visit_range t left qx0 qy0 qx1 qy1 acc))
;;

(* Turn the accumulated bounds into a signed interval. Both unsigned bounds are padded
   outward (relative to the coordinate scale) before signs are applied. *)
let finish_range acc qx0 qy0 qx1 qy1 : Interval.t =
  let dmin = F.sqrt acc.dmin2 in
  let dub = F.sqrt acc.dub2 in
  let scale = max4 (F.abs qx0) (F.abs qy0) (F.abs qx1) (F.abs qy1) in
  let pad = F.mul range_pad_rel (F.add scale dub) in
  let dmin = F.max zero (F.sub dmin pad) in
  let dub = F.add dub pad in
  (* At least one sign flag is always set when there are segments (the segment achieving
     [dub2] passes its own candidacy check); fall back to both if not. *)
  let can_pos, can_neg =
    if acc.can_pos || acc.can_neg then acc.can_pos, acc.can_neg else true, true
  in
  let lo = if can_neg then F.neg dub else dmin in
  let hi = if can_pos then dub else F.neg dmin in
  #{ Interval.lo; hi }
;;

let query_range { portended = t } ~x_lo ~y_lo ~x_hi ~y_hi : Interval.t =
  let t = Obj.magic Obj.magic t in
  if t.seg_count = 0
  then #{ Interval.lo = F.infinity; hi = F.infinity }
  else (
    let qx0 = F.min x_lo x_hi in
    let qx1 = F.max x_lo x_hi in
    let qy0 = F.min y_lo y_hi in
    let qy1 = F.max y_lo y_hi in
    let acc = { dmin2 = F.infinity; dub2 = F.infinity; can_pos = false; can_neg = false } in
    visit_range t 0 qx0 qy0 qx1 qy1 acc;
    finish_range acc qx0 qy0 qx1 qy1)
;;

let query_range @ portable = Obj.magic_portable query_range

(* Brute-force O(n) reference implementation. [query] scans every segment, with no spatial
   pruning, using exactly the same per-segment distance and sign arithmetic as [scan_leaf]
   above. It exists so tests can bisimulate the real index against it: the only thing that
   can differ between the two is *which* segments get visited, never the formula. *)
module Dummy = struct
  type inner =
    { sx1 : float32# array
    ; sy1 : float32# array
    ; sx2 : float32# array
    ; sy2 : float32# array
    ; seg_count : int
    }

  type t = inner portended

  let build (coords : float32# array) ~length : t =
    let n = if length < 0 then 0 else length in
    let sx1 = Array.create ~len:n zero in
    let sy1 = Array.create ~len:n zero in
    let sx2 = Array.create ~len:n zero in
    let sy2 = Array.create ~len:n zero in
    for s = 0 to n - 1 do
      Array.set sx1 s (Array.get coords ((4 * s) + 0));
      Array.set sy1 s (Array.get coords ((4 * s) + 1));
      Array.set sx2 s (Array.get coords ((4 * s) + 2));
      Array.set sy2 s (Array.get coords ((4 * s) + 3))
    done;
    { portended = Obj.magic_portable__contended { sx1; sy1; sx2; sy2; seg_count = n } }
  ;;

  let query { portended = t } ~x:px ~y:py =
    let t = Obj.magic Obj.magic t in
    if t.seg_count = 0
    then F.infinity
    else (
      let best = Array.create ~len:3 F.infinity in
      Array.set best 1 one;
      Array.set best 2 zero;
      for k = 0 to t.seg_count - 1 do
        let x1 = Array.get t.sx1 k in
        let y1 = Array.get t.sy1 k in
        let x2 = Array.get t.sx2 k in
        let y2 = Array.get t.sy2 k in
        let abx = F.sub x2 x1 in
        let aby = F.sub y2 y1 in
        let apx = F.sub px x1 in
        let apy = F.sub py y1 in
        let len2 = F.add (F.mul abx abx) (F.mul aby aby) in
        let dot = F.add (F.mul apx abx) (F.mul apy aby) in
        let tparam =
          if F.compare len2 zero > 0
          then (
            let q = F.div dot len2 in
            if F.compare q zero < 0 then zero else if F.compare q one > 0 then one else q)
          else zero
        in
        let interior = F.compare tparam zero > 0 && F.compare tparam one < 0 in
        let cpx =
          if interior
          then F.add x1 (F.mul tparam abx)
          else if F.compare tparam zero > 0
          then x2
          else x1
        in
        let cpy =
          if interior
          then F.add y1 (F.mul tparam aby)
          else if F.compare tparam zero > 0
          then y2
          else y1
        in
        let dx = F.sub px cpx in
        let dy = F.sub py cpy in
        let d2 = F.add (F.mul dx dx) (F.mul dy dy) in
        if F.compare d2 (F.mul (Array.get best 0) one_plus_eps) <= 0
        then (
          let cross = F.sub (F.mul abx apy) (F.mul aby apx) in
          let line_d2 =
            if F.compare len2 zero > 0 then F.div (F.mul cross cross) len2 else zero
          in
          if F.compare d2 (F.mul (Array.get best 0) one_minus_eps) < 0
             || F.compare line_d2 (Array.get best 2) > 0
          then (
            let sign = if F.compare cross zero > 0 then neg_one else one in
            Array.set best 1 sign;
            Array.set best 2 line_d2);
          if F.compare d2 (Array.get best 0) < 0 then Array.set best 0 d2)
      done;
      F.mul (Array.get best 1) (F.sqrt (Array.get best 0)))
  ;;

  let query @ portable = Obj.magic_portable query

  (* Same per-segment range computation as the spatially-indexed [query_range], with no
     pruning at all: every segment is processed. *)
  let query_range { portended = t } ~x_lo ~y_lo ~x_hi ~y_hi : Interval.t =
    let t = Obj.magic Obj.magic t in
    if t.seg_count = 0
    then #{ Interval.lo = F.infinity; hi = F.infinity }
    else (
      let qx0 = F.min x_lo x_hi in
      let qx1 = F.max x_lo x_hi in
      let qy0 = F.min y_lo y_hi in
      let qy1 = F.max y_lo y_hi in
      let acc =
        { dmin2 = F.infinity; dub2 = F.infinity; can_pos = false; can_neg = false }
      in
      for k = 0 to t.seg_count - 1 do
        process_seg_range
          (Array.get t.sx1 k)
          (Array.get t.sy1 k)
          (Array.get t.sx2 k)
          (Array.get t.sy2 k)
          qx0
          qy0
          qx1
          qy1
          acc
      done;
      finish_range acc qx0 qy0 qx1 qy1)
  ;;

  let query_range @ portable = Obj.magic_portable query_range
end
