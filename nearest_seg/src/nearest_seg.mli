@@ portable

(** A spatial-partitioning index (a bounding-volume hierarchy) over a fixed set of 2D line
    segments, specialised for nearest-segment queries.

    Coordinates are unboxed [float32#] for cache-density and to interoperate with the rest
    of the codebase. *)

type t : value mod contended portable

(** [build coords ~length] indexes the first [length] segments described by [coords].
    [coords] is a flat, interleaved list of endpoints in the order [x1; y1; x2; y2] per
    segment, repeating; only the leading [length * 4] entries are read, so the buffer may
    be over-allocated (e.g. the partially-filled output of [sdf/march], whose returned
    count is exactly this [length]). Requires [length * 4 <= Array.length coords].
    Building is O(length log length).

    [assume_level_set] declares that the segments are the contour of a level set, as
    marching squares emits them: consistently wound chains that never cross mid-segment,
    whose shared vertices are bitwise-identical, and whose only sign discontinuities at
    nonzero magnitude are past open chain ends (where a contour was clipped at the
    sample-region boundary). Under that assumption {!query_range} may use a midpoint
    probe to resolve an otherwise-ambiguous sign, which makes its intervals dramatically
    tighter far from the contour (see {!query_range}). Do {e not} set it for arbitrary
    segment soups: two nearby same-wound strands (impossible in a level set) have a
    genuine sign discontinuity between them that the probe cannot detect, and the
    containment guarantee of {!query_range} would be lost. *)
val build : ?assume_level_set:bool -> float32# array -> length:int -> t

(** [query t ~x ~y] returns the signed distance from the point [(x, y)] to the nearest
    line segment in [t].

    The magnitude is the Euclidean distance to the closest point of the closest segment.
    The sign is taken from the side of that (directed) segment the query point lies on,
    chosen to give standard signed-distance-field semantics: negative inside, positive
    outside.

    Concretely, the index is built from contours wound clockwise (as drawn on screen, in
    image coordinates with x rightward and y downward) around solid regions, so that the
    inside sits on the right of each directed segment [(x1,y1) -> (x2,y2)] — this is the
    winding that [sdf/march] emits. With that input, [query] returns a negative distance
    for the right side (inside) and a positive distance for the left side (outside).

    The underlying rule is purely the sign of the 2D cross product
    [(x2-x1)*(y-y1) - (y2-y1)*(x-x1)]: it is negative when that cross product is positive.
    Feeding in segments wound the other way flips the sign of the whole field.

    When the nearest contour point is a vertex shared by two segments, the two report the
    same distance but may disagree on the side (the point lies beyond each segment's
    extent, where the infinite-line test of the more nearly collinear segment is
    meaningless). Candidates whose squared distances agree to within a few float32 ulps
    are therefore treated as ties (clamped projections also reuse the stored endpoint
    coordinates, so segments sharing a bitwise-identical vertex tie exactly), and the
    sign comes from the tying segment whose infinite line the query point deviates from
    the most (the 2D angle-weighted-pseudonormal rule), which gives the correct sign at
    every vertex of a consistently wound contour.

    Returns [+inf] for an empty index. Runs in O(log n) on well-distributed inputs. *)
val query : t -> x:float32# -> y:float32# -> float32#

(** An inclusive range of query results, as returned by {!query_range}. *)
module Interval : sig
  type t = #{ lo : float32#
            ; hi : float32#
            }
end

(** [query_range t ~x_lo ~y_lo ~x_hi ~y_hi] returns an interval guaranteed to contain
    [query t ~x ~y] for every point (x, y) of the axis-aligned box
    [x_lo, x_hi] × [y_lo, y_hi] (the bounds of each axis are swapped if given out of
    order). Coordinates must be finite.

    The magnitude bounds are the exact min distance from the box to the contour and a
    branch-and-bound upper bound on the max distance, both padded outward by a small
    epsilon relative to the coordinate scale to absorb float32 rounding (the scalar query
    computes its distance by a different float32 expression).

    The sign side is conservative: the interval covers a sign as soon as *some* segment
    that could be nearest for *some* point of the box lies on that side of the point, so
    boxes near the contour (or near a sign discontinuity, e.g. past the open end of an
    unclosed contour) report both signs even when every actual sample inside agrees. The
    result is therefore an over-approximation: every scalar query result falls inside it,
    but not every value inside it need be attainable.

    For an index built with [~assume_level_set:true], an ambiguous sign is additionally
    resolved by a {e midpoint probe}: a scalar query at the box centre. The signed field
    of a level-set contour is 1-Lipschitz wherever its sign is continuous, so when the
    centre value's magnitude exceeds the box's half-diagonal (plus float32 padding) the
    field cannot cross zero inside the box and the sign is decided. The probe is skipped
    whenever an {e unsafe vertex} — an open chain end, junction, or degenerate segment,
    where the sign can jump at nonzero magnitude — could be the nearest contour point of
    any box point, so those regions keep the conservative both-signs answer. Without the
    probe, far-from-the-contour boxes that overlap the contour's bounding box in one
    axis typically report both signs (perpendicular far edges of the contour enter the
    sign-candidate set), making the interval straddle zero needlessly.

    Returns [[+inf, +inf]] for an empty index. *)
val query_range
  :  t
  -> x_lo:float32#
  -> y_lo:float32#
  -> x_hi:float32#
  -> y_hi:float32#
  -> Interval.t

(** A brute-force O(n) reference implementation of the index, kept as a testing oracle.

    [build] and [query] have the same meaning and signed-distance semantics as the
    top-level {!val:build} and {!val:query}, but [query] simply scans every segment with no
    spatial pruning. It uses the same [float32#] arithmetic and the same tie-break rule as
    the real index, so the two agree except in degenerate cases where both the distance
    and the tie-break metric tie exactly across segments with different signs. Intended
    for bisimulation tests, not production use. *)
module Dummy : sig
  type t : value mod contended portable

  val build : ?assume_level_set:bool -> float32# array -> length:int -> t
  val query : t -> x:float32# -> y:float32# -> float32#

  (** Brute-force [query_range]: identical per-segment bounds and sign logic as the
      top-level {!val:query_range}, but scanning every segment. The two can differ only
      in tightness (the indexed version may skip segments that cannot affect the bounds),
      never in soundness. *)
  val query_range
    :  t
    -> x_lo:float32#
    -> y_lo:float32#
    -> x_hi:float32#
    -> y_hi:float32#
    -> Interval.t
end
