val create_instance : unit -> instance
val instance_request_adapter_sync : instance -> int -> int -> adapter
val adapter_request_device_sync : adapter -> device

type adapter_info =
  { vendor : string
  ; architecture : string
  ; device : string
  ; description : string
  ; backend_type : int
  ; adapter_type : int
  }

val adapter_get_info : adapter -> adapter_info
val queue_submit_single : queue -> command_buffer -> unit
val device_poll : device -> bool -> unit
val buffer_map_sync : buffer -> int -> int64 -> int64 -> int

val buffer_get_mapped_range_bigarray
  :  buffer
  -> int64
  -> int64
  -> (int, Bigarray.int8_unsigned_elt, Bigarray.c_layout) Bigarray.Array1.t

val buffer_get_const_mapped_range_bigarray
  :  buffer
  -> int64
  -> int64
  -> (int, Bigarray.int8_unsigned_elt, Bigarray.c_layout) Bigarray.Array1.t

val queue_write_buffer_bigarray
  :  queue
  -> buffer
  -> int64
  -> (_, _, Bigarray.c_layout) Bigarray.Array1.t
  -> unit

val device_create_bind_group_layout_storage
  :  device
  -> string
  -> int
  -> bool
  -> bind_group_layout

val device_create_bind_group_buffer
  :  device
  -> string
  -> bind_group_layout
  -> int
  -> buffer
  -> int64
  -> int64
  -> bind_group

val device_create_texture_2d : device -> string -> int -> int -> int -> int -> texture

val texture_create_view_configurable
  :  texture
  -> string
  -> int
  -> int
  -> int
  -> int
  -> int
  -> int
  -> int
  -> texture_view

val command_encoder_begin_render_pass_configurable
  :  command_encoder
  -> string
  -> texture_view
  -> int
  -> int
  -> float
  -> float
  -> float
  -> float
  -> render_pass_encoder

val device_create_render_pipeline_full
  :  device
  -> string
  -> shader_module
  -> string
  -> string
  -> int
  -> int
  -> int
  -> int
  -> bool
  -> int
  -> int
  -> int
  -> int
  -> int
  -> int
  -> int
  -> render_pipeline
