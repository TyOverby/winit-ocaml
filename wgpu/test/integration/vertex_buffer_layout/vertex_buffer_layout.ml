open! Core

(* Test demonstrating vertex buffer layouts with @location attributes *)

let width = 64
let height = 64
let bytes_per_pixel = 4
let bytes_per_row = ((width * bytes_per_pixel) + 255) / 256 * 256
let buffer_size = bytes_per_row * height

(* Shader that uses @location(0) for position from vertex buffer *)
let shader_code =
  {|
struct VertexOutput {
    @builtin(position) position: vec4<f32>,
    @location(0) color: vec3<f32>,
};

@vertex
fn vs_main(@location(0) position: vec2<f32>, @location(1) color: vec3<f32>) -> VertexOutput {
    var output: VertexOutput;
    output.position = vec4<f32>(position, 0.0, 1.0);
    output.color = color;
    return output;
}

@fragment
fn fs_main(input: VertexOutput) -> @location(0) vec4<f32> {
    return vec4<f32>(input.color, 1.0);
}
|}
;;

(* Triangle vertices with position (Float32x2) and color (Float32x3) *)
(* Format: x, y, r, g, b for each vertex *)
let vertex_data =
  [| (* top vertex: red *)
     0.0
   ; 0.5
   ; 1.0
   ; 0.0
   ; 0.0
   ; (* bottom-left vertex: green *)
     -0.5
   ; -0.5
   ; 0.0
   ; 1.0
   ; 0.0
   ; (* bottom-right vertex: blue *)
     0.5
   ; -0.5
   ; 0.0
   ; 0.0
   ; 1.0
  |]
;;

let init () =
  let instance = Wgpu.Instance.create () in
  let adapter = Wgpu.Instance.request_adapter instance () in
  let device = Wgpu.Adapter.request_device adapter in
  let queue = Wgpu.Device.get_queue device in
  let shader =
    Wgpu.Device.create_shader_module
      device
      ~label:"vertex_buffer_shader"
      ~wgsl:shader_code
      ()
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
  ~vertex_buffer
  =
  Wgpu.Command_buffer.release command_buffer;
  Wgpu.Render_pass_encoder.release render_pass;
  Wgpu.Command_encoder.release encoder;
  Wgpu.Buffer.release readback_buffer;
  Wgpu.Buffer.release vertex_buffer;
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
  (* Create vertex buffer with position and color data *)
  let vertex_buffer_size = Array.length vertex_data * 4 in
  let vertex_buffer =
    Wgpu.Device.create_buffer
      device
      ~label:"vertex_buffer"
      ~size:(Int64.of_int vertex_buffer_size)
      ~usage:[ Wgpu.Buffer_usage.Item.Vertex; Wgpu.Buffer_usage.Item.Copy_dst ]
      ~mapped_at_creation:false
      ()
  in
  let ( (* Upload vertex data *) ) =
    let vertex_bigarray =
      Bigarray.Array1.create Bigarray.float32 Bigarray.c_layout (Array.length vertex_data)
    in
    Array.iteri vertex_data ~f:(fun i v -> Bigarray.Array1.set vertex_bigarray i v);
    Wgpu.Queue.write_buffer queue ~buffer:vertex_buffer ~offset:0L ~data:vertex_bigarray
  in
  (* Define vertex buffer layout with two attributes:
     - position at @location(0): Float32x2, offset 0
     - color at @location(1): Float32x3, offset 8 (after 2 floats) *)
  let vertex_buffer_layout =
    { Wgpu.Vertex_buffer_layout.step_mode = Wgpu.Vertex_step_mode.Vertex
    ; array_stride = Int64.of_int (5 * 4)
    ; attributes =
        [ { Wgpu.Vertex_attribute.format = Wgpu.Vertex_format.Float32x2
          ; offset = 0L
          ; shader_location = 0
          }
        ; { Wgpu.Vertex_attribute.format = Wgpu.Vertex_format.Float32x3
          ; offset = Int64.of_int (2 * 4)
          ; shader_location = 1
          }
        ]
    }
  in
  (* Create render pipeline with vertex buffer layout *)
  let pipeline =
    Wgpu.Device.create_render_pipeline
      device
      ~label:"vertex_buffer_pipeline"
      ~vertex_module:shader
      ~vertex_entry_point:"vs_main"
      ~vertex_buffers:[ vertex_buffer_layout ]
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
  let encoder = Wgpu.Device.create_command_encoder device ~label:"render_encoder" () in
  let render_pass =
    Wgpu.begin_render_pass_simple
      encoder
      ~label:"vertex_buffer_pass"
      ~color_view:texture_view
      ~clear_color:(0.1, 0.1, 0.1, 1.0)
      ()
  in
  Wgpu.Render_pass_encoder.set_pipeline render_pass ~pipeline;
  Wgpu.Render_pass_encoder.set_vertex_buffer
    render_pass
    ~slot:0
    ~buffer:vertex_buffer
    ~offset:0L
    ~size:(Int64.of_int vertex_buffer_size);
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
  (* Write output image *)
  let ( (* Write output *) ) =
    let ppm_file = Test_util.output_path "vertex_buffer_layout.ppm" in
    let png_file = Test_util.output_path "vertex_buffer_layout.png" in
    Test_util.write_ppm ~filename:ppm_file ~width ~height ~data:mapped_data ~bytes_per_row;
    Test_util.ppm_to_png ~ppm_file ~png_file;
    ()
  in
  (* Verify: check that center of triangle has interpolated colors (not background) *)
  let center_x = width / 2 in
  let center_y = height / 2 in
  let center_offset = (center_y * bytes_per_row) + (center_x * bytes_per_pixel) in
  let cr = Bigarray.Array1.get mapped_data center_offset in
  let cg = Bigarray.Array1.get mapped_data (center_offset + 1) in
  let cb = Bigarray.Array1.get mapped_data (center_offset + 2) in
  (* The center should have interpolated colors from red, green, and blue vertices *)
  let is_colored = cr > 50 || cg > 50 || cb > 50 in
  (* Check corner is background color (dark gray ~26) *)
  let corner_offset = 0 in
  let br = Bigarray.Array1.get mapped_data corner_offset in
  let bg = Bigarray.Array1.get mapped_data (corner_offset + 1) in
  let bb = Bigarray.Array1.get mapped_data (corner_offset + 2) in
  let corner_is_background = br < 30 && bg < 30 && bb < 30 in
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
    ~encoder
    ~vertex_buffer;
  if not (is_colored && corner_is_background)
  then (
    print_s
      [%message
        "FAILURE: Unexpected pixel values"
          ~center:((cr, cg, cb) : int * int * int)
          ~corner:((br, bg, bb) : int * int * int)
          ~is_colored:(is_colored : bool)
          ~corner_is_background:(corner_is_background : bool)];
    exit 1)
;;
