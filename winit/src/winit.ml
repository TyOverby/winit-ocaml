(** OCaml bindings for winit - Window creation and event handling *)

type window
type window_handle

(** Physical key code - layout-independent key position *)
type key_code = int

(** Key location on the keyboard *)
type key_location =
  | Standard
  | Left
  | Right
  | Numpad

(** Modifier key state *)
type modifier_key_state =
  | Unknown
  | LeftPressed
  | RightPressed
  | BothPressed

(** Tablet tool type *)
type tablet_tool_kind =
  | Pen
  | Eraser
  | Brush
  | Pencil
  | Airbrush
  | Finger
  | TabletMouse
  | Lens

(** Tablet-specific data (pressure, tilt, etc.) *)
type tablet_data =
  { pressure : float option
  ; tilt_x : int option
  ; tilt_y : int option
  ; tool_kind : tablet_tool_kind
  }

(** Pointer source type *)
type pointer_source =
  | Mouse
  | Touch
  | Tablet of tablet_data
  | Unknown

(** Mouse wheel delta type *)
type mouse_wheel_delta_type =
  | Line
  | Pixel

(** Touch phase *)
type touch_phase =
  | Started
  | Moved
  | Ended
  | Cancelled

(** Window theme *)
type theme =
  | Light
  | Dark

(** Window event types *)
type event =
  | NoEvent
  | CloseRequested
  | SurfaceResized of
      { width : int
      ; height : int
      }
  | RedrawRequested
  | KeyPressed of
      { key_code : key_code
      ; location : key_location
      ; repeat : bool
      }
  | KeyReleased of
      { key_code : key_code
      ; location : key_location
      ; repeat : bool
      }
  | ModifiersChanged of
      { shift : modifier_key_state
      ; control : modifier_key_state
      ; alt : modifier_key_state
      ; super : modifier_key_state
      }
  | PointerMoved of
      { x : float
      ; y : float
      ; primary : bool
      ; source : pointer_source
      }
  | PointerEntered of
      { x : float
      ; y : float
      ; primary : bool
      ; source : pointer_source
      }
  | PointerLeft of
      { x : float
      ; y : float
      ; primary : bool
      ; source : pointer_source
      }
  | PointerButtonPressed of
      { button : int
      ; x : float
      ; y : float
      ; primary : bool
      }
  | PointerButtonReleased of
      { button : int
      ; x : float
      ; y : float
      ; primary : bool
      }
  | MouseWheel of
      { delta_type : mouse_wheel_delta_type
      ; x : float
      ; y : float
      ; phase : touch_phase
      }
  | Focused
  | Unfocused
  | WindowMoved of
      { x : int
      ; y : int
      }
  | Destroyed
  | Occluded
  | Unoccluded
  | ThemeChanged of theme
  | ScaleFactorChanged of float

(** Window level - controls z-ordering relative to other windows *)
type window_level =
  | Always_on_bottom
  | Normal
  | Always_on_top

(* External C stubs *)
external create_raw : int -> string -> int -> int -> window = "caml_winit_window_create"

let create
  ?(window_level = Normal)
  ?(title = "OCaml Window")
  ?(width = 800)
  ?(height = 600)
  ()
  =
  let level =
    match window_level with
    | Always_on_bottom -> 0
    | Normal -> 1
    | Always_on_top -> 2
  in
  create_raw level title width height
;;

external pump_events_raw
  :  window
  -> (int * int array) array
  = "caml_winit_window_pump_events"

external get_handle : window -> window_handle = "caml_winit_window_get_handle"
external test_version : unit -> int = "caml_winit_test_version"
external surface_size : window -> int * int = "caml_winit_window_surface_size"
external scale_factor : window -> float = "caml_winit_window_scale_factor"

(* Helper to decode f64 from two i32s *)
let decode_f64 low high =
  let low_bits = Int64.logand (Int64.of_int low) 0xFFFFFFFFL in
  let high_bits = Int64.logand (Int64.of_int high) 0xFFFFFFFFL in
  let bits = Int64.logor low_bits (Int64.shift_left high_bits 32) in
  Int64.float_of_bits bits
;;

(* Helper to decode f32 from i32 *)
let decode_f32 bits = Int32.float_of_bits (Int32.of_int bits)

let key_location_of_int : int -> key_location = function
  | 0 -> Standard
  | 1 -> Left
  | 2 -> Right
  | 3 -> Numpad
  | _ -> Standard
;;

let modifier_key_state_of_int : int -> modifier_key_state = function
  | 0 -> Unknown
  | 1 -> LeftPressed
  | 2 -> RightPressed
  | 3 -> BothPressed
  | _ -> Unknown
;;

let tablet_tool_kind_of_int = function
  | 0 -> Pen
  | 1 -> Eraser
  | 2 -> Brush
  | 3 -> Pencil
  | 4 -> Airbrush
  | 5 -> Finger
  | 6 -> TabletMouse
  | 7 -> Lens
  | _ -> Pen
;;

let decode_tablet_data data =
  let pressure = if data.(6) = 0 then None else Some (decode_f32 data.(6)) in
  let tilt_x = if data.(7) = 0 then None else Some data.(7) in
  let tilt_y = if data.(8) = 0 then None else Some data.(8) in
  let tool_kind = tablet_tool_kind_of_int data.(9) in
  { pressure; tilt_x; tilt_y; tool_kind }
;;

let pointer_source_of_int data source_int =
  match source_int with
  | 0 -> Mouse
  | 1 -> Touch
  | 2 -> Tablet (decode_tablet_data data)
  | 3 -> Unknown
  | _ -> Unknown
;;

let mouse_wheel_delta_type_of_int = function
  | 0 -> Line
  | 1 -> Pixel
  | _ -> Line
;;

let touch_phase_of_int = function
  | 0 -> Started
  | 1 -> Moved
  | 2 -> Ended
  | 3 -> Cancelled
  | _ -> Started
;;

let theme_of_int = function
  | 0 -> Light
  | 1 -> Dark
  | _ -> Light
;;

let event_of_raw event_type data =
  match event_type with
  | 0 -> NoEvent
  | 1 -> CloseRequested
  | 2 -> SurfaceResized { width = data.(0); height = data.(1) }
  | 3 -> RedrawRequested
  | 4 ->
    KeyPressed
      { key_code = data.(0)
      ; location = key_location_of_int data.(1)
      ; repeat = data.(2) <> 0
      }
  | 5 ->
    KeyReleased
      { key_code = data.(0)
      ; location = key_location_of_int data.(1)
      ; repeat = data.(2) <> 0
      }
  | 6 ->
    PointerMoved
      { x = decode_f64 data.(0) data.(1)
      ; y = decode_f64 data.(2) data.(3)
      ; primary = data.(4) <> 0
      ; source = pointer_source_of_int data data.(5)
      }
  | 7 ->
    PointerButtonPressed
      { button = data.(0)
      ; x = decode_f64 data.(1) data.(2)
      ; y = decode_f64 data.(3) data.(4)
      ; primary = data.(5) <> 0
      }
  | 8 ->
    PointerButtonReleased
      { button = data.(0)
      ; x = decode_f64 data.(1) data.(2)
      ; y = decode_f64 data.(3) data.(4)
      ; primary = data.(5) <> 0
      }
  | 9 ->
    PointerEntered
      { x = decode_f64 data.(0) data.(1)
      ; y = decode_f64 data.(2) data.(3)
      ; primary = data.(4) <> 0
      ; source = pointer_source_of_int data data.(5)
      }
  | 10 ->
    PointerLeft
      { x = decode_f64 data.(0) data.(1)
      ; y = decode_f64 data.(2) data.(3)
      ; primary = data.(4) <> 0
      ; source = pointer_source_of_int data data.(5)
      }
  | 11 ->
    MouseWheel
      { delta_type = mouse_wheel_delta_type_of_int data.(0)
      ; x = decode_f32 data.(1)
      ; y = decode_f32 data.(2)
      ; phase = touch_phase_of_int data.(3)
      }
  | 12 -> Focused
  | 13 -> Unfocused
  | 14 -> WindowMoved { x = data.(0); y = data.(1) }
  | 15 ->
    ModifiersChanged
      { shift = modifier_key_state_of_int data.(0)
      ; control = modifier_key_state_of_int data.(1)
      ; alt = modifier_key_state_of_int data.(2)
      ; super = modifier_key_state_of_int data.(3)
      }
  | 16 -> Destroyed
  | 17 -> Occluded
  | 18 -> Unoccluded
  | 19 -> ThemeChanged (theme_of_int data.(0))
  | 20 -> ScaleFactorChanged (decode_f64 data.(0) data.(1))
  | _ -> NoEvent
;;

let pump_events window =
  let raw_events = pump_events_raw window in
  Array.to_list (Array.map (fun (et, data) -> event_of_raw et data) raw_events)
;;

(** Raw window handle backend type *)
type raw_handle_backend =
  | X11
  | Wayland
  | Win32
  | AppKit
  | Unknown_backend

(** Raw window handle containing platform-specific data for wgpu surface creation *)
type raw_window_handle =
  { backend : raw_handle_backend
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

(* Raw C stub for getting raw handle *)
external get_raw_handle_raw
  :  window
  -> int * nativeint * int64 * nativeint * nativeint * nativeint * nativeint * nativeint
  = "caml_winit_window_get_raw_handle"

let raw_handle_backend_of_int = function
  | 0 -> X11
  | 1 -> Wayland
  | 2 -> Win32
  | 3 -> AppKit
  | _ -> Unknown_backend
;;

(** Get the raw window handle for creating wgpu surfaces. The returned handle contains
    platform-specific data (X11, Wayland, Win32, etc.) *)
let get_raw_handle window =
  let ( backend_int
      , x11_display
      , x11_window
      , wayland_display
      , wayland_surface
      , win32_hwnd
      , win32_hinstance
      , metal_layer )
    =
    get_raw_handle_raw window
  in
  { backend = raw_handle_backend_of_int backend_int
  ; x11_display
  ; x11_window
  ; wayland_display
  ; wayland_surface
  ; win32_hwnd
  ; win32_hinstance
  ; metal_layer
  }
;;
