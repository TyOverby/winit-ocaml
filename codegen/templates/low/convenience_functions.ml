external create_instance : unit -> instance = "caml_wgpu_create_instance"

external instance_request_adapter_sync
  :  instance
  -> int
  -> int
  -> adapter
  = "caml_wgpu_instance_request_adapter_sync"

external adapter_request_device_sync
  :  adapter
  -> device
  = "caml_wgpu_adapter_request_device_sync"

type adapter_info =
  { vendor : string
  ; architecture : string
  ; device : string
  ; description : string
  ; backend_type : int
  ; adapter_type : int
  }

external adapter_get_info_raw
  :  adapter
  -> string * string * string * string * int * int
  = "caml_wgpu_adapter_get_info"

let adapter_get_info adapter =
  let vendor, architecture, device, description, backend_type, adapter_type =
    adapter_get_info_raw adapter
  in
  { vendor; architecture; device; description; backend_type; adapter_type }
;;

external queue_submit_single
  :  queue
  -> command_buffer
  -> unit
  = "caml_wgpu_queue_submit_single"

external device_poll : device -> bool -> unit = "caml_wgpu_device_poll"

external buffer_map_sync
  :  buffer
  -> int
  -> int64
  -> int64
  -> int
  = "caml_wgpu_buffer_map_sync"

external buffer_get_mapped_range_bigarray_raw
  :  buffer
  -> int64
  -> int64
  -> int
  -> ('a, 'b, Bigarray.c_layout) Bigarray.Array1.t
  = "caml_wgpu_buffer_get_mapped_range_bigarray"

let kind_to_int : type a b. (a, b) Bigarray.kind -> int =
  fun kind ->
  match kind with
  | Bigarray.Float16 -> 14
  | Bigarray.Float32 -> 0
  | Bigarray.Float64 -> 1
  | Bigarray.Int8_signed -> 2
  | Bigarray.Int8_unsigned -> 3
  | Bigarray.Int16_signed -> 4
  | Bigarray.Int16_unsigned -> 5
  | Bigarray.Int32 -> 6
  | Bigarray.Int64 -> 7
  | Bigarray.Int -> 8
  | Bigarray.Nativeint -> 9
  | Bigarray.Complex32 -> 10
  | Bigarray.Complex64 -> 11
  | Bigarray.Char -> 12
;;

let buffer_get_mapped_range_bigarray buffer offset size kind =
  buffer_get_mapped_range_bigarray_raw buffer offset size (kind_to_int kind)
;;

external buffer_get_const_mapped_range_bigarray_raw
  :  buffer
  -> int64
  -> int64
  -> int
  -> ('a, 'b, Bigarray.c_layout) Bigarray.Array1.t
  = "caml_wgpu_buffer_get_const_mapped_range_bigarray"

let buffer_get_const_mapped_range_bigarray buffer offset size kind =
  buffer_get_const_mapped_range_bigarray_raw buffer offset size (kind_to_int kind)
;;

external queue_write_buffer_bigarray
  :  queue
  -> buffer
  -> int64
  -> (_, _, Bigarray.c_layout) Bigarray.Array1.t
  -> unit
  = "caml_wgpu_queue_write_buffer_bigarray"

external device_create_bind_group_layout_storage
  :  device
  -> string
  -> int
  -> bool
  -> bind_group_layout
  = "caml_wgpu_device_create_bind_group_layout_storage"

external device_create_bind_group_buffer
  :  device
  -> string
  -> bind_group_layout
  -> int
  -> buffer
  -> int64
  -> int64
  -> bind_group
  = "caml_wgpu_device_create_bind_group_buffer_bytecode"
    "caml_wgpu_device_create_bind_group_buffer"

external device_create_texture_2d
  :  device
  -> string
  -> int
  -> int
  -> int
  -> int
  -> texture
  = "caml_wgpu_device_create_texture_2d_bytecode" "caml_wgpu_device_create_texture_2d"

external texture_create_view_configurable
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
  = "caml_wgpu_texture_create_view_configurable_bytecode"
    "caml_wgpu_texture_create_view_configurable"

external command_encoder_begin_render_pass_configurable
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
  = "caml_wgpu_command_encoder_begin_render_pass_configurable_bytecode"
    "caml_wgpu_command_encoder_begin_render_pass_configurable"

external device_create_render_pipeline_full
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
  = "caml_wgpu_device_create_render_pipeline_full_bytecode"
    "caml_wgpu_device_create_render_pipeline_full"

external device_create_bind_group_layout_uniform
  :  device
  -> string
  -> int
  -> int
  -> bind_group_layout
  = "caml_wgpu_device_create_bind_group_layout_uniform"

external device_create_render_pipeline_with_layout
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
  -> pipeline_layout
  -> render_pipeline
  = "caml_wgpu_device_create_render_pipeline_with_layout_bytecode"
    "caml_wgpu_device_create_render_pipeline_with_layout"

(* Vertex buffer layout tuple: (step_mode, array_stride, attributes) *)
(* Vertex attribute tuple: (format, offset, shader_location) *)
external device_create_render_pipeline_with_vertex_buffers
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
  -> pipeline_layout option
  -> (int * int64 * (int * int64 * int) array) array
  -> render_pipeline
  = "caml_wgpu_device_create_render_pipeline_with_vertex_buffers_bytecode"
    "caml_wgpu_device_create_render_pipeline_with_vertex_buffers"
