open! Core

(* Test multisampling (MSAA) support.

   This test renders a diagonal line to demonstrate anti-aliasing:
   - Creates a 4x MSAA texture
   - Creates a render pipeline with multisample_count:4
   - Renders to the MSAA texture with a resolve target
   - The resolved output should show anti-aliased (smooth) edges

   A diagonal line is used because it clearly shows aliasing artifacts
   when MSAA is not working, and smooth edges when it is.
*)

let width = 128
let height = 128
let bytes_per_pixel = 4
let bytes_per_row = ((width * bytes_per_pixel) + 255) / 256 * 256
let buffer_size = bytes_per_row * height

(* Shader that draws a thin diagonal line 
   TODO: this doesn't actually demonstrate antialising because MSAA doesn't
   multisample the interior of triangles. *)
let shader_code =
  {|
struct VertexOutput {
    @builtin(position) position: vec4<f32>,
    @location(0) uv: vec2<f32>,
}

@vertex
fn vs_main(@builtin(vertex_index) in_vertex_index: u32) -> VertexOutput {
    // Full-screen quad vertices
    var positions = array<vec2<f32>, 6>(
        vec2<f32>(-1.0, -1.0),
        vec2<f32>( 1.0, -1.0),
        vec2<f32>(-1.0,  1.0),
        vec2<f32>(-1.0,  1.0),
        vec2<f32>( 1.0, -1.0),
        vec2<f32>( 1.0,  1.0),
    );

    var output: VertexOutput;
    output.position = vec4<f32>(positions[in_vertex_index], 0.0, 1.0);
    output.uv = (positions[in_vertex_index] + 1.0) * 0.5;
    return output;
}

@fragment
fn fs_main(input: VertexOutput) -> @location(0) vec4<f32> {
    // Draw a diagonal line from bottom-left to top-right
    // The line has thickness of about 2 pixels
    let line_distance = abs(input.uv.x - input.uv.y);
    let line_thickness = 0.02;

    if (line_distance < line_thickness) {
        return vec4<f32>(1.0, 0.5, 0.0, 1.0);  // Orange line
    } else {
        return vec4<f32>(0.1, 0.1, 0.2, 1.0);  // Dark blue background
    }
}
|}
;;

let init () =
  let instance = Wgpu.Instance.create () in
  let adapter = Wgpu.Instance.request_adapter instance () in
  let device = Wgpu.Adapter.request_device adapter in
  let queue = Wgpu.Device.get_queue device in
  let shader =
    Wgpu.Device.create_shader_module device ~label:"msaa_shader" ~wgsl:shader_code ()
  in
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
  ( instance
  , adapter
  , device
  , queue
  , shader
  , msaa_texture
  , msaa_view
  , resolve_texture
  , resolve_view
  , readback_buffer )
;;

let cleanup
  ~instance
  ~adapter
  ~device
  ~queue
  ~shader
  ~msaa_texture
  ~msaa_view
  ~resolve_texture
  ~resolve_view
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

let () =
  let ( instance
      , adapter
      , device
      , queue
      , shader
      , msaa_texture
      , msaa_view
      , resolve_texture
      , resolve_view
      , readback_buffer )
    =
    init ()
  in
  (* Create render pipeline with 4x MSAA *)
  let pipeline =
    Wgpu.Device.create_render_pipeline
      device
      ~label:"msaa_pipeline"
      ~vertex_module:shader
      ~vertex_entry_point:"vs_main"
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
  let encoder = Wgpu.Device.create_command_encoder device ~label:"render_encoder" () in
  (* Begin render pass with MSAA texture and resolve target *)
  let render_pass =
    Wgpu.begin_render_pass
      encoder
      ~label:"msaa_pass"
      ~color_view:msaa_view
      ~load_op:Wgpu.Load_op.Clear
      ~store_op:Wgpu.Store_op.Discard
      ~clear_color:(0.1, 0.1, 0.2, 1.0)
      ~resolve_target:resolve_view
      ()
  in
  Wgpu.Render_pass_encoder.set_pipeline render_pass ~pipeline;
  (* Draw full-screen quad (6 vertices for 2 triangles) *)
  Wgpu.Render_pass_encoder.draw
    render_pass
    ~vertex_count:6
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
  (* Verify the output *)
  (* Check a pixel on the diagonal - should be orange (255, 128, 0) or similar *)
  let diag_x = width / 2 in
  let diag_y = height / 2 in
  let diag_offset = (diag_y * bytes_per_row) + (diag_x * bytes_per_pixel) in
  let dr = Bigarray.Array1.get mapped_data diag_offset in
  let dg = Bigarray.Array1.get mapped_data (diag_offset + 1) in
  let db = Bigarray.Array1.get mapped_data (diag_offset + 2) in
  (* Check a corner pixel - should be dark blue background *)
  let corner_offset = 0 in
  let cr = Bigarray.Array1.get mapped_data corner_offset in
  let cg = Bigarray.Array1.get mapped_data (corner_offset + 1) in
  let cb = Bigarray.Array1.get mapped_data (corner_offset + 2) in
  (* The diagonal should have orange-ish color (high red, medium green, low blue) *)
  let diag_is_orange = dr > 200 && dg > 100 && dg < 200 && db < 50 in
  (* The corner should be dark blue (low red/green, higher blue) *)
  let corner_is_dark_blue = cr < 50 && cg < 50 && cb > 30 in
  let ( (* Write output *) ) =
    let ppm_file = Test_util.output_path "multisampling.ppm" in
    let png_file = Test_util.output_path "multisampling.png" in
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
    ~msaa_texture
    ~msaa_view
    ~resolve_texture
    ~resolve_view
    ~readback_buffer
    ~pipeline
    ~command_buffer
    ~render_pass
    ~encoder;
  if not (diag_is_orange && corner_is_dark_blue)
  then (
    print_s
      [%message
        "FAILURE: Unexpected pixel values"
          ~diagonal:((dr, dg, db) : int * int * int)
          ~corner:((cr, cg, cb) : int * int * int)];
    exit 1)
;;
