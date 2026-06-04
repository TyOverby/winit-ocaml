open! Core
module Id : Core.Unique_id.Id

type t

val parse : float32# array -> length:int -> t
val remove : t -> Id.t -> unit
val lookup_line : t -> Id.t -> Line.t
val first : t -> Id.t
val find_by_start : t -> Point.t -> Id.t option
val find_by_end : t -> Point.t -> Id.t option
val is_empty : t -> bool
