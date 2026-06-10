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
end
