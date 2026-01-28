module Instance = struct
  type t = { handle : Wgpu_low.instance }

  let create () = { handle = Wgpu_low.create_instance () }

  let request_adapter
    t
    ?(power_preference = Power_preference.Undefined)
    ?(backend_type = Backend_type.Undefined)
    ()
    =
    let adapter =
      Wgpu_low.instance_request_adapter_sync
        t.handle
        (Power_preference.to_int power_preference)
        (Backend_type.to_int backend_type)
    in
    { Adapter.handle = adapter }
  ;;

  (* AUTO-GENERATED INSTANCE METHODS INJECTED HERE *)
end

(* Convenience functions that delegate to module methods *)

let begin_compute_pass (encoder : Command_encoder.t) ?(label = "") () =
  Command_encoder.begin_compute_pass encoder ~label ()
;;

let begin_render_pass
  (encoder : Command_encoder.t)
  ?(label = "")
  ~color_view
  ?(load_op = Load_op.Clear)
  ?(store_op = Store_op.Store)
  ~clear_color
  ()
  =
  Command_encoder.begin_render_pass
    encoder
    ~label
    ~color_view
    ~load_op
    ~store_op
    ~clear_color
    ()
;;

let finish (encoder : Command_encoder.t) ?(label = "") () =
  Command_encoder.finish encoder ~label ()
;;

let set_bind_group (pass : Compute_pass_encoder.t) ~index ~bind_group =
  Compute_pass_encoder.set_bind_group
    pass
    ~group_index:index
    ~group:bind_group
    ~dynamic_offsets:[]
;;

let set_bind_group_render (pass : Render_pass_encoder.t) ~index ~bind_group =
  Render_pass_encoder.set_bind_group
    pass
    ~group_index:index
    ~group:bind_group
    ~dynamic_offsets:[]
;;

let copy_texture_to_buffer
  (encoder : Command_encoder.t)
  ~texture
  ~buffer
  ~size
  ~bytes_per_row
  ()
  =
  let width, height = size in
  Command_encoder.copy_texture_to_buffer
    encoder
    ~source_texture:texture
    ~source_mip_level:0
    ~source_origin_x:0
    ~source_origin_y:0
    ~source_origin_z:0
    ~source_aspect:Texture_aspect.All
    ~destination_layout_offset:0L
    ~destination_layout_bytes_per_row:bytes_per_row
    ~destination_layout_rows_per_image:height
    ~destination_buffer:buffer
    ~copy_size_width:width
    ~copy_size_height:height
    ~copy_size_depth_or_array_layers:1
    ()
;;

let map_buffer (buffer : Buffer.t) ~mode ~offset ~size =
  ignore
    (Wgpu_low.buffer_map_sync buffer.handle (Map_mode.list_to_int mode) offset size : int)
;;

let get_mapped_range (buffer : Buffer.t) ~offset ~size ~kind =
  Wgpu_low.buffer_get_mapped_range_bigarray buffer.handle offset size kind
;;

let get_const_mapped_range (buffer : Buffer.t) ~offset ~size ~kind =
  Wgpu_low.buffer_get_const_mapped_range_bigarray buffer.handle offset size kind
;;

let create_texture_view
  (texture : Texture.t)
  ?(label = "")
  ?(format = Texture_format.Undefined)
  ?(dimension = Texture_view_dimension.Undefined)
  ?(aspect = Texture_aspect.All)
  ?(base_mip_level = 0)
  ?(mip_level_count = 0xFFFFFFFF)
  (* WGPU_MIP_LEVEL_COUNT_UNDEFINED *)
  ?(base_array_layer = 0)
  ?(array_layer_count = 0xFFFFFFFF)
  (* WGPU_ARRAY_LAYER_COUNT_UNDEFINED *)
    ()
  =
  let view =
    Wgpu_low.texture_create_view_configurable
      texture.handle
      label
      (Texture_format.to_int format)
      (Texture_view_dimension.to_int dimension)
      (Texture_aspect.to_int aspect)
      base_mip_level
      mip_level_count
      base_array_layer
      array_layer_count
  in
  ({ Texture_view.handle = view } : Texture_view.t)
;;
