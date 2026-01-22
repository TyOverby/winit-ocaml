(** OCaml bindings for winit and softbuffer *)

(** Opaque type representing the application state *)
type app

(** Event types *)
type event_type =
  | NoEvent
  | CloseRequested
  | Resized
  | RedrawRequested
  | KeyPressed
  | KeyReleased
  | MouseMoved
  | MouseButtonPressed
  | MouseButtonReleased

(** An event with associated data *)
type event = {
  event_type : event_type;
  data1 : int;  (** Width, X coordinate, button ID, etc. *)
  data2 : int;  (** Height, Y coordinate, etc. *)
}

(** Create a new window and application *)
val create : unit -> app

(** Pump events from the window system. Returns a list of events. *)
val pump_events : app -> event list

(** Get the pixel buffer for drawing.
    Returns (width, height, buffer) where buffer is a bigarray of ARGB pixels. *)
val get_buffer : app -> (int * int * (int32, Bigarray.int32_elt, Bigarray.c_layout) Bigarray.Array1.t)

(** Present the current buffer to the screen *)
val present : app -> unit

(** Test function to verify FFI is working *)
val test_version : unit -> int
