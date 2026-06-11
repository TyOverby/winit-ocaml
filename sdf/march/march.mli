@@ portable

(** [run grid output width height] extracts the zero contour of the [width] x [height]
    sample grid as line segments (4 floats each) written into [output], returning the
    segment count. Coordinates are in cell-index space. *)
val run : float32# array -> float32# array -> int -> int -> int

(** [run_offset] is [run] with the emitted coordinates translated as if the grid's first
    cell were global cell [(ox, oy)]. The offset is applied in integer arithmetic before
    any float math, so marching a tile of a larger grid produces segments bitwise
    identical to the corresponding segments of a dense run over the whole grid — which is
    what lets [line_join] stitch segments across tile seams by exact point equality. *)
val run_offset : float32# array -> float32# array -> int -> int -> ox:int -> oy:int -> int
