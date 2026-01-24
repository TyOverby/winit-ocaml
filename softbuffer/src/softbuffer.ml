(** OCaml bindings for softbuffer - Pixel buffer rendering *)

type surface

(** Damage rectangle *)
type damage_rect =
  { x : int
  ; y : int
  ; width : int
  ; height : int
  }

(* External C stubs *)
external create : Winit.window_handle -> surface = "caml_softbuffer_surface_create"

external resize
  :  surface
  -> width:int
  -> height:int
  -> unit
  = "caml_softbuffer_surface_resize"

external get_buffer
  :  surface
  -> int * int * (int32, Bigarray.int32_elt, Bigarray.c_layout) Bigarray.Array1.t
  = "caml_softbuffer_surface_get_buffer"

external get_buffer_age : surface -> int = "caml_softbuffer_surface_get_buffer_age"
external present : surface -> unit = "caml_softbuffer_surface_present"

external present_with_damage_impl
  :  surface
  -> (int * int * int * int) array
  -> unit
  = "caml_softbuffer_surface_present_with_damage"

let present_with_damage surface rects =
  let tuples = Array.map (fun r -> r.x, r.y, r.width, r.height) rects in
  present_with_damage_impl surface tuples
;;
