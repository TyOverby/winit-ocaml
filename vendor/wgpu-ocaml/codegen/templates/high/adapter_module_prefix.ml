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

  let begin_compute_pass t ?(label = "") () =
    let desc = Wgpu_low.Compute_pass_descriptor.compute_pass_descriptor_create () in
    Wgpu_low.Compute_pass_descriptor.compute_pass_descriptor_set_label desc label;
    let pass = Wgpu_low.command_encoder_begin_compute_pass t.handle desc in
    Wgpu_low.Compute_pass_descriptor.compute_pass_descriptor_free desc;
    ({ Compute_pass_encoder.handle = pass } : Compute_pass_encoder.t)
  ;;

  let begin_render_pass
    t
    ?(label = "")
    ~color_view
    ?(load_op = Load_op.Clear)
    ?(store_op = Store_op.Store)
    ~clear_color
    ?depth_view
    ?(depth_load_op = Load_op.Clear)
    ?(depth_store_op = Store_op.Discard)
    ?(depth_clear_value = 1.0)
    ?resolve_target
    ()
    =
    let r, g, b, a = clear_color in
    let depth_view_opt = Option.map (fun v -> v.Texture_view.handle) depth_view in
    let resolve_target_opt = Option.map (fun v -> v.Texture_view.handle) resolve_target in
    let pass =
      Wgpu_low.command_encoder_begin_render_pass_with_depth
        t.handle
        label
        color_view.Texture_view.handle
        (Load_op.to_int load_op)
        (Store_op.to_int store_op)
        r
        g
        b
        a
        depth_view_opt
        (Load_op.to_int depth_load_op)
        (Store_op.to_int depth_store_op)
        depth_clear_value
        resolve_target_opt
    in
    ({ Render_pass_encoder.handle = pass } : Render_pass_encoder.t)
  ;;

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

  (* create_compute_pipeline is now auto-generated *)

  let create_render_pipeline
    t
    ?(label = "")
    ~shader_module
    ~vertex_entry_point
    ~fragment_entry_point
    ~color_format
    ?(topology = Primitive_topology.Triangle_list)
    ?(front_face = Front_face.Ccw)
    ?(cull_mode = Cull_mode.None)
    ?(blend :
        (Blend_factor.t
        * Blend_factor.t
        * Blend_operation.t
        * Blend_factor.t
        * Blend_factor.t
        * Blend_operation.t)
          option)
    ?(write_mask = [ Color_write_mask.Item.All ])
    ?layout
    ?(vertex_buffer_layouts : Vertex_buffer_layout.t list = [])
    ?depth_format
    ?(depth_write_enabled = true)
    ?(depth_compare = Compare_function.Less)
    ?(multisample_count = 1)
    ()
    =
    let blend_enabled, color_src, color_dst, color_op, alpha_src, alpha_dst, alpha_op =
      match blend with
      | None ->
        ( false
        , Blend_factor.One
        , Blend_factor.Zero
        , Blend_operation.Add
        , Blend_factor.One
        , Blend_factor.Zero
        , Blend_operation.Add )
      | Some (cs, cd, co, as_, ad, ao) -> true, cs, cd, co, as_, ad, ao
    in
    let pipeline =
      let vbl_array =
        Array.of_list
          (List.map
             (fun vbl ->
               let attrs =
                 Array.of_list
                   (List.map
                      (fun attr ->
                        ( Vertex_format.to_int attr.Vertex_attribute.format
                        , attr.Vertex_attribute.offset
                        , attr.Vertex_attribute.shader_location ))
                      vbl.Vertex_buffer_layout.attributes)
               in
               ( Vertex_step_mode.to_int vbl.Vertex_buffer_layout.step_mode
               , vbl.Vertex_buffer_layout.array_stride
               , attrs ))
             vertex_buffer_layouts)
      in
      let layout_opt = Option.map (fun l -> l.Pipeline_layout.handle) layout in
      let depth_format_opt = Option.map Texture_format.to_int depth_format in
      Wgpu_low.device_create_render_pipeline_with_depth
        t.handle
        label
        shader_module.Shader_module.handle
        vertex_entry_point
        fragment_entry_point
        (Texture_format.to_int color_format)
        (Primitive_topology.to_int topology)
        (Front_face.to_int front_face)
        (Cull_mode.to_int cull_mode)
        blend_enabled
        (Blend_factor.to_int color_src)
        (Blend_factor.to_int color_dst)
        (Blend_operation.to_int color_op)
        (Blend_factor.to_int alpha_src)
        (Blend_factor.to_int alpha_dst)
        (Blend_operation.to_int alpha_op)
        (Color_write_mask.list_to_int write_mask)
        layout_opt
        vbl_array
        depth_format_opt
        depth_write_enabled
        (Compare_function.to_int depth_compare)
        multisample_count
    in
    ({ Render_pipeline.handle = pipeline } : Render_pipeline.t)
  ;;

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
