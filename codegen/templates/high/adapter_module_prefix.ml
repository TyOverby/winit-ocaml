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
end

module Queue = struct
  type t = { handle : Wgpu_low.queue }

  let release t = Wgpu_low.queue_release t.handle
  let set_label t ~label = Wgpu_low.queue_set_label t.handle label

  let submit t ~command_buffers =
    let handles = List.map (fun (cb : Command_buffer.t) -> cb.handle) command_buffers in
    Wgpu_low.queue_submit t.handle (Array.of_list handles)

  let write_buffer t ~buffer ~offset ~data =
    Wgpu_low.queue_write_buffer_bigarray t.handle buffer.Buffer.handle offset data
end

module Device = struct
  type t = { handle : Wgpu_low.device }

  let release t = Wgpu_low.device_release t.handle
  let get_queue t = { Queue.handle = Wgpu_low.device_get_queue t.handle }

  let create_shader_module t ?(label = "") ~wgsl () =
    (* Create the WGSL source extension struct *)
    let wgsl_source = Wgpu_low.Shader_source_wgsl.shader_source_WGSL_create () in
    Wgpu_low.Shader_source_wgsl.shader_source_WGSL_set_code wgsl_source wgsl;
    Wgpu_low.Shader_source_wgsl.shader_source_WGSL_set_chain_stype wgsl_source (S_type.to_int S_type.Shader_source_wgsl);
    (* Create the shader module descriptor and chain the extension *)
    let desc = Wgpu_low.Shader_module_descriptor.shader_module_descriptor_create () in
    Wgpu_low.Shader_module_descriptor.shader_module_descriptor_set_label desc label;
    let chained = Wgpu_low.Shader_source_wgsl.shader_source_WGSL_as_chained wgsl_source in
    Wgpu_low.Shader_module_descriptor.shader_module_descriptor_set_next_in_chain desc chained;
    (* Create the shader module *)
    let shader = Wgpu_low.device_create_shader_module t.handle desc in
    (* Free the descriptor structs *)
    Wgpu_low.Shader_module_descriptor.shader_module_descriptor_free desc;
    Wgpu_low.Shader_source_wgsl.shader_source_WGSL_free wgsl_source;
    ({ Shader_module.handle = shader } : Shader_module.t)

  let create_texture t ?(label = "") ~size ~format ~usage ?(dimension = Texture_dimension.N2d)
      ?(mip_level_count = 1) ?(sample_count = 1) () =
    let desc = Wgpu_low.Texture_descriptor.texture_descriptor_create () in
    Wgpu_low.Texture_descriptor.texture_descriptor_set_label desc label;
    Wgpu_low.Texture_descriptor.texture_descriptor_set_dimension desc (Texture_dimension.to_int dimension);
    let extent = Wgpu_low.Extent_3d.extent_3D_create () in
    let (width, height, depth) = size in
    Wgpu_low.Extent_3d.extent_3D_set_width extent width;
    Wgpu_low.Extent_3d.extent_3D_set_height extent height;
    Wgpu_low.Extent_3d.extent_3D_set_depth_or_array_layers extent depth;
    Wgpu_low.Texture_descriptor.texture_descriptor_set_size desc extent;
    Wgpu_low.Texture_descriptor.texture_descriptor_set_format desc (Texture_format.to_int format);
    Wgpu_low.Texture_descriptor.texture_descriptor_set_usage desc (Texture_usage.list_to_int usage);
    Wgpu_low.Texture_descriptor.texture_descriptor_set_mip_level_count desc mip_level_count;
    Wgpu_low.Texture_descriptor.texture_descriptor_set_sample_count desc sample_count;
    let texture = Wgpu_low.device_create_texture t.handle desc in
    Wgpu_low.Extent_3d.extent_3D_free extent;
    Wgpu_low.Texture_descriptor.texture_descriptor_free desc;
    ({ Texture.handle = texture } : Texture.t)

  let create_compute_pipeline t ?(label = "") ~layout ~module_ ~entry_point () =
    let stage_desc = Wgpu_low.Programmable_stage_descriptor.programmable_stage_descriptor_create () in
    Wgpu_low.Programmable_stage_descriptor.programmable_stage_descriptor_set_module stage_desc module_.Shader_module.handle;
    Wgpu_low.Programmable_stage_descriptor.programmable_stage_descriptor_set_entry_point stage_desc entry_point;
    Wgpu_low.Programmable_stage_descriptor.programmable_stage_descriptor_set_constants stage_desc [||];
    let desc = Wgpu_low.Compute_pipeline_descriptor.compute_pipeline_descriptor_create () in
    Wgpu_low.Compute_pipeline_descriptor.compute_pipeline_descriptor_set_label desc label;
    Wgpu_low.Compute_pipeline_descriptor.compute_pipeline_descriptor_set_layout desc layout.Pipeline_layout.handle;
    Wgpu_low.Compute_pipeline_descriptor.compute_pipeline_descriptor_set_compute desc stage_desc;
    let pipeline = Wgpu_low.device_create_compute_pipeline t.handle desc in
    Wgpu_low.Programmable_stage_descriptor.programmable_stage_descriptor_free stage_desc;
    Wgpu_low.Compute_pipeline_descriptor.compute_pipeline_descriptor_free desc;
    ({ Compute_pipeline.handle = pipeline } : Compute_pipeline.t)

  let create_render_pipeline t ?(label = "") ~shader_module ~vertex_entry_point
      ~fragment_entry_point ~color_format
      ?(topology = Primitive_topology.Triangle_list)
      ?(front_face = Front_face.Ccw)
      ?(cull_mode = Cull_mode.None)
      ?(blend : (Blend_factor.t * Blend_factor.t * Blend_operation.t *
                 Blend_factor.t * Blend_factor.t * Blend_operation.t) option)
      ?(write_mask = [ Color_write_mask.All ])
      () =
    let blend_enabled, color_src, color_dst, color_op, alpha_src, alpha_dst, alpha_op =
      match blend with
      | None -> false, Blend_factor.One, Blend_factor.Zero, Blend_operation.Add,
                       Blend_factor.One, Blend_factor.Zero, Blend_operation.Add
      | Some (cs, cd, co, as_, ad, ao) -> true, cs, cd, co, as_, ad, ao
    in
    let pipeline = Wgpu_low.device_create_render_pipeline_full t.handle
      label shader_module.Shader_module.handle vertex_entry_point
      fragment_entry_point (Texture_format.to_int color_format)
      (Primitive_topology.to_int topology)
      (Front_face.to_int front_face)
      (Cull_mode.to_int cull_mode)
      blend_enabled
      (Blend_factor.to_int color_src) (Blend_factor.to_int color_dst)
      (Blend_operation.to_int color_op)
      (Blend_factor.to_int alpha_src) (Blend_factor.to_int alpha_dst)
      (Blend_operation.to_int alpha_op)
      (Color_write_mask.list_to_int write_mask) in
    ({ Render_pipeline.handle = pipeline } : Render_pipeline.t)

  let create_bind_group_layout_for_storage_buffer t ?(label = "") ~binding ?(read_only = false) () =
    let layout = Wgpu_low.device_create_bind_group_layout_storage t.handle
      label binding read_only in
    ({ Bind_group_layout.handle = layout } : Bind_group_layout.t)

  (* AUTO-GENERATED DEVICE METHODS INJECTED HERE *)
