(*
   Rotation Example - Port of WebGPU Fundamentals rotation lesson

   This example demonstrates 2D rotation using a unit circle concept:
   - Rotation is applied by multiplying vertex positions by (cos, sin) of the angle
   - The formula: rotatedX = x * cos - y * sin
                  rotatedY = x * sin + y * cos

   We render an F-shape at four different rotation angles: 0, 45, 90, and 180 degrees.

   Note: The F-shape vertices are embedded in the shader to avoid the need for
   vertex buffer layouts, which simplifies the example while still demonstrating
   the core rotation concept.
*)

open! Core

let width = 600
let height = 400
let bytes_per_pixel = 4
let bytes_per_row = ((width * bytes_per_pixel) + 255) / 256 * 256
let buffer_size = bytes_per_row * height
let num_vertices = 18

(* Generate shader code with embedded constants for a specific rotation *)
let shader_code ~rotation_radians =
  let cos_angle = Float.cos rotation_radians in
  let sin_angle = Float.sin rotation_radians in
  Printf.sprintf
    {|
// F-shape vertices embedded in shader
// The F is made of 3 rectangles: left column, top rung, middle rung
// Each rectangle is 2 triangles = 6 vertices
const positions = array<vec2f, 18>(
  // left column (0-5)
  vec2f(0.0, 0.0),
  vec2f(30.0, 0.0),
  vec2f(0.0, 150.0),
  vec2f(0.0, 150.0),
  vec2f(30.0, 0.0),
  vec2f(30.0, 150.0),
  // top rung (6-11)
  vec2f(30.0, 0.0),
  vec2f(100.0, 0.0),
  vec2f(30.0, 30.0),
  vec2f(30.0, 30.0),
  vec2f(100.0, 0.0),
  vec2f(100.0, 30.0),
  // middle rung (12-17)
  vec2f(30.0, 60.0),
  vec2f(70.0, 60.0),
  vec2f(30.0, 90.0),
  vec2f(30.0, 90.0),
  vec2f(70.0, 60.0),
  vec2f(70.0, 90.0)
);

// Constants for this frame
const color = vec4f(1.0, 0.5, 0.2, 1.0);  // orange-ish
const resolution = vec2f(%f, %f);
const translation = vec2f(200.0, 150.0);
const rotation = vec2f(%f, %f);  // cos, sin

struct VSOutput {
  @builtin(position) position: vec4f,
};

@vertex fn vs(@builtin(vertex_index) vertex_index: u32) -> VSOutput {
  var vsOut: VSOutput;

  let pos = positions[vertex_index];

  // Rotate the position
  let rotatedPosition = vec2f(
    pos.x * rotation.x - pos.y * rotation.y,
    pos.x * rotation.y + pos.y * rotation.x
  );

  // Add in the translation
  let position = rotatedPosition + translation;

  // convert the position from pixels to a 0.0 to 1.0 value
  let zeroToOne = position / resolution;

  // convert from 0 <-> 1 to 0 <-> 2
  let zeroToTwo = zeroToOne * 2.0;

  // covert from 0 <-> 2 to -1 <-> +1 (clip space)
  let flippedClipSpace = zeroToTwo - 1.0;

  // flip Y
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

(* Create render pipeline for a specific rotation *)
let create_pipeline ~device ~rotation_radians =
  let wgsl = shader_code ~rotation_radians in
  let shader =
    Wgpu.Device.create_shader_module device ~label:"rotation_shader" ~wgsl ()
  in
  let pipeline =
    Wgpu.Device.create_render_pipeline
      device
      ~label:"rotation_pipeline"
      ~shader_module:shader
      ~vertex_entry_point:"vs"
      ~fragment_entry_point:"fs"
      ~color_format:Wgpu.Texture_format.Rgba8_unorm
      ()
  in
  shader, pipeline
;;

(* Render a frame and save to PNG *)
let render_frame
  ~device
  ~queue
  ~texture
  ~texture_view
  ~readback_buffer
  ~rotation_degrees
  ~output_name
  =
  let rotation_radians = Float.of_int rotation_degrees *. Float.pi /. 180.0 in
  let shader, pipeline = create_pipeline ~device ~rotation_radians in
  let encoder = Wgpu.Device.create_command_encoder device ~label:"render_encoder" () in
  let render_pass =
    Wgpu.begin_render_pass
      encoder
      ~label:"rotation_pass"
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
  in
  let ( (* Write output *) ) =
    let ppm_file = Test_util.output_path (output_name ^ ".ppm") in
    let png_file = Test_util.output_path (output_name ^ ".png") in
    Test_util.write_ppm ~filename:ppm_file ~width ~height ~data:mapped_data ~bytes_per_row;
    Test_util.ppm_to_png ~ppm_file ~png_file;
    Core_unix.unlink ppm_file
  in
  Wgpu.Buffer.unmap readback_buffer;
  (* Cleanup per-frame resources *)
  Wgpu.Command_buffer.release command_buffer;
  Wgpu.Render_pass_encoder.release render_pass;
  Wgpu.Command_encoder.release encoder;
  Wgpu.Render_pipeline.release pipeline;
  Wgpu.Shader_module.release shader
;;

let () =
  let instance, adapter, device, queue, texture, texture_view, readback_buffer =
    init ()
  in
  (* Render frames at different rotation angles *)
  let angles =
    [ 0, "rotation_0deg"
    ; 45, "rotation_45deg"
    ; 90, "rotation_90deg"
    ; 180, "rotation_180deg"
    ]
  in
  List.iter angles ~f:(fun (degrees, name) ->
    render_frame
      ~device
      ~queue
      ~texture
      ~texture_view
      ~readback_buffer
      ~rotation_degrees:degrees
      ~output_name:name);
  (* Cleanup *)
  Wgpu.Buffer.release readback_buffer;
  Wgpu.Texture_view.release texture_view;
  Wgpu.Texture.release texture;
  Wgpu.Queue.release queue;
  Wgpu.Device.release device;
  Wgpu.Adapter.release adapter;
  Wgpu.Instance.release instance
;;
