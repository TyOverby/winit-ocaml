module Adapter_info = struct
  type t =
    { vendor : string
    ; architecture : string
    ; device : string
    ; description : string
    ; backend_type : Backend_type.t
    ; adapter_type : Adapter_type.t
    }

  let of_low (info : Wgpu_low.adapter_info) : t =
    { vendor = info.vendor
    ; architecture = info.architecture
    ; device = info.device
    ; description = info.description
    ; backend_type = Backend_type.of_int info.backend_type
    ; adapter_type = Adapter_type.of_int info.adapter_type
    }
  ;;
end

module Command_encoder = struct
  type t = { handle : Wgpu_low.command_encoder }

  (* AUTO-GENERATED COMMAND_ENCODER METHODS INJECTED HERE *)
end

module Queue = struct
  type t = { handle : Wgpu_low.queue }

  let write_buffer t ~buffer ~offset ~data =
    Wgpu_low.queue_write_buffer_bigarray t.handle buffer.Buffer.handle offset data
  ;;

  let write_texture
    t
    ~destination_texture
    ~destination_mip_level
    ~destination_origin_x
    ~destination_origin_y
    ~destination_origin_z
    ~destination_aspect
    ~data_layout_offset
    ~data_layout_bytes_per_row
    ~data_layout_rows_per_image
    ~write_size_width
    ~write_size_height
    ~write_size_depth_or_array_layers
    ~data
    ()
    =
    let destination_origin_nested = Wgpu_low.Origin_3d.origin_3D_create () in
    let desc_destination =
      Wgpu_low.Texel_copy_texture_info.texel_copy_texture_info_create ()
    in
    let desc_data_layout =
      Wgpu_low.Texel_copy_buffer_layout.texel_copy_buffer_layout_create ()
    in
    let desc_write_size = Wgpu_low.Extent_3d.extent_3D_create () in
    Wgpu_low.Texel_copy_texture_info.texel_copy_texture_info_set_texture
      desc_destination
      destination_texture.Texture.handle;
    Wgpu_low.Texel_copy_texture_info.texel_copy_texture_info_set_mip_level
      desc_destination
      destination_mip_level;
    Wgpu_low.Origin_3d.origin_3D_set_x destination_origin_nested destination_origin_x;
    Wgpu_low.Origin_3d.origin_3D_set_y destination_origin_nested destination_origin_y;
    Wgpu_low.Origin_3d.origin_3D_set_z destination_origin_nested destination_origin_z;
    Wgpu_low.Texel_copy_texture_info.texel_copy_texture_info_set_origin
      desc_destination
      destination_origin_nested;
    Wgpu_low.Texel_copy_texture_info.texel_copy_texture_info_set_aspect
      desc_destination
      (Texture_aspect.to_int destination_aspect);
    Wgpu_low.Texel_copy_buffer_layout.texel_copy_buffer_layout_set_offset
      desc_data_layout
      data_layout_offset;
    Wgpu_low.Texel_copy_buffer_layout.texel_copy_buffer_layout_set_bytes_per_row
      desc_data_layout
      data_layout_bytes_per_row;
    Wgpu_low.Texel_copy_buffer_layout.texel_copy_buffer_layout_set_rows_per_image
      desc_data_layout
      data_layout_rows_per_image;
    Wgpu_low.Extent_3d.extent_3D_set_width desc_write_size write_size_width;
    Wgpu_low.Extent_3d.extent_3D_set_height desc_write_size write_size_height;
    Wgpu_low.Extent_3d.extent_3D_set_depth_or_array_layers
      desc_write_size
      write_size_depth_or_array_layers;
    Wgpu_low.queue_write_texture_bigarray
      t.handle
      desc_destination
      desc_data_layout
      desc_write_size
      data;
    Wgpu_low.Extent_3d.extent_3D_free desc_write_size;
    Wgpu_low.Texel_copy_buffer_layout.texel_copy_buffer_layout_free desc_data_layout;
    Wgpu_low.Origin_3d.origin_3D_free destination_origin_nested;
    Wgpu_low.Texel_copy_texture_info.texel_copy_texture_info_free desc_destination;
    ()
  ;;

  (* AUTO-GENERATED QUEUE METHODS INJECTED HERE *)
end

module Device = struct
  type t = { handle : Wgpu_low.device }

  let create_shader_module t ?(label = "") ~wgsl () =
    (* Create the WGSL source extension struct *)
    let wgsl_source = Wgpu_low.Shader_source_wgsl.shader_source_WGSL_create () in
    Wgpu_low.Shader_source_wgsl.shader_source_WGSL_set_code wgsl_source wgsl;
    Wgpu_low.Shader_source_wgsl.shader_source_WGSL_set_chain_stype
      wgsl_source
      (S_type.to_int S_type.Shader_source_wgsl);
    (* Create the shader module descriptor and chain the extension *)
    let desc = Wgpu_low.Shader_module_descriptor.shader_module_descriptor_create () in
    Wgpu_low.Shader_module_descriptor.shader_module_descriptor_set_label desc label;
    let chained = Wgpu_low.Shader_source_wgsl.shader_source_WGSL_as_chained wgsl_source in
    Wgpu_low.Shader_module_descriptor.shader_module_descriptor_set_next_in_chain
      desc
      chained;
    (* Create the shader module *)
    let shader = Wgpu_low.device_create_shader_module t.handle desc in
    (* Free the descriptor structs *)
    Wgpu_low.Shader_module_descriptor.shader_module_descriptor_free desc;
    Wgpu_low.Shader_source_wgsl.shader_source_WGSL_free wgsl_source;
    ({ Shader_module.handle = shader } : Shader_module.t)
  ;;

  (* create_compute_pipeline and create_render_pipeline are now auto-generated *)

  let create_bind_group_layout_for_storage_buffer
    t
    ?(label = "")
    ~binding
    ?(read_only = false)
    ()
    =
    let layout =
      Wgpu_low.device_create_bind_group_layout_storage t.handle label binding read_only
    in
    ({ Bind_group_layout.handle = layout } : Bind_group_layout.t)
  ;;

  let create_bind_group_layout_for_uniform_buffer t ?(label = "") ~binding ~visibility () =
    let visibility_int = Shader_stage.list_to_int visibility in
    let layout =
      Wgpu_low.device_create_bind_group_layout_uniform
        t.handle
        label
        binding
        visibility_int
    in
    ({ Bind_group_layout.handle = layout } : Bind_group_layout.t)
  ;;

  (* AUTO-GENERATED DEVICE METHODS INJECTED HERE *)
