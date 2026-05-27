@@ portable

open! Base

module Rect : sig
  type t =
    #{ x : int
     ; y : int
     ; w : int
     ; h : int
     }
end

type t : value mod contended portable

val create : ?transparency:bool -> width:int -> height:int -> int32# -> t

val from_external
  :  ?transparency:bool
  -> width:int
  -> height:int
  -> (int32, Bigarray.int32_elt, Bigarray.c_layout) Bigarray.Array1.t
  -> t

(* property getters *)
val width : t -> int
val height : t -> int
val transparency : t -> bool

(* pixel manipulation *)
val get : t -> x:int -> y:int -> int32#
val set : t -> x:int -> y:int -> int32# -> unit

(** Copies a rectangular region of pixels from [from] into [to_]. [region] is in [from]'s
    pixel coordinates, while [x] and [y] specify the top-left pixel in the destination
    image. *)
val blit : from:t -> region:Rect.t -> to_:t -> x:int -> y:int -> unit

module For_testing : sig
  (** Produces a string containing a grid, where each pixel is represented by an ascii
      character:

      - `R` if the pixel is pure red
      - `G` if the pixel is pure green
      - `B` if the pixel is pure blue
      - `_` if the pixel is black or fully transparent
      - `?` in any other scenario *)
  val to_string : t -> string
end
