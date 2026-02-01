(*
   WebGPU Fundamentals: Storage Buffers with Instancing

   This test demonstrates the power of storage buffers for instanced rendering.
   Unlike uniform buffers which have a 64 KiB limit, storage buffers can be
   much larger (128 MiB by default) and support arrays.

   Key concepts:
   - Storage buffers with runtime-sized arrays
   - GPU instancing with @builtin(instance_index)
   - Single draw call for all 100 triangles
   - Passing color through inter-stage variables

   The vertex shader uses instance_index to look up per-object data from
   the storage buffer arrays, enabling a single draw call to render all
   objects with different transforms and colors.
*)

open! Core

let width = 600
let height = 400
let bytes_per_pixel = 4
let bytes_per_row = ((width * bytes_per_pixel) + 255) / 256 * 256
let buffer_size = bytes_per_row * height
let num_objects = 100

let shader_code =
  {|
struct OurStruct {
  color: vec4f,
  offset: vec2f,
};

struct OtherStruct {
  scale: vec2f,
};

struct VSOutput {
  @builtin(position) position: vec4f,
  @location(0) color: vec4f,
}

@group(0) @binding(0) var<storage, read> ourStructs: array<OurStruct>;
@group(0) @binding(1) var<storage, read> otherStructs: array<OtherStruct>;

@vertex fn vs(
  @builtin(vertex_index) vertexIndex : u32,
  @builtin(instance_index) instanceIndex: u32
) -> VSOutput {
  let pos = array(
    vec2f( 0.0,  0.5),  // top center
    vec2f(-0.5, -0.5),  // bottom left
    vec2f( 0.5, -0.5)   // bottom right
  );

  let otherStruct = otherStructs[instanceIndex];
  let ourStruct = ourStructs[instanceIndex];

  var vsOut: VSOutput;
  vsOut.position = vec4f(
      pos[vertexIndex] * otherStruct.scale + ourStruct.offset, 0.0, 1.0);
  vsOut.color = ourStruct.color;
  return vsOut;
}

@fragment fn fs(vsOut: VSOutput) -> @location(0) vec4f {
  return vsOut.color;
}
|}
;;

(* Storage buffer layout for static data (color + offset):
   - color: vec4f (4 floats, 16 bytes)
   - offset: vec2f (2 floats, 8 bytes)
   - padding: 8 bytes (struct alignment)
   Total per object: 32 bytes *)
let static_unit_size = 32

(* Storage buffer layout for dynamic data (scale):
   - scale: vec2f (2 floats, 8 bytes)
   Total per object: 8 bytes *)
let changing_unit_size = 8

(* Random number in range [min, max) *)
let rand ~min ~max = min +. Random.float (max -. min)

let init () =
  let instance = Wgpu.Instance.create () in
  let adapter = Wgpu.Instance.request_adapter instance () in
  let device = Wgpu.Adapter.request_device adapter in
  let queue = Wgpu.Device.get_queue device in
  let shader =
    Wgpu.Device.create_shader_module
      device
      ~label:"storage_split_shader"
      ~wgsl:shader_code
      ()
  in
  instance, adapter, device, queue, shader
;;

let () =
  (* Use a fixed seed for reproducible output *)
  Random.init 42;
  let instance, adapter, device, queue, shader = init () in
  (* Create storage buffers for all objects *)
  let static_storage_buffer_size = static_unit_size * num_objects in
  let static_storage_buffer =
    Wgpu.Device.create_buffer
      device
      ~label:"static storage for objects"
      ~size:(Int64.of_int static_storage_buffer_size)
      ~usage:[ Wgpu.Buffer_usage.Item.Storage; Wgpu.Buffer_usage.Item.Copy_dst ]
      ~mapped_at_creation:false
      ()
  in
  let changing_storage_buffer_size = changing_unit_size * num_objects in
  let changing_storage_buffer =
    Wgpu.Device.create_buffer
      device
      ~label:"changing storage for objects"
      ~size:(Int64.of_int changing_storage_buffer_size)
      ~usage:[ Wgpu.Buffer_usage.Item.Storage; Wgpu.Buffer_usage.Item.Copy_dst ]
      ~mapped_at_creation:false
      ()
  in
  (* Populate static storage buffer with colors and offsets *)
  let object_scales = Array.create ~len:num_objects 0.0 in
  let ( (* Populate static storage data *) ) =
    let static_data =
      Bigarray.Array1.create
        Bigarray.float32
        Bigarray.c_layout
        (static_storage_buffer_size / 4)
    in
    let k_color_offset = 0 in
    let k_offset_offset = 4 in
    for i = 0 to num_objects - 1 do
      let offset = i * (static_unit_size / 4) in
      (* color at offset 0: rgba *)
      Bigarray.Array1.set static_data (offset + k_color_offset) (Random.float 1.0);
      Bigarray.Array1.set static_data (offset + k_color_offset + 1) (Random.float 1.0);
      Bigarray.Array1.set static_data (offset + k_color_offset + 2) (Random.float 1.0);
      Bigarray.Array1.set static_data (offset + k_color_offset + 3) 1.0;
      (* offset at offset 4: xy *)
      Bigarray.Array1.set
        static_data
        (offset + k_offset_offset)
        (rand ~min:(-0.9) ~max:0.9);
      Bigarray.Array1.set
        static_data
        (offset + k_offset_offset + 1)
        (rand ~min:(-0.9) ~max:0.9);
      (* padding at offset 6,7 *)
      Bigarray.Array1.set static_data (offset + 6) 0.0;
      Bigarray.Array1.set static_data (offset + 7) 0.0;
      object_scales.(i) <- rand ~min:0.2 ~max:0.5
    done;
    Wgpu.Queue.write_buffer
      queue
      ~buffer:static_storage_buffer
      ~offset:0L
      ~data:static_data
  in
  (* Populate changing storage buffer with scales *)
  let changing_data =
    Bigarray.Array1.create
      Bigarray.float32
      Bigarray.c_layout
      (changing_storage_buffer_size / 4)
  in
  let aspect = Float.of_int width /. Float.of_int height in
  for i = 0 to num_objects - 1 do
    let offset = i * (changing_unit_size / 4) in
    (* scale: xy *)
    Bigarray.Array1.set changing_data offset (object_scales.(i) /. aspect);
    Bigarray.Array1.set changing_data (offset + 1) object_scales.(i)
  done;
  Wgpu.Queue.write_buffer
    queue
    ~buffer:changing_storage_buffer
    ~offset:0L
    ~data:changing_data;
  (* Create bind group layout with two storage buffer bindings *)
  let bind_group_layout =
    Wgpu.Device.create_bind_group_layout
      device
      ~label:"storage_split_bind_group_layout"
      ~entries:
        [ Wgpu.Bind_group_layout_entry.create
            ~binding:0
            ~visibility:[ Wgpu.Shader_stage.Item.Vertex ]
            ~buffer:
              (Wgpu.Bind_group_layout_entry.Buffer_binding_layout.create
                 ~type_:Wgpu.Buffer_binding_type.Read_only_storage
                 ~has_dynamic_offset:false
                 ~min_binding_size:0L
                 ())
            ()
        ; Wgpu.Bind_group_layout_entry.create
            ~binding:1
            ~visibility:[ Wgpu.Shader_stage.Item.Vertex ]
            ~buffer:
              (Wgpu.Bind_group_layout_entry.Buffer_binding_layout.create
                 ~type_:Wgpu.Buffer_binding_type.Read_only_storage
                 ~has_dynamic_offset:false
                 ~min_binding_size:0L
                 ())
            ()
        ]
      ()
  in
  let bind_group =
    Wgpu.Device.create_bind_group
      device
      ~label:"storage_split_bind_group"
      ~layout:bind_group_layout
      ~entries:
        [ Wgpu.Bind_group_entry.create
            ~binding:0
            ~buffer:static_storage_buffer
            ~offset:0L
            ~size:(Int64.of_int static_storage_buffer_size)
            ()
        ; Wgpu.Bind_group_entry.create
            ~binding:1
            ~buffer:changing_storage_buffer
            ~offset:0L
            ~size:(Int64.of_int changing_storage_buffer_size)
            ()
        ]
      ()
  in
  (* Create pipeline layout *)
  let pipeline_layout =
    Wgpu.Device.create_pipeline_layout
      device
      ~label:"storage_split_pipeline_layout"
      ~bind_group_layouts:[ bind_group_layout ]
      ()
  in
  (* Create render pipeline *)
  let pipeline =
    Wgpu.Device.create_render_pipeline
      device
      ~label:"storage_split_pipeline"
      ~layout:pipeline_layout
      ~vertex_module:shader
      ~vertex_entry_point:"vs"
      ~primitive_topology:Wgpu.Primitive_topology.Triangle_list
      ~primitive_strip_index_format:Wgpu.Index_format.Undefined
      ~primitive_front_face:Wgpu.Front_face.Ccw
      ~primitive_cull_mode:Wgpu.Cull_mode.None
      ~primitive_unclipped_depth:false
      ~multisample_count:1
      ~multisample_mask:0xFFFFFFFF
      ~multisample_alpha_to_coverage_enabled:false
      ~fragment:
        (Wgpu.Fragment_state.create
           ~module_:shader
           ~entry_point:"fs"
           ~targets:
             [ Wgpu.Color_target_state.create
                 ~format:Wgpu.Texture_format.Rgba8_unorm
                 ~write_mask:[ Wgpu.Color_write_mask.Item.All ]
                 ()
             ]
           ())
      ()
  in
  (* Create render target *)
  let texture =
    Wgpu.Device.create_texture
      device
      ~label:"render_target"
      ~size_width:width
      ~size_height:height
      ~size_depth_or_array_layers:1
      ~dimension:N2d
      ~mip_level_count:1
      ~sample_count:1
      ~format:Wgpu.Texture_format.Rgba8_unorm
      ~usage:
        [ Wgpu.Texture_usage.Item.Render_attachment; Wgpu.Texture_usage.Item.Copy_src ]
      ()
  in
  let texture_view = Wgpu.create_texture_view texture ~label:"render_target_view" () in
  let readback_buffer =
    Wgpu.Device.create_buffer
      device
      ~label:"readback_buffer"
      ~size:(Int64.of_int buffer_size)
      ~usage:[ Wgpu.Buffer_usage.Item.Map_read; Wgpu.Buffer_usage.Item.Copy_dst ]
      ~mapped_at_creation:false
      ()
  in
  (* Render - single draw call for all objects using instancing *)
  let encoder = Wgpu.Device.create_command_encoder device ~label:"render_encoder" () in
  let render_pass =
    Wgpu.Command_encoder.begin_render_pass
      encoder
      ~label:"storage_split_pass"
      ~color_attachments:
        [ Wgpu.Render_pass_color_attachment.create
            ~view:texture_view
            ~load_op:Wgpu.Load_op.Clear
            ~store_op:Wgpu.Store_op.Store
            ~clear_value:
              (Wgpu.Render_pass_color_attachment.Color.create
                 ~r:0.3
                 ~g:0.3
                 ~b:0.3
                 ~a:1.0
                 ())
            ()
        ]
      ()
  in
  Wgpu.Render_pass_encoder.set_pipeline render_pass ~pipeline;
  Wgpu.set_bind_group_render render_pass ~index:0 ~bind_group;
  (* Draw 3 vertices (triangle) for num_objects instances *)
  Wgpu.Render_pass_encoder.draw
    render_pass
    ~vertex_count:3
    ~instance_count:num_objects
    ~first_vertex:0
    ~first_instance:0;
  Wgpu.Render_pass_encoder.end_ render_pass;
  Wgpu.copy_texture_to_buffer
    encoder
    ~texture
    ~buffer:readback_buffer
    ~size:(width, height)
    ~bytes_per_row
    ();
  let command_buffer = Wgpu.finish encoder ~label:"render_commands" () in
  Wgpu.Queue.submit queue ~commands:[ command_buffer ];
  Wgpu.Device.poll device ~wait:true ();
  let mapped_data =
    Wgpu.map_buffer
      readback_buffer
      ~mode:[ Wgpu.Map_mode.Item.Read ]
      ~offset:0L
      ~size:(Int64.of_int buffer_size);
    Wgpu.Device.poll device ~wait:true ();
    Wgpu.get_const_mapped_range
      readback_buffer
      ~offset:0L
      ~size:(Int64.of_int buffer_size)
      ~kind:Bigarray.int8_unsigned
  in
  let ( (* Write output *) ) =
    let ppm_file = Test_util.output_path "simple_triangle_storage_split.ppm" in
    let png_file = Test_util.output_path "simple_triangle_storage_split.png" in
    Test_util.write_ppm ~filename:ppm_file ~width ~height ~data:mapped_data ~bytes_per_row;
    Test_util.ppm_to_png ~ppm_file ~png_file;
    ()
  in
  Wgpu.Buffer.unmap readback_buffer;
  (* Cleanup *)
  Wgpu.Command_buffer.release command_buffer;
  Wgpu.Render_pass_encoder.release render_pass;
  Wgpu.Command_encoder.release encoder;
  Wgpu.Buffer.release readback_buffer;
  Wgpu.Texture_view.release texture_view;
  Wgpu.Texture.release texture;
  Wgpu.Render_pipeline.release pipeline;
  Wgpu.Pipeline_layout.release pipeline_layout;
  Wgpu.Bind_group.release bind_group;
  Wgpu.Bind_group_layout.release bind_group_layout;
  Wgpu.Buffer.release changing_storage_buffer;
  Wgpu.Buffer.release static_storage_buffer;
  Wgpu.Shader_module.release shader;
  Wgpu.Queue.release queue;
  Wgpu.Device.release device;
  Wgpu.Adapter.release adapter;
  Wgpu.Instance.release instance
;;
