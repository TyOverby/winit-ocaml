
(** A spatial-partitioning index (a bounding-volume hierarchy) over a fixed set of 2D line
    segments, specialised for nearest-segment queries.

    Coordinates are unboxed [float32#] for cache-density and to interoperate with the rest
    of the codebase. *)

type t

(** [build coords] indexes the segments described by [coords]. The array is a flat,
    interleaved list of endpoints in the order [x1; y1; x2; y2] per segment, repeating, so
    its length must be a multiple of 4. Building is O(n log n). *)
val build : float32# array -> t

(** [query t ~x ~y] returns the signed distance from the point [(x, y)] to the nearest
    line segment in [t].

    The magnitude is the Euclidean distance to the closest point of the closest segment.
    The sign is taken from the side of that (directed) segment the query point lies on:
    positive if on the right of the directed segment [(x1,y1) -> (x2,y2)] (i.e. the segment
    winds clockwise around the point), negative if on the left. Sidedness is measured in a
    standard math orientation (x right, y up).

    Returns [+inf] for an empty index. Runs in O(log n) on well-distributed inputs. *)
val query : t -> x:float32# -> y:float32# -> float32#
