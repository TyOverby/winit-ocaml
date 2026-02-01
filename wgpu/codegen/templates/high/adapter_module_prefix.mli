module Adapter_info : sig
  type t =
    { vendor : string
    ; architecture : string
    ; device : string
    ; description : string
    ; backend_type : Backend_type.t
    ; adapter_type : Adapter_type.t
    }
end

module Command_encoder : sig
  type t

  (** Begin a compute pass on this command encoder (simple convenience function) *)
  val begin_compute_pass_simple : t -> ?label:string -> unit -> Compute_pass_encoder.t

  (** Begin a render pass on this command encoder with a single color attachment
      and optional depth attachment (simple convenience function).
      If [depth_view] is provided, depth testing will be enabled.
      If [resolve_target] is provided, MSAA resolve will be performed. *)
  val begin_render_pass_simple
    :  t
    -> ?label:string
    -> color_view:Texture_view.t
    -> ?load_op:Load_op.t
    -> ?store_op:Store_op.t
    -> clear_color:float * float * float * float
    -> ?depth_view:Texture_view.t
    -> ?depth_load_op:Load_op.t
    -> ?depth_store_op:Store_op.t
    -> ?depth_clear_value:float
    -> ?resolve_target:Texture_view.t
    -> unit
    -> Render_pass_encoder.t

  (* AUTO-GENERATED COMMAND_ENCODER METHOD SIGNATURES INJECTED HERE *)
end

module Queue : sig
  type t

  val write_buffer : t -> buffer:Buffer.t -> offset:int64 ->
    data:(_, _, Bigarray.c_layout) Bigarray.Array1.t -> unit

  val write_texture
    :  t
    -> destination_texture:Texture.t
    -> destination_mip_level:int
    -> destination_origin_x:int
    -> destination_origin_y:int
    -> destination_origin_z:int
    -> destination_aspect:Texture_aspect.t
    -> data_layout_offset:int64
    -> data_layout_bytes_per_row:int
    -> data_layout_rows_per_image:int
    -> write_size_width:int
    -> write_size_height:int
    -> write_size_depth_or_array_layers:int
    -> data:(_, _, Bigarray.c_layout) Bigarray.Array1.t
    -> unit
    -> unit

  (* AUTO-GENERATED QUEUE METHOD SIGNATURES INJECTED HERE *)
end

module Device : sig
  type t

  (** Create a shader module from WGSL source code *)
  val create_shader_module : t -> ?label:string -> wgsl:string -> unit -> Shader_module.t

  (* create_compute_pipeline and create_render_pipeline are now auto-generated *)

  (** Create a bind group layout for a single storage buffer *)
  val create_bind_group_layout_for_storage_buffer : t -> ?label:string -> binding:int ->
    ?read_only:bool -> unit -> Bind_group_layout.t

  (** Create a bind group layout for a single uniform buffer *)
  val create_bind_group_layout_for_uniform_buffer : t -> ?label:string -> binding:int ->
    visibility:Shader_stage.Item.t list -> unit -> Bind_group_layout.t

  (* AUTO-GENERATED DEVICE METHOD SIGNATURES INJECTED HERE *)
