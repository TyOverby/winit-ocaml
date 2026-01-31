
  (** Poll the device for completed work *)
  val poll : t -> ?wait:bool -> unit -> unit
end

module Adapter : sig
  type t

  val get_info : t -> Adapter_info.t
  val request_device : t -> Device.t

  (* AUTO-GENERATED ADAPTER METHOD SIGNATURES INJECTED HERE *)
end

module Surface : sig
  (** An object used to continuously present image data to the user, see @ref Surfaces
      for more details. *)

  type t

  (** Create a Surface from a low-level surface handle (for platform-specific surface creation) *)
  val of_low_level : Wgpu_low.surface -> t

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

  val get_current_texture : t -> surface_texture

  (* get_capabilities not yet implemented - low-level array getters are stubs *)

  (* present, unconfigure, set_label, configure are auto-generated *)

  (* AUTO-GENERATED SURFACE METHOD SIGNATURES INJECTED HERE *)
end
