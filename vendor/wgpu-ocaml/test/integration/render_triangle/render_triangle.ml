open! Core

let width = 64
let height = 64
let bytes_per_pixel = 4
let bytes_per_row = ((width * bytes_per_pixel) + 255) / 256 * 256
let buffer_size = bytes_per_row * height

let shader_code =
  {|
@vertex
fn vs_main(@builtin(vertex_index) in_vertex_index: u32) -> @builtin(position) vec4<f32> {
    // Triangle vertices computed from vertex index
    let x = f32(i32(in_vertex_index) - 1);
    let y = f32(i32(in_vertex_index & 1u) * 2 - 1);
    return vec4<f32>(x, y, 0.0, 1.0);
}

@fragment
fn fs_main() -> @location(0) vec4<f32> {
    return vec4<f32>(0.0, 1.0, 0.0, 1.0);  // Green
}
|}
;;

let init () =
  let instance = Wgpu.Instance.create () in
  let adapter = Wgpu.Instance.request_adapter instance () in
  let device = Wgpu.Adapter.request_device adapter in
  let queue = Wgpu.Device.get_queue device in
  let shader =
    Wgpu.Device.create_shader_module device ~label:"triangle_shader" ~wgsl:shader_code ()
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
  ~pipeline
  ~command_buffer
  ~render_pass
  ~encoder
  =
  Wgpu.Command_buffer.release command_buffer;
  Wgpu.Render_pass_encoder.release render_pass;
  Wgpu.Command_encoder.release encoder;
  Wgpu.Buffer.release readback_buffer;
  Wgpu.Render_pipeline.release pipeline;
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
  let pipeline =
    Wgpu.Device.create_render_pipeline
      device
      ~label:"triangle_pipeline"
      ~shader_module:shader
      ~vertex_entry_point:"vs_main"
      ~fragment_entry_point:"fs_main"
      ~color_format:Wgpu.Texture_format.Rgba8_unorm
      ()
  in
  let encoder = Wgpu.Device.create_command_encoder device ~label:"render_encoder" () in
  let render_pass =
    Wgpu.begin_render_pass
      encoder
      ~label:"triangle_pass"
      ~color_view:texture_view
      ~clear_color:(0.0, 0.0, 1.0, 1.0)
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
  (* Check center pixel - should be green (triangle covers center) *)
  let center_x = width / 2 in
  let center_y = height / 2 in
  let center_offset = (center_y * bytes_per_row) + (center_x * bytes_per_pixel) in
  let cr = Bigarray.Array1.get mapped_data center_offset in
  let cg = Bigarray.Array1.get mapped_data (center_offset + 1) in
  let cb = Bigarray.Array1.get mapped_data (center_offset + 2) in
  let ca = Bigarray.Array1.get mapped_data (center_offset + 3) in
  (* Check corner pixel - should be blue (background) *)
  let corner_offset = 0 in
  let br = Bigarray.Array1.get mapped_data corner_offset in
  let bg = Bigarray.Array1.get mapped_data (corner_offset + 1) in
  let bb = Bigarray.Array1.get mapped_data (corner_offset + 2) in
  let ba = Bigarray.Array1.get mapped_data (corner_offset + 3) in
  let center_is_green = cr = 0 && cg = 255 && cb = 0 && ca = 255 in
  let corner_is_blue = br = 0 && bg = 0 && bb = 255 && ba = 255 in
  let ( (* Write output *) ) =
    let ppm_file = Test_util.output_path "render_triangle.ppm" in
    let png_file = Test_util.output_path "render_triangle.png" in
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
    ~pipeline
    ~command_buffer
    ~render_pass
    ~encoder;
  if not (center_is_green && corner_is_blue)
  then (
    print_s
      [%message
        "FAILURE: Unexpected pixel values"
          ~center:((cr, cg, cb, ca) : int * int * int * int)
          ~corner:((br, bg, bb, ba) : int * int * int * int)];
    exit 1)
;;
