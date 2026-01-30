(** Bridge library for creating wgpu surfaces from winit windows *)

(** Create a wgpu Surface from a winit window and wgpu Instance. This function detects the
    windowing backend (X11 or Wayland) and creates the appropriate surface. *)
let create_surface ~instance ~window =
  let raw_handle = Winit.get_raw_handle window in
  let instance_handle = Wgpu.Instance.to_low_level instance in
  let surface_handle =
    match raw_handle.backend with
    | Winit.X11 ->
      let source =
        Wgpu_low.Surface_source_xlib_window.surface_source_xlib_window_create ()
      in
      Wgpu_low.Surface_source_xlib_window.surface_source_xlib_window_set_chain_stype
        source
        (Wgpu_low.S_type.to_int Wgpu_low.S_type.Surface_source_xlib_window);
      Wgpu_low.Surface_source_xlib_window.surface_source_xlib_window_set_display
        source
        raw_handle.x11_display;
      Wgpu_low.Surface_source_xlib_window.surface_source_xlib_window_set_window
        source
        raw_handle.x11_window;
      let chained =
        Wgpu_low.Surface_source_xlib_window.surface_source_xlib_window_as_chained source
      in
      let desc = Wgpu_low.Surface_descriptor.surface_descriptor_create () in
      Wgpu_low.Surface_descriptor.surface_descriptor_set_next_in_chain desc chained;
      let surface = Wgpu_low.instance_create_surface instance_handle desc in
      Wgpu_low.Surface_descriptor.surface_descriptor_free desc;
      Wgpu_low.Surface_source_xlib_window.surface_source_xlib_window_free source;
      surface
    | Winit.Wayland ->
      let source =
        Wgpu_low.Surface_source_wayland_surface.surface_source_wayland_surface_create ()
      in
      Wgpu_low.Surface_source_wayland_surface
      .surface_source_wayland_surface_set_chain_stype
        source
        (Wgpu_low.S_type.to_int Wgpu_low.S_type.Surface_source_wayland_surface);
      Wgpu_low.Surface_source_wayland_surface.surface_source_wayland_surface_set_display
        source
        raw_handle.wayland_display;
      Wgpu_low.Surface_source_wayland_surface.surface_source_wayland_surface_set_surface
        source
        raw_handle.wayland_surface;
      let chained =
        Wgpu_low.Surface_source_wayland_surface.surface_source_wayland_surface_as_chained
          source
      in
      let desc = Wgpu_low.Surface_descriptor.surface_descriptor_create () in
      Wgpu_low.Surface_descriptor.surface_descriptor_set_next_in_chain desc chained;
      let surface = Wgpu_low.instance_create_surface instance_handle desc in
      Wgpu_low.Surface_descriptor.surface_descriptor_free desc;
      Wgpu_low.Surface_source_wayland_surface.surface_source_wayland_surface_free source;
      surface
    | Winit.Win32 ->
      let source =
        Wgpu_low.Surface_source_windows_hwnd.surface_source_windows_HWND_create ()
      in
      Wgpu_low.Surface_source_windows_hwnd.surface_source_windows_HWND_set_chain_stype
        source
        (Wgpu_low.S_type.to_int Wgpu_low.S_type.Surface_source_windows_hwnd);
      Wgpu_low.Surface_source_windows_hwnd.surface_source_windows_HWND_set_hwnd
        source
        raw_handle.win32_hwnd;
      Wgpu_low.Surface_source_windows_hwnd.surface_source_windows_HWND_set_hinstance
        source
        raw_handle.win32_hinstance;
      let chained =
        Wgpu_low.Surface_source_windows_hwnd.surface_source_windows_HWND_as_chained source
      in
      let desc = Wgpu_low.Surface_descriptor.surface_descriptor_create () in
      Wgpu_low.Surface_descriptor.surface_descriptor_set_next_in_chain desc chained;
      let surface = Wgpu_low.instance_create_surface instance_handle desc in
      Wgpu_low.Surface_descriptor.surface_descriptor_free desc;
      Wgpu_low.Surface_source_windows_hwnd.surface_source_windows_HWND_free source;
      surface
    | Winit.AppKit | Winit.Unknown_backend ->
      failwith "Unsupported window backend for wgpu surface creation"
  in
  Wgpu.Surface.of_low_level surface_handle
;;
