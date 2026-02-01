open! Core

(* Test depth testing with overlapping triangles.

   This test renders two overlapping triangles:
   - A red triangle at z=0.3 (closer to camera)
   - A blue triangle at z=0.7 (further from camera)

   With proper depth testing, the red triangle should appear on top of the blue triangle
   in the overlapping region.
*)

let width = 128
let height = 128
let bytes_per_pixel = 4
let bytes_per_row = ((width * bytes_per_pixel) + 255) / 256 * 256
let buffer_size = bytes_per_row * height

(* Shader that takes vertex position and color from vertex buffer *)
let shader_code =
  {|
struct VertexInput {
    @location(0) position: vec3<f32>,
    @location(1) color: vec3<f32>,
}

struct VertexOutput {
    @builtin(position) position: vec4<f32>,
    @location(0) color: vec3<f32>,
}

@vertex
fn vs_main(input: VertexInput) -> VertexOutput {
    var output: VertexOutput;
    output.position = vec4<f32>(input.position, 1.0);
    output.color = input.color;
    return output;
}

@fragment
fn fs_main(input: VertexOutput) -> @location(0) vec4<f32> {
    return vec4<f32>(input.color, 1.0);
}
|}
;;

(* Vertex data: position (x, y, z) and color (r, g, b) *)
(* Red triangle at z=0.3 (closer to camera, should be on top) *)
(* Blue triangle at z=0.7 (further from camera) *)
let vertex_data =
  [| (* Red triangle - closer (z=0.3), positioned slightly right *)
     (* v0 *)
     -0.3
   ; 0.8
   ; 0.3
   ; 1.0
   ; 0.0
   ; 0.0
   ; (* v1 *) 0.7
   ; 0.8
   ; 0.3
   ; 1.0
   ; 0.0
   ; 0.0
   ; (* v2 *) 0.2
   ; -0.8
   ; 0.3
   ; 1.0
   ; 0.0
   ; 0.0
   ; (* Blue triangle - further (z=0.7), positioned slightly left *)
     (* v3 *)
     -0.7
   ; 0.8
   ; 0.7
   ; 0.0
   ; 0.0
   ; 1.0
   ; (* v4 *) 0.3
   ; 0.8
   ; 0.7
   ; 0.0
   ; 0.0
   ; 1.0
   ; (* v5 *) -0.2
   ; -0.8
   ; 0.7
   ; 0.0
   ; 0.0
   ; 1.0
  |]
;;

let num_vertices = 6
let floats_per_vertex = 6
let bytes_per_vertex = floats_per_vertex * 4
let vertex_buffer_size = num_vertices * bytes_per_vertex

let init () =
  let instance = Wgpu.Instance.create () in
  let adapter = Wgpu.Instance.request_adapter instance () in
  let device = Wgpu.Adapter.request_device adapter in
  let queue = Wgpu.Device.get_queue device in
  let shader =
    Wgpu.Device.create_shader_module
      device
      ~label:"depth_test_shader"
      ~wgsl:shader_code
      ()
  in
  (* Create color texture *)
  let color_texture =
    Wgpu.Device.create_texture
      device
      ~label:"color_target"
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
  let color_view = Wgpu.create_texture_view color_texture ~label:"color_view" () in
  (* Create depth texture *)
  let depth_texture =
    Wgpu.Device.create_texture
      device
      ~label:"depth_target"
      ~size_width:width
      ~size_height:height
      ~size_depth_or_array_layers:1
      ~dimension:N2d
      ~mip_level_count:1
      ~sample_count:1
      ~format:Wgpu.Texture_format.Depth24_plus
      ~usage:[ Wgpu.Texture_usage.Item.Render_attachment ]
      ()
  in
  let depth_view = Wgpu.create_texture_view depth_texture ~label:"depth_view" () in
  (* Create vertex buffer *)
  let vertex_buffer =
    Wgpu.Device.create_buffer
      device
      ~label:"vertex_buffer"
      ~size:(Int64.of_int vertex_buffer_size)
      ~usage:[ Wgpu.Buffer_usage.Item.Vertex; Wgpu.Buffer_usage.Item.Copy_dst ]
      ~mapped_at_creation:false
      ()
  in
  (* Write vertex data to buffer *)
  let vertex_bigarray =
    Bigarray.Array1.of_array Bigarray.float32 Bigarray.c_layout vertex_data
  in
  Wgpu.Queue.write_buffer queue ~buffer:vertex_buffer ~offset:0L ~data:vertex_bigarray;
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
  , color_texture
  , color_view
  , depth_texture
  , depth_view
  , vertex_buffer
  , readback_buffer )
;;

let cleanup
  ~instance
  ~adapter
  ~device
  ~queue
  ~shader
  ~color_texture
  ~color_view
  ~depth_texture
  ~depth_view
  ~vertex_buffer
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
  Wgpu.Buffer.release vertex_buffer;
  Wgpu.Render_pipeline.release pipeline;
  Wgpu.Texture_view.release depth_view;
  Wgpu.Texture.release depth_texture;
  Wgpu.Texture_view.release color_view;
  Wgpu.Texture.release color_texture;
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
      , color_texture
      , color_view
      , depth_texture
      , depth_view
      , vertex_buffer
      , readback_buffer )
    =
    init ()
  in
  (* Create render pipeline with depth testing enabled *)
  let vertex_buffer_layout : Wgpu.Vertex_buffer_layout.t =
    { step_mode = Wgpu.Vertex_step_mode.Vertex
    ; array_stride = Int64.of_int bytes_per_vertex
    ; attributes =
        [ { format = Wgpu.Vertex_format.Float32x3; offset = 0L; shader_location = 0 }
        ; { format = Wgpu.Vertex_format.Float32x3
          ; offset = Int64.of_int (3 * 4)
          ; shader_location = 1
          }
        ]
    }
  in
  let pipeline =
    Wgpu.Device.create_render_pipeline
      device
      ~label:"depth_test_pipeline"
      ~vertex_module:shader
      ~vertex_entry_point:"vs_main"
      ~vertex_buffers:[ vertex_buffer_layout ]
      ~primitive_topology:Wgpu.Primitive_topology.Triangle_list
      ~primitive_strip_index_format:Wgpu.Index_format.Undefined
      ~primitive_front_face:Wgpu.Front_face.Ccw
      ~primitive_cull_mode:Wgpu.Cull_mode.None
      ~primitive_unclipped_depth:false
      ~depth_stencil:
        { format = Wgpu.Texture_format.Depth24_plus
        ; depth_write_enabled = True
        ; depth_compare = Wgpu.Compare_function.Less
        ; stencil_front =
            { compare = Wgpu.Compare_function.Always
            ; fail_op = Wgpu.Stencil_operation.Keep
            ; depth_fail_op = Wgpu.Stencil_operation.Keep
            ; pass_op = Wgpu.Stencil_operation.Keep
            }
        ; stencil_back =
            { compare = Wgpu.Compare_function.Always
            ; fail_op = Wgpu.Stencil_operation.Keep
            ; depth_fail_op = Wgpu.Stencil_operation.Keep
            ; pass_op = Wgpu.Stencil_operation.Keep
            }
        ; stencil_read_mask = 0xFFFFFFFF
        ; stencil_write_mask = 0xFFFFFFFF
        ; depth_bias = 0
        ; depth_bias_slope_scale = 0.0
        ; depth_bias_clamp = 0.0
        }
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
    Wgpu.Command_encoder.begin_render_pass
      encoder
      ~label:"depth_test_pass"
      ~color_attachments:
        [ { view = Some color_view
          ; depth_slice = 0xFFFFFFFF
          ; resolve_target = None
          ; load_op = Wgpu.Load_op.Clear
          ; store_op = Wgpu.Store_op.Store
          ; clear_value = Some { r = 0.2; g = 0.2; b = 0.2; a = 1.0 }
          }
        ]
      ~depth_stencil_attachment:
        { view = depth_view
        ; depth_load_op = Wgpu.Load_op.Clear
        ; depth_store_op = Wgpu.Store_op.Discard
        ; depth_clear_value = 1.0
        ; depth_read_only = false
        ; stencil_load_op = Wgpu.Load_op.Clear
        ; stencil_store_op = Wgpu.Store_op.Store
        ; stencil_clear_value = 0
        ; stencil_read_only = false
        }
      ()
  in
  Wgpu.Render_pass_encoder.set_pipeline render_pass ~pipeline;
  Wgpu.Render_pass_encoder.set_vertex_buffer
    render_pass
    ~slot:0
    ~buffer:vertex_buffer
    ~offset:0L
    ~size:(Int64.of_int vertex_buffer_size);
  (* Draw all 6 vertices (both triangles) *)
  Wgpu.Render_pass_encoder.draw
    render_pass
    ~vertex_count:num_vertices
    ~instance_count:1
    ~first_vertex:0
    ~first_instance:0;
  Wgpu.Render_pass_encoder.end_ render_pass;
  Wgpu.copy_texture_to_buffer
    encoder
    ~texture:color_texture
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
  (* Check center pixel - should be red because the red triangle is closer (z=0.3 < z=0.7) *)
  let center_x = width / 2 in
  let center_y = height / 2 in
  let center_offset = (center_y * bytes_per_row) + (center_x * bytes_per_pixel) in
  let cr = Bigarray.Array1.get mapped_data center_offset in
  let cg = Bigarray.Array1.get mapped_data (center_offset + 1) in
  let cb = Bigarray.Array1.get mapped_data (center_offset + 2) in
  let _ca = Bigarray.Array1.get mapped_data (center_offset + 3) in
  (* The center should be red (the closer triangle) *)
  let center_is_red = cr > 200 && cg < 50 && cb < 50 in
  let ( (* Write output *) ) =
    let ppm_file = Test_util.output_path "depth_test.ppm" in
    let png_file = Test_util.output_path "depth_test.png" in
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
    ~color_texture
    ~color_view
    ~depth_texture
    ~depth_view
    ~vertex_buffer
    ~readback_buffer
    ~pipeline
    ~command_buffer
    ~render_pass
    ~encoder;
  if not center_is_red
  then (
    print_s
      [%message
        "FAILURE: Center pixel should be red (from closer triangle)"
          ~center_color:((cr, cg, cb) : int * int * int)];
    exit 1)
;;
