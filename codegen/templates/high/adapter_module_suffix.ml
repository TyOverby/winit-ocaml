
  let poll t ?(wait = false) () = Wgpu_low.device_poll t.handle wait
end

module Adapter = struct
  type t = { handle : Wgpu_low.adapter }

  let get_info t = Adapter_info.of_low (Wgpu_low.adapter_get_info t.handle)
  let request_device t =
    let device = Wgpu_low.adapter_request_device_sync t.handle in
    { Device.handle = device }

  (* AUTO-GENERATED ADAPTER METHODS INJECTED HERE *)
end

module Surface = struct
  type t = { handle : Wgpu_low.surface }

  type surface_capabilities =
    { usages : Texture_usage.Item.t list
    ; formats : Texture_format.t list
    ; present_modes : Present_mode.t list
    ; alpha_modes : Composite_alpha_mode.t list
    }

  type surface_texture =
    { texture : Texture.t
    ; status : Surface_get_current_texture_status.t
    }

  let get_current_texture t =
    let output = Wgpu_low.Surface_texture.surface_texture_create () in
    let _status = Wgpu_low.surface_get_current_texture t.handle output in
    let texture =
      ({ Texture.handle = Wgpu_low.Surface_texture.surface_texture_get_texture output }
       : Texture.t)
    in
    let status =
      Surface_get_current_texture_status.of_int
        (Wgpu_low.Surface_texture.surface_texture_get_status output)
    in
    let result = { texture; status } in
    Wgpu_low.Surface_texture.surface_texture_free output;
    result
  ;;

  (* get_capabilities not yet implemented - low-level array getters are stubs *)

  (* present, unconfigure, set_label, configure are auto-generated *)

  (* AUTO-GENERATED SURFACE METHODS INJECTED HERE *)
end
