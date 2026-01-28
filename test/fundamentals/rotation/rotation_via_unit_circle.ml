(*
   Rotation Via Unit Circle Example - Port of WebGPU Fundamentals lesson

   This example demonstrates the unit circle concept for rotation:
   - The unit circle has radius 1
   - Any point on the circle can be expressed as (cos(angle), sin(angle))
   - These values directly represent the rotation transformation

   This version shows the F-shape rotated at 30 degrees (a typical unit circle
   demonstration angle) where cos(30) = sqrt(3)/2 ~ 0.866 and sin(30) = 0.5.

   The key insight is that rotation is just multiplication by the unit circle
   coordinates - no need to think about angles directly once you understand
   the unit circle.
*)

open! Core

let width = 600
let height = 400
let bytes_per_pixel = 4
let bytes_per_row = ((width * bytes_per_pixel) + 255) / 256 * 256
let buffer_size = bytes_per_row * height
let num_vertices = 18

(* Generate shader code with explicit unit circle values *)
let shader_code ~cos_angle ~sin_angle =
  Printf.sprintf
    {|
// F-shape vertices embedded in shader
const positions = array<vec2f, 18>(
  // left column
  vec2f(0.0, 0.0),
  vec2f(30.0, 0.0),
  vec2f(0.0, 150.0),
  vec2f(0.0, 150.0),
  vec2f(30.0, 0.0),
  vec2f(30.0, 150.0),
  // top rung
  vec2f(30.0, 0.0),
  vec2f(100.0, 0.0),
  vec2f(30.0, 30.0),
  vec2f(30.0, 30.0),
  vec2f(100.0, 0.0),
  vec2f(100.0, 30.0),
  // middle rung
  vec2f(30.0, 60.0),
  vec2f(70.0, 60.0),
  vec2f(30.0, 90.0),
  vec2f(30.0, 90.0),
  vec2f(70.0, 60.0),
  vec2f(70.0, 90.0)
);

// Constants - using unit circle values directly!
// The key insight: rotation = point on unit circle = (cos, sin)
const color = vec4f(0.2, 0.7, 0.7, 1.0);  // teal
const resolution = vec2f(%f, %f);
const translation = vec2f(200.0, 150.0);
const rotation = vec2f(%f, %f);  // cos(30), sin(30) from unit circle

struct VSOutput {
  @builtin(position) position: vec4f,
};

@vertex fn vs(@builtin(vertex_index) vertex_index: u32) -> VSOutput {
  var vsOut: VSOutput;

  let pos = positions[vertex_index];

  // Rotate using unit circle values (cos, sin)
  // This is the rotation matrix multiplication:
  //   [cos  -sin] [x]   [x*cos - y*sin]
  //   [sin   cos] [y] = [x*sin + y*cos]
  let rotatedPosition = vec2f(
    pos.x * rotation.x - pos.y * rotation.y,
    pos.x * rotation.y + pos.y * rotation.x
  );

  let position = rotatedPosition + translation;
  let zeroToOne = position / resolution;
  let zeroToTwo = zeroToOne * 2.0;
  let flippedClipSpace = zeroToTwo - 1.0;
  let clipSpace = flippedClipSpace * vec2f(1, -1);

  vsOut.position = vec4f(clipSpace, 0.0, 1.0);
  return vsOut;
}

@fragment fn fs(vsOut: VSOutput) -> @location(0) vec4f {
  return color;
}
|}
    (Float.of_int width)
    (Float.of_int height)
    cos_angle
    sin_angle
;;

let init () =
  let instance = Wgpu.Instance.create () in
  let adapter = Wgpu.Instance.request_adapter instance () in
  let device = Wgpu.Adapter.request_device adapter in
  let queue = Wgpu.Device.get_queue device in
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
  instance, adapter, device, queue, texture, texture_view, readback_buffer
;;

let create_pipeline ~device ~cos_angle ~sin_angle =
  let wgsl = shader_code ~cos_angle ~sin_angle in
  let shader =
    Wgpu.Device.create_shader_module device ~label:"rotation_unit_circle_shader" ~wgsl ()
  in
  let pipeline =
    Wgpu.Device.create_render_pipeline
      device
      ~label:"rotation_unit_circle_pipeline"
      ~shader_module:shader
      ~vertex_entry_point:"vs"
      ~fragment_entry_point:"fs"
      ~color_format:Wgpu.Texture_format.Rgba8_unorm
      ()
  in
  shader, pipeline
;;

let () =
  let instance, adapter, device, queue, texture, texture_view, readback_buffer =
    init ()
  in
  (* Use unit circle values for 30 degrees - this is the key insight!
     Instead of thinking about angles, think about the point on the unit circle.
     cos(30) = sqrt(3)/2 ~ 0.866
     sin(30) = 0.5 *)
  let cos_30 = Float.sqrt 3.0 /. 2.0 in
  let sin_30 = 0.5 in
  let shader, pipeline = create_pipeline ~device ~cos_angle:cos_30 ~sin_angle:sin_30 in
  let encoder = Wgpu.Device.create_command_encoder device ~label:"render_encoder" () in
  let render_pass =
    Wgpu.begin_render_pass
      encoder
      ~label:"rotation_unit_circle_pass"
      ~color_view:texture_view
      ~clear_color:(0.3, 0.3, 0.3, 1.0)
      ()
  in
  Wgpu.Render_pass_encoder.set_pipeline render_pass ~pipeline;
  Wgpu.Render_pass_encoder.draw
    render_pass
    ~vertex_count:num_vertices
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
  let ( (* Write output *) ) =
    let ppm_file = Test_util.output_path "rotation_via_unit_circle.ppm" in
    let png_file = Test_util.output_path "rotation_via_unit_circle.png" in
    Test_util.write_ppm ~filename:ppm_file ~width ~height ~data:mapped_data ~bytes_per_row;
    Test_util.ppm_to_png ~ppm_file ~png_file;
    Core_unix.unlink ppm_file
  in
  Wgpu.Buffer.unmap readback_buffer;
  (* Cleanup *)
  Wgpu.Command_buffer.release command_buffer;
  Wgpu.Render_pass_encoder.release render_pass;
  Wgpu.Command_encoder.release encoder;
  Wgpu.Render_pipeline.release pipeline;
  Wgpu.Shader_module.release shader;
  Wgpu.Buffer.release readback_buffer;
  Wgpu.Texture_view.release texture_view;
  Wgpu.Texture.release texture;
  Wgpu.Queue.release queue;
  Wgpu.Device.release device;
  Wgpu.Adapter.release adapter;
  Wgpu.Instance.release instance
;;
