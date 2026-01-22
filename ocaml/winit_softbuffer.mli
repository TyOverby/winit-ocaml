(** OCaml bindings for winit and softbuffer *)

(** Opaque type representing the application state *)
type app

(** Physical key code - layout-independent key position. This is the scancode value from
    the keyboard hardware. *)
type key_code = int

(** Key location on the keyboard *)
type key_location =
  | Standard (** Most keys *)
  | Left (** Left variant of a key (e.g., left Shift) *)
  | Right (** Right variant of a key (e.g., right Shift) *)
  | Numpad (** Key on the numeric keypad *)

(** Modifier key state - tracks left and right keys separately *)
type modifier_key_state =
  | Unknown (** State is unknown or key is not pressed *)
  | LeftPressed (** Only the left variant is pressed *)
  | RightPressed (** Only the right variant is pressed *)
  | BothPressed (** Both left and right variants are pressed *)

(** Source of a pointer event *)
type pointer_source =
  | Mouse (** Traditional mouse pointer *)
  | Touch (** Touch screen or trackpad *)
  | Tablet (** Graphics tablet or stylus *)
  | Unknown (** Unknown pointer source *)

(** Mouse wheel delta type *)
type mouse_wheel_delta_type =
  | Line (** Delta in lines (typical for mouse wheels) *)
  | Pixel (** Delta in pixels (typical for trackpads) *)

(** Touch/gesture phase *)
type touch_phase =
  | Started (** Touch or gesture started *)
  | Moved (** Touch or gesture moved *)
  | Ended (** Touch or gesture ended *)
  | Cancelled (** Touch or gesture cancelled *)

(** Window theme *)
type theme =
  | Light (** Light color scheme *)
  | Dark (** Dark color scheme *)

(** Window events. These are the events that can be received from the window system. *)
type event =
  | NoEvent (** Placeholder event *)
  | CloseRequested (** User requested to close the window *)
  | SurfaceResized of
      { width : int (** New width in pixels *)
      ; height : int (** New height in pixels *)
      } (** Window surface was resized *)
  | RedrawRequested (** Window needs to be redrawn *)
  | KeyPressed of
      { key_code : key_code (** Physical key code (scancode) *)
      ; location : key_location (** Location of the key on keyboard *)
      ; repeat : bool (** True if this is a key-repeat event *)
      } (** A keyboard key was pressed *)
  | KeyReleased of
      { key_code : key_code (** Physical key code (scancode) *)
      ; location : key_location (** Location of the key on keyboard *)
      ; repeat : bool (** Always false for release events *)
      } (** A keyboard key was released *)
  | ModifiersChanged of
      { shift : modifier_key_state (** Shift key state *)
      ; control : modifier_key_state (** Control key state *)
      ; alt : modifier_key_state (** Alt key state *)
      ; super : modifier_key_state (** Super/Windows/Command key state *)
      } (** Keyboard modifiers changed *)
  | PointerMoved of
      { x : float (** X coordinate relative to window *)
      ; y : float (** Y coordinate relative to window *)
      ; primary : bool (** True if this is the primary pointer *)
      ; source : pointer_source (** Source of the pointer event *)
      } (** Pointer moved within the window *)
  | PointerEntered of
      { x : float (** X coordinate where pointer entered *)
      ; y : float (** Y coordinate where pointer entered *)
      ; primary : bool (** True if this is the primary pointer *)
      ; source : pointer_source (** Source of the pointer event *)
      } (** Pointer entered the window *)
  | PointerLeft of
      { x : float (** X coordinate where pointer left (may be outside window) *)
      ; y : float (** Y coordinate where pointer left (may be outside window) *)
      ; primary : bool (** True if this is the primary pointer *)
      ; source : pointer_source (** Source of the pointer event *)
      } (** Pointer left the window *)
  | PointerButtonPressed of
      { button : int
      (** Button ID (1=Left, 2=Right, 3=Middle, 4=Back, 5=Forward, >5=Other) *)
      ; x : float (** X coordinate when button was pressed *)
      ; y : float (** Y coordinate when button was pressed *)
      ; primary : bool (** True if this is the primary pointer *)
      } (** Pointer button was pressed *)
  | PointerButtonReleased of
      { button : int
      (** Button ID (1=Left, 2=Right, 3=Middle, 4=Back, 5=Forward, >5=Other) *)
      ; x : float (** X coordinate when button was released *)
      ; y : float (** Y coordinate when button was released *)
      ; primary : bool (** True if this is the primary pointer *)
      } (** Pointer button was released *)
  | MouseWheel of
      { delta_type : mouse_wheel_delta_type (** Type of delta measurement *)
      ; x : float (** Horizontal scroll amount *)
      ; y : float (** Vertical scroll amount *)
      ; phase : touch_phase (** Scroll gesture phase *)
      } (** Mouse wheel or trackpad scroll *)
  | Focused (** Window gained focus *)
  | Unfocused (** Window lost focus *)
  | WindowMoved of
      { x : int (** New X position in screen coordinates *)
      ; y : int (** New Y position in screen coordinates *)
      } (** Window was moved *)
  | Destroyed (** Window was destroyed *)
  | Occluded (** Window is completely hidden from view *)
  | Unoccluded (** Window is no longer completely hidden *)
  | ThemeChanged of theme (** System theme changed *)
  | ScaleFactorChanged of float (** Window DPI scale factor changed *)

(** Create a new window and application. This initializes the window system and creates a
    window. *)
val create : unit -> app

(** Pump events from the window system. This polls for new events and returns them as a
    list. Should be called regularly (e.g., once per frame) to keep the window responsive. *)
val pump_events : app -> event list

(** Get the pixel buffer for drawing. Returns (width, height, buffer) where buffer is a
    bigarray of ARGB pixels.

    The buffer format is 32-bit ARGB (0xAARRGGBB) with pixels in row-major order. After
    drawing, call {!present} to display the buffer on screen.

    The buffer becomes invalid after calling {!present}, so you must call {!get_buffer}
    again for the next frame. *)
val get_buffer
  :  app
  -> int * int * (int32, Bigarray.int32_elt, Bigarray.c_layout) Bigarray.Array1.t

(** Present the current buffer to the screen. This displays the pixels you've drawn and
    invalidates the buffer. You must call {!get_buffer} again to get a new buffer for the
    next frame. *)
val present : app -> unit

(** Test function to verify FFI is working. Returns 100 if the FFI is working correctly. *)
val test_version : unit -> int
