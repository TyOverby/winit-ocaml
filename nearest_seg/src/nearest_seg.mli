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
    Building is O(length log length). *)
val build : float32# array -> length:int -> t

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

(** A brute-force O(n) reference implementation of the index, kept as a testing oracle.

    [build] and [query] have the same meaning and signed-distance semantics as the
    top-level {!val:build} and {!val:query}, but [query] simply scans every segment with no
    spatial pruning. It uses the same [float32#] arithmetic and the same tie-break rule as
    the real index, so the two agree except in degenerate cases where both the distance
    and the tie-break metric tie exactly across segments with different signs. Intended
    for bisimulation tests, not production use. *)
module Dummy : sig
  type t : value mod contended portable

  val build : float32# array -> length:int -> t
  val query : t -> x:float32# -> y:float32# -> float32#
end
