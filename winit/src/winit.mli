(** OCaml bindings for winit - Window creation and event handling *)

(** Opaque type representing a window *)
type window

(** Opaque type representing a window handle for use with Softbuffer *)
type window_handle

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

(** Tablet tool type *)
type tablet_tool_kind =
  | Pen (** Pen/stylus *)
  | Eraser (** Eraser end of stylus *)
  | Brush (** Brush tool *)
  | Pencil (** Pencil tool *)
  | Airbrush (** Airbrush tool *)
  | Finger (** Finger *)
  | TabletMouse (** Tablet puck/mouse *)
  | Lens (** Lens tool *)

(** Tablet-specific data (pressure, tilt, etc.) *)
type tablet_data =
  { pressure : float option (** Pressure 0.0-1.0, None if not available *)
  ; tilt_x : int option (** Tilt X in degrees -90 to 90, None if not available *)
  ; tilt_y : int option (** Tilt Y in degrees -90 to 90, None if not available *)
  ; tool_kind : tablet_tool_kind (** Type of tool *)
  }

(** Source of a pointer event *)
type pointer_source =
  | Mouse (** Traditional mouse pointer *)
  | Touch (** Touch screen or trackpad *)
  | Tablet of tablet_data (** Graphics tablet or stylus with tablet-specific data *)
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

(** Window level - controls z-ordering relative to other windows *)
type window_level =
  | Always_on_bottom (** Below all other windows *)
  | Normal (** Default window level *)
  | Always_on_top (** Above all other windows *)

(** Create a new window. This initializes the window system and creates a window.
    @param window_level Controls the z-ordering of the window. Default is [Normal].
    @param title The window title. Default is ["OCaml Window"].
    @param width The initial logical width in pixels. Default is [800].
    @param height The initial logical height in pixels. Default is [600]. *)
val create
  :  ?window_level:window_level
  -> ?title:string
  -> ?width:int
  -> ?height:int
  -> unit
  -> window

(** Pump events from the window system. This polls for new events and returns them as a
    list. Should be called regularly (e.g., once per frame) to keep the window responsive. *)
val pump_events : window -> event list

(** Get a window handle for use with Softbuffer. This handle can be passed to
    {!Softbuffer.create} to create a rendering surface for this window. *)
val get_handle : window -> window_handle

(** Test function to verify FFI is working. Returns 100 if the FFI is working correctly. *)
val test_version : unit -> int

(** {1 Window Size and Scaling} *)

(** Get the current surface size in physical pixels. This returns the actual framebuffer
    dimensions, accounting for DPI scaling. Use this for configuring rendering surfaces
    (wgpu, etc.) that need physical pixel dimensions.

    On HiDPI displays, this will be larger than the logical window size. For example, an
    800x600 logical window at 2x scale factor returns (1600, 1200). *)
val surface_size : window -> int * int

(** Get the window's DPI scale factor. This is the ratio between physical pixels and
    logical pixels (points). Common values:
    - 1.0 for standard displays
    - 2.0 for Retina/HiDPI displays
    - 1.25, 1.5, etc. for Windows display scaling *)
val scale_factor : window -> float

(** {1 Raw Window Handles for wgpu} *)

(** Raw window handle backend type - indicates which windowing system is in use *)
type raw_handle_backend =
  | X11 (** X11 (Xlib) on Linux *)
  | Wayland (** Wayland on Linux *)
  | Win32 (** Windows *)
  | AppKit (** macOS *)
  | Unknown_backend (** Unknown or unsupported backend *)

(** Raw window handle containing platform-specific data for wgpu surface creation. Only
    the fields corresponding to the backend type contain valid data. *)
type raw_window_handle =
  { backend : raw_handle_backend (** The windowing backend in use *)
  ; x11_display : nativeint (** X11 Display pointer (only valid when backend = X11) *)
  ; x11_window : int64 (** X11 Window ID (only valid when backend = X11) *)
  ; wayland_display : nativeint
  (** Wayland wl_display pointer (only valid when backend = Wayland) *)
  ; wayland_surface : nativeint
  (** Wayland wl_surface pointer (only valid when backend = Wayland) *)
  ; win32_hwnd : nativeint (** Win32 HWND (only valid when backend = Win32) *)
  ; win32_hinstance : nativeint (** Win32 HINSTANCE (only valid when backend = Win32) *)
  ; metal_layer : nativeint (** CAMetalLayer pointer (only valid when backend = AppKit) *)
  }

(** Get the raw window handle for creating wgpu surfaces. This returns platform-specific
    window handle data that can be used to create a wgpu Surface via the low-level
    wgpu-ocaml bindings. *)
val get_raw_handle : window -> raw_window_handle
