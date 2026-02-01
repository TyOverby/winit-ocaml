(*
   WebGPU Fundamentals: Multisampling (Center Interpolation Issue)

   This test demonstrates an issue with center-based interpolation when using
   MSAA. We pass barycentric coordinates from the vertex shader to the fragment
   shader. The fragment shader checks if these coordinates are within [0,1] for
   all three components - they should always be inside the triangle.

   However, with default 'center' interpolation, the GPU interpolates values
   relative to the pixel center. When the pixel center is outside the triangle
   (but some samples are inside), the interpolated barycentric coordinates can
   fall outside [0,1], causing the test to fail and showing yellow pixels.

   This is rendered at low resolution to make the issue visible.
*)

open! Core

(* Low resolution to make the interpolation issue visible *)
let width = 40
let height = 40
let bytes_per_pixel = 4
let bytes_per_row = ((width * bytes_per_pixel) + 255) / 256 * 256
let buffer_size = bytes_per_row * height

let shader_code =
  {|
struct VOut {
  @builtin(position) position: vec4f,
  @location(0) baryCoord: vec3f,
};

@vertex fn vs(
  @builtin(vertex_index) vertexIndex : u32
) -> VOut {
  let pos = array(
    vec2f( 0.0,  0.5),  // top center
    vec2f(-0.5, -0.5),  // bottom left
    vec2f( 0.5, -0.5)   // bottom right
  );
  let bary = array(
    vec3f(1, 0, 0),
    vec3f(0, 1, 0),
    vec3f(0, 0, 1),
  );
  var vout: VOut;
  vout.position = vec4f(pos[vertexIndex], 0.0, 1.0);
  vout.baryCoord = bary[vertexIndex];
  return vout;
}

@fragment fn fs(vin: VOut) -> @location(0) vec4f {
  let allAbove0 = all(vin.baryCoord >= vec3f(0));
  let allBelow1 = all(vin.baryCoord <= vec3f(1));
  let inside = allAbove0 && allBelow1;
  let red = vec4f(1, 0, 0, 1);
  let yellow = vec4f(1, 1, 0, 1);
  return select(yellow, red, inside);
}
|}
;;

let init () =
  let instance = Wgpu.Instance.create () in
  let adapter = Wgpu.Instance.request_adapter instance () in
  let device = Wgpu.Adapter.request_device adapter in
  let queue = Wgpu.Device.get_queue device in
  let shader =
    Wgpu.Device.create_shader_module
      device
      ~label:"msaa_center_shader"
      ~wgsl:shader_code
      ()
  in
  instance, adapter, device, queue, shader
;;

let () =
  let instance, adapter, device, queue, shader = init () in
  (* Create 4x MSAA texture (render target) *)
  let msaa_texture =
    Wgpu.Device.create_texture
      device
      ~label:"msaa_target"
      ~size_width:width
      ~size_height:height
      ~size_depth_or_array_layers:1
      ~dimension:N2d
      ~mip_level_count:1
      ~sample_count:4
      ~format:Wgpu.Texture_format.Rgba8_unorm
      ~usage:[ Wgpu.Texture_usage.Item.Render_attachment ]
      ()
  in
  let msaa_view = Wgpu.create_texture_view msaa_texture ~label:"msaa_view" () in
  (* Create resolve target texture (non-MSAA) *)
  let resolve_texture =
    Wgpu.Device.create_texture
      device
      ~label:"resolve_target"
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
  let resolve_view = Wgpu.create_texture_view resolve_texture ~label:"resolve_view" () in
  (* Create readback buffer *)
  let readback_buffer =
    Wgpu.Device.create_buffer
      device
      ~label:"readback_buffer"
      ~size:(Int64.of_int buffer_size)
      ~usage:[ Wgpu.Buffer_usage.Item.Map_read; Wgpu.Buffer_usage.Item.Copy_dst ]
      ~mapped_at_creation:false
      ()
  in
  (* Create render pipeline with 4x MSAA *)
  let pipeline =
    Wgpu.Device.create_render_pipeline
      device
      ~label:"msaa_center_pipeline"
      ~vertex_module:shader
      ~vertex_entry_point:"vs"
      ~primitive_topology:Wgpu.Primitive_topology.Triangle_list
      ~primitive_strip_index_format:Wgpu.Index_format.Undefined
      ~primitive_front_face:Wgpu.Front_face.Ccw
      ~primitive_cull_mode:Wgpu.Cull_mode.None
      ~primitive_unclipped_depth:false
      ~multisample_count:4
      ~multisample_mask:0xFFFFFFFF
      ~multisample_alpha_to_coverage_enabled:false
      ~fragment:
        { module_ = shader
        ; entry_point = "fs"
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
  let encoder = Wgpu.Device.create_command_encoder device ~label:"render_encoder" () in
  (* Begin render pass with MSAA texture and resolve target *)
  let render_pass =
    Wgpu.begin_render_pass_simple
      encoder
      ~label:"msaa_pass"
      ~color_view:msaa_view
      ~load_op:Wgpu.Load_op.Clear
      ~store_op:Wgpu.Store_op.Discard
      ~clear_color:(0.3, 0.3, 0.3, 1.0)
      ~resolve_target:resolve_view
      ()
  in
  Wgpu.Render_pass_encoder.set_pipeline render_pass ~pipeline;
  Wgpu.Render_pass_encoder.draw
    render_pass
    ~vertex_count:3
    ~instance_count:1
    ~first_vertex:0
    ~first_instance:0;
  Wgpu.Render_pass_encoder.end_ render_pass;
  (* Copy resolve target to readback buffer *)
  Wgpu.copy_texture_to_buffer
    encoder
    ~texture:resolve_texture
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
    let ppm_file = Test_util.output_path "multisample_center_issue.ppm" in
    let png_file = Test_util.output_path "multisample_center_issue.png" in
    Test_util.write_ppm ~filename:ppm_file ~width ~height ~data:mapped_data ~bytes_per_row;
    Test_util.ppm_to_png ~ppm_file ~png_file;
    ()
  in
  Wgpu.Buffer.unmap readback_buffer;
  (* Cleanup *)
  Wgpu.Command_buffer.release command_buffer;
  Wgpu.Render_pass_encoder.release render_pass;
  Wgpu.Command_encoder.release encoder;
  Wgpu.Render_pipeline.release pipeline;
  Wgpu.Buffer.release readback_buffer;
  Wgpu.Texture_view.release resolve_view;
  Wgpu.Texture.release resolve_texture;
  Wgpu.Texture_view.release msaa_view;
  Wgpu.Texture.release msaa_texture;
  Wgpu.Shader_module.release shader;
  Wgpu.Queue.release queue;
  Wgpu.Device.release device;
  Wgpu.Adapter.release adapter;
  Wgpu.Instance.release instance
;;
