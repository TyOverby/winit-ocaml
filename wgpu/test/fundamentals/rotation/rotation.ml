(* WebGPU Fundamentals: Rotation

   This test demonstrates 2D rotation in WebGPU. The F shape is rotated around its origin
   by computing cos/sin of the rotation angle and passing them to the shader via a uniform
   buffer. The shader applies the 2D rotation matrix:

   rotatedX = x * cos(angle) - y * sin(angle) rotatedY = x * sin(angle) + y * cos(angle)

   We render at 0, 45, 90, and 180 degrees to show the rotation in action.
*)

open! Core

let width = 600
let height = 400
let bytes_per_pixel = 4
let bytes_per_row = ((width * bytes_per_pixel) + 255) / 256 * 256
let buffer_size = bytes_per_row * height

(* F shape vertices in pixel coordinates *)
let create_f_vertices () =
  (* Position data: x, y pairs for each vertex *)
  let vertex_data =
    [| (* left column *)
       0.0
     ; 0.0
     ; 30.0
     ; 0.0
     ; 0.0
     ; 150.0
     ; 30.0
     ; 150.0
     ; (* top rung *)
       30.0
     ; 0.0
     ; 100.0
     ; 0.0
     ; 30.0
     ; 30.0
     ; 100.0
     ; 30.0
     ; (* middle rung *)
       30.0
     ; 60.0
     ; 70.0
     ; 60.0
     ; 30.0
     ; 90.0
     ; 70.0
     ; 90.0
    |]
  in
  (* Index data: triangles *)
  let index_data =
    [| 0
     ; 1
     ; 2
     ; 2
     ; 1
     ; 3 (* left column *)
     ; 4
     ; 5
     ; 6
     ; 6
     ; 5
     ; 7 (* top rung *)
     ; 8
     ; 9
     ; 10
     ; 10
     ; 9
     ; 11 (* middle rung *)
    |]
  in
  vertex_data, index_data
;;

let shader_code =
  {|
struct Uniforms {
  color: vec4f,
  resolution: vec2f,
  translation: vec2f,
  rotation: vec2f,
};

struct Vertex {
  @location(0) position: vec2f,
};

struct VSOutput {
  @builtin(position) position: vec4f,
};

@group(0) @binding(0) var<uniform> uni: Uniforms;

@vertex fn vs(vert: Vertex) -> VSOutput {
  var vsOut: VSOutput;

  // Rotate the position using the rotation values (cos, sin)
  let rotatedPosition = vec2f(
    vert.position.x * uni.rotation.x - vert.position.y * uni.rotation.y,
    vert.position.x * uni.rotation.y + vert.position.y * uni.rotation.x
  );

  // Add in the translation
  let position = rotatedPosition + uni.translation;

  // Convert the position from pixels to 0.0 to 1.0
  let zeroToOne = position / uni.resolution;

  // Convert from 0 <-> 1 to 0 <-> 2
  let zeroToTwo = zeroToOne * 2.0;

  // Convert from 0 <-> 2 to -1 <-> +1 (clip space)
  let flippedClipSpace = zeroToTwo - 1.0;

  // Flip Y
  let clipSpace = flippedClipSpace * vec2f(1, -1);

  vsOut.position = vec4f(clipSpace, 0.0, 1.0);
  return vsOut;
}

@fragment fn fs(vsOut: VSOutput) -> @location(0) vec4f {
  return uni.color;
}
|}
;;

(* Uniform buffer layout:
   - color: vec4f (4 floats, 16 bytes)
   - resolution: vec2f (2 floats, 8 bytes)
   - translation: vec2f (2 floats, 8 bytes)
   - rotation: vec2f (2 floats, 8 bytes)
   - padding: 8 bytes (to align to 16 bytes) Total: 48 bytes *)
let num_uniform_floats = 12
let uniform_buffer_size = num_uniform_floats * 4

let init () =
  let instance = Wgpu.Instance.create () in
  let adapter = Wgpu.Instance.request_adapter instance () in
  let device = Wgpu.Adapter.request_device adapter in
  let queue = Wgpu.Device.get_queue device in
  let shader =
    Wgpu.Device.create_shader_module device ~label:"rotation_shader" ~wgsl:shader_code ()
  in
  instance, adapter, device, queue, shader
;;

let render
  ~device
  ~queue
  ~pipeline
  ~vertex_buffer
  ~vertex_buffer_size
  ~index_buffer
  ~num_indices
  ~uniform_buffer
  ~bind_group
  ~translation_x
  ~translation_y
  ~rotation_angle
  ~output_name
  =
  (* Create render target texture *)
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
  (* Update uniform buffer with rotation values *)
  let uniform_data =
    Bigarray.Array1.create Bigarray.float32 Bigarray.c_layout num_uniform_floats
  in
  (* Color: orange *)
  Bigarray.Array1.set uniform_data 0 1.0;
  Bigarray.Array1.set uniform_data 1 0.5;
  Bigarray.Array1.set uniform_data 2 0.0;
  Bigarray.Array1.set uniform_data 3 1.0;
  (* Resolution *)
  Bigarray.Array1.set uniform_data 4 (Float.of_int width);
  Bigarray.Array1.set uniform_data 5 (Float.of_int height);
  (* Translation *)
  Bigarray.Array1.set uniform_data 6 translation_x;
  Bigarray.Array1.set uniform_data 7 translation_y;
  (* Rotation: cos(angle), sin(angle) *)
  let cos_angle = Float.cos rotation_angle in
  let sin_angle = Float.sin rotation_angle in
  Bigarray.Array1.set uniform_data 8 cos_angle;
  Bigarray.Array1.set uniform_data 9 sin_angle;
  (* Padding *)
  Bigarray.Array1.set uniform_data 10 0.0;
  Bigarray.Array1.set uniform_data 11 0.0;
  Wgpu.Queue.write_buffer queue ~buffer:uniform_buffer ~offset:0L ~data:uniform_data;
  (* Render *)
  let encoder = Wgpu.Device.create_command_encoder device ~label:"render_encoder" () in
  let render_pass =
    Wgpu.Command_encoder.begin_render_pass
      encoder
      ~label:"rotation_pass"
      ~color_attachments:
        [ Wgpu.Render_pass_color_attachment.create
            ~view:texture_view
            ~load_op:Wgpu.Load_op.Clear
            ~store_op:Wgpu.Store_op.Store
            ~clear_value:
              (Wgpu.Render_pass_color_attachment.Color.create
                 ~r:0.2
                 ~g:0.2
                 ~b:0.3
                 ~a:1.0
                 ())
            ()
        ]
      ()
  in
  Wgpu.Render_pass_encoder.set_pipeline render_pass ~pipeline;
  Wgpu.Render_pass_encoder.set_vertex_buffer
    render_pass
    ~slot:0
    ~buffer:vertex_buffer
    ~offset:0L
    ~size:(Int64.of_int vertex_buffer_size);
  Wgpu.Render_pass_encoder.set_index_buffer
    render_pass
    ~buffer:index_buffer
    ~format:Wgpu.Index_format.Uint32
    ~offset:0L
    ~size:(Int64.of_int (num_indices * 4));
  Wgpu.set_bind_group_render render_pass ~index:0 ~bind_group;
  Wgpu.Render_pass_encoder.draw_indexed
    render_pass
    ~index_count:num_indices
    ~instance_count:1
    ~first_index:0
    ~base_vertex:0
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
    let ppm_file = Test_util.output_path (output_name ^ ".ppm") in
    let png_file = Test_util.output_path (output_name ^ ".png") in
    Test_util.write_ppm ~filename:ppm_file ~width ~height ~data:mapped_data ~bytes_per_row;
    Test_util.ppm_to_png ~ppm_file ~png_file;
    ()
  in
  Wgpu.Buffer.unmap readback_buffer;
  (* Cleanup frame-specific resources *)
  Wgpu.Command_buffer.release command_buffer;
  Wgpu.Render_pass_encoder.release render_pass;
  Wgpu.Command_encoder.release encoder;
  Wgpu.Buffer.release readback_buffer;
  Wgpu.Texture_view.release texture_view;
  Wgpu.Texture.release texture
;;

let () =
  let instance, adapter, device, queue, shader = init () in
  let vertex_data, index_data = create_f_vertices () in
  (* Create vertex buffer *)
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
  (* Create index buffer *)
  let num_indices = Array.length index_data in
  let index_buffer_size = num_indices * 4 in
  let index_buffer =
    Wgpu.Device.create_buffer
      device
      ~label:"index_buffer"
      ~size:(Int64.of_int index_buffer_size)
      ~usage:[ Wgpu.Buffer_usage.Item.Index; Wgpu.Buffer_usage.Item.Copy_dst ]
      ~mapped_at_creation:false
      ()
  in
  let ( (* Upload index data *) ) =
    let index_bigarray =
      Bigarray.Array1.create Bigarray.int32 Bigarray.c_layout (Array.length index_data)
    in
    Array.iteri index_data ~f:(fun i v ->
      Bigarray.Array1.set index_bigarray i (Int32.of_int_exn v));
    Wgpu.Queue.write_buffer queue ~buffer:index_buffer ~offset:0L ~data:index_bigarray
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
  (* Create bind group layout and bind group *)
  let bind_group_layout =
    Wgpu.Device.create_bind_group_layout_for_uniform_buffer
      device
      ~label:"uniform_bind_group_layout"
      ~binding:0
      ~visibility:[ Wgpu.Shader_stage.Item.Vertex; Wgpu.Shader_stage.Item.Fragment ]
      ()
  in
  let bind_group =
    Wgpu.Device.create_bind_group
      device
      ~label:"uniform_bind_group"
      ~layout:bind_group_layout
      ~entries:
        [ Wgpu.Bind_group_entry.create
            ~binding:0
            ~buffer:uniform_buffer
            ~offset:0L
            ~size:(Int64.of_int uniform_buffer_size)
            ()
        ]
      ()
  in
  (* Create pipeline layout *)
  let pipeline_layout =
    Wgpu.Device.create_pipeline_layout
      device
      ~label:"rotation_pipeline_layout"
      ~bind_group_layouts:[ bind_group_layout ]
      ()
  in
  (* Define vertex buffer layout *)
  let vertex_buffer_layout =
    Wgpu.Vertex_buffer_layout.create
      ~step_mode:Wgpu.Vertex_step_mode.Vertex
      ~array_stride:(Int64.of_int (2 * 4))
      ~attributes:
        [ Wgpu.Vertex_attribute.create
            ~format:Wgpu.Vertex_format.Float32x2
            ~offset:0L
            ~shader_location:0
            ()
        ]
      ()
  in
  (* Create render pipeline *)
  let pipeline =
    Wgpu.Device.create_render_pipeline
      device
      ~label:"rotation_pipeline"
      ~layout:pipeline_layout
      ~vertex_module:shader
      ~vertex_entry_point:"vs"
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
  (* Render at different rotation angles *)
  let deg_to_rad d = d *. Float.pi /. 180.0 in
  let translation_x = 200.0 in
  let translation_y = 150.0 in
  let angles =
    [ 0.0, "rotation_0deg"
    ; 45.0, "rotation_45deg"
    ; 90.0, "rotation_90deg"
    ; 180.0, "rotation_180deg"
    ]
  in
  List.iter angles ~f:(fun (degrees, output_name) ->
    let rotation_angle = deg_to_rad degrees in
    render
      ~device
      ~queue
      ~pipeline
      ~vertex_buffer
      ~vertex_buffer_size
      ~index_buffer
      ~num_indices
      ~uniform_buffer
      ~bind_group
      ~translation_x
      ~translation_y
      ~rotation_angle
      ~output_name);
  (* Cleanup *)
  Wgpu.Render_pipeline.release pipeline;
  Wgpu.Pipeline_layout.release pipeline_layout;
  Wgpu.Bind_group.release bind_group;
  Wgpu.Bind_group_layout.release bind_group_layout;
  Wgpu.Buffer.release uniform_buffer;
  Wgpu.Buffer.release index_buffer;
  Wgpu.Buffer.release vertex_buffer;
  Wgpu.Shader_module.release shader;
  Wgpu.Queue.release queue;
  Wgpu.Device.release device;
  Wgpu.Adapter.release adapter;
  Wgpu.Instance.release instance
;;
