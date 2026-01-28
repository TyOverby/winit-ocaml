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

  (** Begin a compute pass on this command encoder *)
  val begin_compute_pass : t -> ?label:string -> unit -> Compute_pass_encoder.t

  (** Begin a render pass on this command encoder with a single color attachment *)
  val begin_render_pass
    :  t
    -> ?label:string
    -> color_view:Texture_view.t
    -> ?load_op:Load_op.t
    -> ?store_op:Store_op.t
    -> clear_color:float * float * float * float
    -> unit
    -> Render_pass_encoder.t

  (* AUTO-GENERATED COMMAND_ENCODER METHOD SIGNATURES INJECTED HERE *)
end

module Queue : sig
  type t

  val write_buffer : t -> buffer:Buffer.t -> offset:int64 ->
    data:(int, Bigarray.int8_unsigned_elt, Bigarray.c_layout) Bigarray.Array1.t -> unit

  (* AUTO-GENERATED QUEUE METHOD SIGNATURES INJECTED HERE *)
end

module Device : sig
  type t

  (** Create a shader module from WGSL source *)
  val create_shader_module' : t -> ?label:string -> wgsl:string -> unit -> Shader_module.t

  (* create_compute_pipeline is now auto-generated *)

  (** Create a render pipeline (uses single shader module for vertex and fragment).
      The [blend] parameter is a tuple of (color_src, color_dst, color_op, alpha_src, alpha_dst, alpha_op). *)
  val create_render_pipeline : t -> ?label:string -> shader_module:Shader_module.t ->
    vertex_entry_point:string -> fragment_entry_point:string ->
    color_format:Texture_format.t ->
    ?topology:Primitive_topology.t -> ?front_face:Front_face.t ->
    ?cull_mode:Cull_mode.t ->
    ?blend:(Blend_factor.t * Blend_factor.t * Blend_operation.t *
            Blend_factor.t * Blend_factor.t * Blend_operation.t) ->
    ?write_mask:Color_write_mask.Item.t list ->
    unit -> Render_pipeline.t

  (** Create a bind group layout for a single storage buffer *)
  val create_bind_group_layout_for_storage_buffer : t -> ?label:string -> binding:int ->
    ?read_only:bool -> unit -> Bind_group_layout.t

  (* AUTO-GENERATED DEVICE METHOD SIGNATURES INJECTED HERE *)
