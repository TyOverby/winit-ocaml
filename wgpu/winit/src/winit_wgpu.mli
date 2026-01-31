(** Bridge library for creating wgpu surfaces from winit windows *)

(** Create a wgpu Surface from a winit window and wgpu Instance. This function detects the
    windowing backend (X11 or Wayland) and creates the appropriate surface.

    @param instance The wgpu Instance to use
    @param window The winit window to create the surface for
    @raise Failure if the window uses an unsupported backend *)
val create_surface : instance:Wgpu.Instance.t -> window:Winit.window -> Wgpu.Surface.t
