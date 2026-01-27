module Instance : sig
  type t

  val create : unit -> t
  val release : t -> unit

  val request_adapter
    :  t
    -> ?power_preference:Power_preference.t
    -> ?backend_type:Backend_type.t
    -> unit
    -> Adapter.t
end

(** Begin a compute pass on a command encoder *)
val begin_compute_pass
  :  Command_encoder.t
  -> ?label:string
  -> unit
  -> Compute_pass_encoder.t

(** Begin a render pass on a command encoder with a single color attachment *)
val begin_render_pass
  :  Command_encoder.t
  -> ?label:string
  -> color_view:Texture_view.t
  -> ?load_op:Load_op.t
  -> ?store_op:Store_op.t
  -> clear_color:float * float * float * float
  -> unit
  -> Render_pass_encoder.t

(** Finish recording commands and get a command buffer *)
val finish : Command_encoder.t -> ?label:string -> unit -> Command_buffer.t

(** Set a bind group on a compute pass encoder *)
val set_bind_group
  :  Compute_pass_encoder.t
  -> index:int
  -> bind_group:Bind_group.t
  -> unit

(** Set a bind group on a render pass encoder *)
val set_bind_group_render
  :  Render_pass_encoder.t
  -> index:int
  -> bind_group:Bind_group.t
  -> unit

(** Copy texture to buffer (for readback) *)
val copy_texture_to_buffer
  :  Command_encoder.t
  -> texture:Texture.t
  -> buffer:Buffer.t
  -> size:int * int
  -> bytes_per_row:int
  -> unit
  -> unit

(** Map a buffer for CPU access (synchronous) *)
val map_buffer
  :  Buffer.t
  -> mode:Map_mode.Item.t list
  -> offset:int64
  -> size:int64
  -> unit

(** Get mapped buffer data as a bigarray *)
val get_mapped_range
  :  Buffer.t
  -> offset:int64
  -> size:int64
  -> (int, Bigarray.int8_unsigned_elt, Bigarray.c_layout) Bigarray.Array1.t

(** Get const mapped buffer data as a bigarray (for read-only access) *)
val get_const_mapped_range
  :  Buffer.t
  -> offset:int64
  -> size:int64
  -> (int, Bigarray.int8_unsigned_elt, Bigarray.c_layout) Bigarray.Array1.t

(** Create a texture view from a texture *)
val create_texture_view
  :  Texture.t
  -> ?label:string
  -> ?format:Texture_format.t
  -> ?dimension:Texture_view_dimension.t
  -> ?aspect:Texture_aspect.t
  -> ?base_mip_level:int
  -> ?mip_level_count:int
  -> ?base_array_layer:int
  -> ?array_layer_count:int
  -> unit
  -> Texture_view.t
