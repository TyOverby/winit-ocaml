(** OCaml bindings for softbuffer - Pixel buffer rendering *)

(** Opaque type representing a rendering surface *)
type surface

(** A rectangular region of the buffer for damage tracking *)
type damage_rect =
  { x : int (** X coordinate of top left corner *)
  ; y : int (** Y coordinate of top left corner *)
  ; width : int (** Width of the rectangle (must be > 0) *)
  ; height : int (** Height of the rectangle (must be > 0) *)
  }

(** Create a new rendering surface for a window. The window handle should be obtained from
    {!Winit.get_handle}. *)
val create : Winit.window_handle -> surface

(** Resize the surface to match a new window size. Should be called when receiving
    {!Winit.SurfaceResized} events. *)
val resize : surface -> width:int -> height:int -> unit

(** Get the pixel buffer for drawing. Returns (width, height, buffer) where buffer is a
    bigarray of ARGB pixels.

    The buffer format is 32-bit ARGB (0xAARRGGBB) with pixels in row-major order. After
    drawing, call {!present} to display the buffer on screen.

    The buffer becomes invalid after calling {!present}, so you must call {!get_buffer}
    again for the next frame. *)
val get_buffer
  :  surface
  -> int * int * (int32, Bigarray.int32_elt, Bigarray.c_layout) Bigarray.Array1.t

(** Get the age of the current buffer. Returns the number of frames ago this buffer was
    last presented:
    - 0 means it's a new buffer with unspecified contents (must redraw everything)
    - 1 means it's the same as the last frame (can use damage regions)
    - 2+ means it's from even earlier frames (for triple-buffering)

    This is useful for optimizing redraws when using {!present_with_damage}. *)
val get_buffer_age : surface -> int

(** Present the current buffer to the screen. This displays the pixels you've drawn and
    invalidates the buffer. You must call {!get_buffer} again to get a new buffer for the
    next frame. *)
val present : surface -> unit

(** Present the current buffer with damage regions. This is like {!present} but tells the
    window system which regions of the buffer have changed, allowing it to optimize the
    display update.

    Platform support:
    - Supported on Wayland, X11 (with XShm), Win32, Web
    - Falls back to full present on unsupported platforms

    Use {!get_buffer_age} to determine if you need to redraw everything (age=0) or can use
    damage regions (age>=1).

    @param damage_rects Array of rectangles that have changed since the last frame *)
val present_with_damage : surface -> damage_rect array -> unit
