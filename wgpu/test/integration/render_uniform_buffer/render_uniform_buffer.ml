(*
   Render Uniform Buffer Test

   This test demonstrates using uniform buffers with render pipelines.
   It creates a pipeline with a bind group layout for a uniform buffer,
   writes color values to the uniform buffer, and verifies that the
   fragment shader reads and uses those values correctly.

   The uniform buffer contains an RGBA color that the fragment shader
   outputs directly. We test by setting a specific color (magenta) and
   verifying the rendered output matches.
*)

open! Core

let width = 64
let height = 64
let bytes_per_pixel = 4
let bytes_per_row = ((width * bytes_per_pixel) + 255) / 256 * 256
let buffer_size = bytes_per_row * height

(* Uniform buffer: 4 floats for RGBA color *)
let num_uniform_floats = 4
let uniform_buffer_size = num_uniform_floats * 4

let shader_code =
  {|
struct Uniforms {
  color: vec4f,
};

@group(0) @binding(0) var<uniform> uniforms: Uniforms;

@vertex
fn vs_main(@builtin(vertex_index) in_vertex_index: u32) -> @builtin(position) vec4<f32> {
    // Full-screen triangle covering the entire viewport
    let x = f32((in_vertex_index << 1u) & 2u) * 2.0 - 1.0;
    let y = f32(in_vertex_index & 2u) * 2.0 - 1.0;
    return vec4<f32>(x, y, 0.0, 1.0);
}

@fragment
fn fs_main() -> @location(0) vec4<f32> {
    return uniforms.color;
}
|}
;;

let init () =
  let instance = Wgpu.Instance.create () in
  let adapter = Wgpu.Instance.request_adapter instance () in
  let device = Wgpu.Adapter.request_device adapter in
  let queue = Wgpu.Device.get_queue device in
  let shader =
    Wgpu.Device.create_shader_module device ~label:"uniform_shader" ~wgsl:shader_code ()
  in
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
  instance, adapter, device, queue, shader, texture, texture_view, readback_buffer
;;

let cleanup
  ~instance
  ~adapter
  ~device
  ~queue
  ~shader
  ~texture
  ~texture_view
  ~readback_buffer
  ~uniform_buffer
  ~bind_group_layout
  ~bind_group
  ~pipeline_layout
  ~pipeline
  ~command_buffer
  ~render_pass
  ~encoder
  =
  Wgpu.Command_buffer.release command_buffer;
  Wgpu.Render_pass_encoder.release render_pass;
  Wgpu.Command_encoder.release encoder;
  Wgpu.Render_pipeline.release pipeline;
  Wgpu.Pipeline_layout.release pipeline_layout;
  Wgpu.Bind_group.release bind_group;
  Wgpu.Bind_group_layout.release bind_group_layout;
  Wgpu.Buffer.release uniform_buffer;
  Wgpu.Buffer.release readback_buffer;
  Wgpu.Texture_view.release texture_view;
  Wgpu.Texture.release texture;
  Wgpu.Shader_module.release shader;
  Wgpu.Queue.release queue;
  Wgpu.Device.release device;
  Wgpu.Adapter.release adapter;
  Wgpu.Instance.release instance
;;

let () =
  let instance, adapter, device, queue, shader, texture, texture_view, readback_buffer =
    init ()
  in
  (* Create uniform buffer *)
  let uniform_buffer =
    Wgpu.Device.create_buffer
      device
      ~label:"uniform_buffer"
      ~size:(Int64.of_int uniform_buffer_size)
      ~usage:[ Wgpu.Buffer_usage.Item.Uniform; Wgpu.Buffer_usage.Item.Copy_dst ]
      ~mapped_at_creation:false
      ()
  in
  (* Write magenta color (1.0, 0.0, 1.0, 1.0) to uniform buffer using float32 bigarray *)
  let uniform_data =
    Bigarray.Array1.create Bigarray.float32 Bigarray.c_layout num_uniform_floats
  in
  Bigarray.Array1.set uniform_data 0 1.0;
  Bigarray.Array1.set uniform_data 1 0.0;
  Bigarray.Array1.set uniform_data 2 1.0;
  Bigarray.Array1.set uniform_data 3 1.0;
  Wgpu.Queue.write_buffer queue ~buffer:uniform_buffer ~offset:0L ~data:uniform_data;
  (* Create bind group layout for uniform buffer *)
  let bind_group_layout =
    Wgpu.Device.create_bind_group_layout_for_uniform_buffer
      device
      ~label:"uniform_bind_group_layout"
      ~binding:0
      ~visibility:[ Wgpu.Shader_stage.Item.Fragment ]
      ()
  in
  (* Create bind group with uniform buffer *)
  let bind_group =
    Wgpu.Device.create_bind_group
      device
      ~label:"uniform_bind_group"
      ~layout:bind_group_layout
      ~entries:
        [ { Wgpu.Bind_group_entry.binding = 0
          ; buffer = Some uniform_buffer
          ; offset = 0L
          ; size = Int64.of_int uniform_buffer_size
          ; sampler = None
          ; texture_view = None
          }
        ]
      ()
  in
  (* Create pipeline layout with bind group layout *)
  let pipeline_layout =
    Wgpu.Device.create_pipeline_layout
      device
      ~label:"uniform_pipeline_layout"
      ~bind_group_layouts:[ bind_group_layout ]
      ()
  in
  (* Create render pipeline with explicit layout *)
  let pipeline =
    Wgpu.Device.create_render_pipeline
      device
      ~label:"uniform_pipeline"
      ~layout:pipeline_layout
      ~vertex_module:shader
      ~vertex_entry_point:"vs_main"
      ~primitive_topology:Wgpu.Primitive_topology.Triangle_list
      ~primitive_strip_index_format:Wgpu.Index_format.Undefined
      ~primitive_front_face:Wgpu.Front_face.Ccw
      ~primitive_cull_mode:Wgpu.Cull_mode.None
      ~primitive_unclipped_depth:false
      ~multisample_count:1
      ~multisample_mask:0xFFFFFFFF
      ~multisample_alpha_to_coverage_enabled:false
      ~fragment:
        { module_ = shader
        ; entry_point = "fs_main"
        ; constants = []
        ; targets =
            [ { format = Wgpu.Texture_format.Rgba8_unorm
              ; blend = None
              ; write_mask = [ Wgpu.Color_write_mask.Item.All ]
              }
            ]
        }
      ()
  in
  (* Render *)
  let encoder = Wgpu.Device.create_command_encoder device ~label:"render_encoder" () in
  let render_pass =
    Wgpu.begin_render_pass_simple
      encoder
      ~label:"uniform_pass"
      ~color_view:texture_view
      ~clear_color:(0.0, 0.0, 0.0, 1.0)
      ()
  in
  Wgpu.Render_pass_encoder.set_pipeline render_pass ~pipeline;
  Wgpu.set_bind_group_render render_pass ~index:0 ~bind_group;
  Wgpu.Render_pass_encoder.draw
    render_pass
    ~vertex_count:3
    ~instance_count:1
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
  (* Check center pixel - should be magenta (255, 0, 255, 255) *)
  let center_x = width / 2 in
  let center_y = height / 2 in
  let center_offset = (center_y * bytes_per_row) + (center_x * bytes_per_pixel) in
  let cr = Bigarray.Array1.get mapped_data center_offset in
  let cg = Bigarray.Array1.get mapped_data (center_offset + 1) in
  let cb = Bigarray.Array1.get mapped_data (center_offset + 2) in
  let ca = Bigarray.Array1.get mapped_data (center_offset + 3) in
  let center_is_magenta = cr = 255 && cg = 0 && cb = 255 && ca = 255 in
  let ( (* Write output *) ) =
    let ppm_file = Test_util.output_path "render_uniform_buffer.ppm" in
    let png_file = Test_util.output_path "render_uniform_buffer.png" in
    Test_util.write_ppm ~filename:ppm_file ~width ~height ~data:mapped_data ~bytes_per_row;
    Test_util.ppm_to_png ~ppm_file ~png_file;
    ()
  in
  Wgpu.Buffer.unmap readback_buffer;
  cleanup
    ~instance
    ~adapter
    ~device
    ~queue
    ~shader
    ~texture
    ~texture_view
    ~readback_buffer
    ~uniform_buffer
    ~bind_group_layout
    ~bind_group
    ~pipeline_layout
    ~pipeline
    ~command_buffer
    ~render_pass
    ~encoder;
  if not center_is_magenta
  then (
    print_s
      [%message
        "FAILURE: Expected magenta (255, 0, 255, 255)"
          ~center:((cr, cg, cb, ca) : int * int * int * int)];
    exit 1)
;;
