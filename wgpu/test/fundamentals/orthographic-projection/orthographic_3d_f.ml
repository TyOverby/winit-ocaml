(*
   WebGPU Fundamentals: Orthographic Projection - 3D F

   This test demonstrates orthographic projection with a 3D "F" shape:
   - 3D vertex positions (x, y, z)
   - Per-face vertex colors using unorm8x4 format
   - Back-face culling (cullMode: 'front' because Y is flipped)
   - Depth testing with depth texture
   - Orthographic projection matrix

   The F shape has 16 faces (rectangles) forming a 3D letter F.
   Each face has a distinct color to make the 3D structure visible.

   We render at multiple rotation angles to show the 3D nature.
*)

open! Core

let width = 600
let height = 400
let bytes_per_pixel = 4
let bytes_per_row = ((width * bytes_per_pixel) + 255) / 256 * 256
let buffer_size = bytes_per_row * height

(* Shader that takes vertex position (xyz) and color (rgba as unorm8x4) *)
let shader_code =
  {|
struct Uniforms {
  matrix: mat4x4f,
};

struct Vertex {
  @location(0) position: vec4f,
  @location(1) color: vec4f,
};

struct VSOutput {
  @builtin(position) position: vec4f,
  @location(0) color: vec4f,
};

@group(0) @binding(0) var<uniform> uni: Uniforms;

@vertex fn vs(vert: Vertex) -> VSOutput {
  var vsOut: VSOutput;
  vsOut.position = uni.matrix * vert.position;
  vsOut.color = vert.color;
  return vsOut;
}

@fragment fn fs(vsOut: VSOutput) -> @location(0) vec4f {
  return vsOut.color;
}
|}
;;

(* 3D F vertex positions - front and back faces *)
let positions =
  [| (* left column front *)
     0.0
   ; 0.0
   ; 0.0
   ; 30.0
   ; 0.0
   ; 0.0
   ; 0.0
   ; 150.0
   ; 0.0
   ; 30.0
   ; 150.0
   ; 0.0
   ; (* top rung front *)
     30.0
   ; 0.0
   ; 0.0
   ; 100.0
   ; 0.0
   ; 0.0
   ; 30.0
   ; 30.0
   ; 0.0
   ; 100.0
   ; 30.0
   ; 0.0
   ; (* middle rung front *)
     30.0
   ; 60.0
   ; 0.0
   ; 70.0
   ; 60.0
   ; 0.0
   ; 30.0
   ; 90.0
   ; 0.0
   ; 70.0
   ; 90.0
   ; 0.0
   ; (* left column back *)
     0.0
   ; 0.0
   ; 30.0
   ; 30.0
   ; 0.0
   ; 30.0
   ; 0.0
   ; 150.0
   ; 30.0
   ; 30.0
   ; 150.0
   ; 30.0
   ; (* top rung back *)
     30.0
   ; 0.0
   ; 30.0
   ; 100.0
   ; 0.0
   ; 30.0
   ; 30.0
   ; 30.0
   ; 30.0
   ; 100.0
   ; 30.0
   ; 30.0
   ; (* middle rung back *)
     30.0
   ; 60.0
   ; 30.0
   ; 70.0
   ; 60.0
   ; 30.0
   ; 30.0
   ; 90.0
   ; 30.0
   ; 70.0
   ; 90.0
   ; 30.0
  |]
;;

(* Indices for all 16 faces of the 3D F - with correct winding order for cullMode: 'front' *)
let indices =
  [| (* front faces *)
     0
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
   ; (* back faces - reversed winding *)
     12
   ; 14
   ; 13
   ; 14
   ; 15
   ; 13 (* left column back *)
   ; 16
   ; 18
   ; 17
   ; 18
   ; 19
   ; 17 (* top rung back *)
   ; 20
   ; 22
   ; 21
   ; 22
   ; 23
   ; 21 (* middle rung back *)
   ; (* connecting faces *)
     0
   ; 12
   ; 5
   ; 12
   ; 17
   ; 5 (* top *)
   ; 5
   ; 17
   ; 7
   ; 17
   ; 19
   ; 7 (* top rung right *)
   ; 6
   ; 7
   ; 18
   ; 18
   ; 7
   ; 19 (* top rung bottom *)
   ; 6
   ; 18
   ; 8
   ; 18
   ; 20
   ; 8 (* between top and middle rung *)
   ; 8
   ; 20
   ; 9
   ; 20
   ; 21
   ; 9 (* middle rung top *)
   ; 9
   ; 21
   ; 11
   ; 21
   ; 23
   ; 11 (* middle rung right *)
   ; 10
   ; 11
   ; 22
   ; 22
   ; 11
   ; 23 (* middle rung bottom *)
   ; 10
   ; 22
   ; 3
   ; 22
   ; 15
   ; 3 (* stem right *)
   ; 2
   ; 3
   ; 14
   ; 14
   ; 3
   ; 15 (* bottom *)
   ; 0
   ; 2
   ; 12
   ; 12
   ; 2
   ; 14 (* left *)
  |]
;;

(* Colors for each quad (16 quads, RGB values 0-255) *)
let quad_colors =
  [| (* front faces - reddish pink *)
     200
   ; 70
   ; 120 (* left column front *)
   ; 200
   ; 70
   ; 120 (* top rung front *)
   ; 200
   ; 70
   ; 120 (* middle rung front *)
   ; (* back faces - blueish purple *)
     80
   ; 70
   ; 200 (* left column back *)
   ; 80
   ; 70
   ; 200 (* top rung back *)
   ; 80
   ; 70
   ; 200 (* middle rung back *)
   ; (* connecting faces - various colors *)
     70
   ; 200
   ; 210 (* top *)
   ; 160
   ; 160
   ; 220 (* top rung right *)
   ; 90
   ; 130
   ; 110 (* top rung bottom *)
   ; 200
   ; 200
   ; 70 (* between top and middle rung *)
   ; 210
   ; 100
   ; 70 (* middle rung top *)
   ; 210
   ; 160
   ; 70 (* middle rung right *)
   ; 70
   ; 180
   ; 210 (* middle rung bottom *)
   ; 100
   ; 70
   ; 210 (* stem right *)
   ; 76
   ; 210
   ; 100 (* bottom *)
   ; 140
   ; 210
   ; 80 (* left *)
  |]
;;

(* Build vertex data: for each index, copy position and add color based on quad *)
let create_vertex_data () =
  let num_vertices = Array.length indices in
  (* Each vertex: 3 floats for position + 1 float (4 bytes as unorm8x4 for color) = 4 floats *)
  let vertex_data =
    Bigarray.Array1.create Bigarray.float32 Bigarray.c_layout (num_vertices * 4)
  in
  let color_data =
    Bigarray.Array1.create Bigarray.int8_unsigned Bigarray.c_layout (num_vertices * 16)
  in
  for i = 0 to num_vertices - 1 do
    let idx = indices.(i) in
    let pos_offset = idx * 3 in
    (* Copy position *)
    Bigarray.Array1.set vertex_data ((i * 4) + 0) positions.(pos_offset + 0);
    Bigarray.Array1.set vertex_data ((i * 4) + 1) positions.(pos_offset + 1);
    Bigarray.Array1.set vertex_data ((i * 4) + 2) positions.(pos_offset + 2);
    (* Set color based on quad (6 vertices per quad) *)
    let quad_idx = i / 6 in
    let color_offset = quad_idx * 3 in
    let r = quad_colors.(color_offset + 0) in
    let g = quad_colors.(color_offset + 1) in
    let b = quad_colors.(color_offset + 2) in
    Bigarray.Array1.set color_data ((i * 16) + 12) r;
    Bigarray.Array1.set color_data ((i * 16) + 13) g;
    Bigarray.Array1.set color_data ((i * 16) + 14) b;
    Bigarray.Array1.set color_data ((i * 16) + 15) 255
  done;
  (* Copy color bytes into vertex_data at the right positions *)
  for i = 0 to num_vertices - 1 do
    let r = Bigarray.Array1.get color_data ((i * 16) + 12) in
    let g = Bigarray.Array1.get color_data ((i * 16) + 13) in
    let b = Bigarray.Array1.get color_data ((i * 16) + 14) in
    let a = Bigarray.Array1.get color_data ((i * 16) + 15) in
    (* Pack RGBA as a single float (reinterpret 4 bytes as float32) *)
    let packed =
      Int32.bit_or
        (Int32.bit_or (Int32.of_int_exn r) (Int32.shift_left (Int32.of_int_exn g) 8))
        (Int32.bit_or
           (Int32.shift_left (Int32.of_int_exn b) 16)
           (Int32.shift_left (Int32.of_int_exn a) 24))
    in
    Bigarray.Array1.set vertex_data ((i * 4) + 3) (Int32.float_of_bits packed)
  done;
  vertex_data, num_vertices
;;

(* Orthographic projection matrix that converts pixel coordinates to clip space.
   This matrix flips Y so 0 is at the top. *)
let projection_matrix ~width ~height ~depth =
  (* Maps:
     x: [0, width] -> [-1, 1]
     y: [0, height] -> [1, -1] (flipped)
     z: [-depth/2, depth/2] -> [0, 1] *)
  Gg.M4.v
    (2.0 /. width)
    0.0
    0.0
    (-1.0)
    0.0
    (-2.0 /. height)
    0.0
    1.0
    0.0
    0.0
    (0.5 /. depth)
    0.5
    0.0
    0.0
    0.0
    1.0
;;

(* 3D transformation matrices *)
let translation_matrix ~tx ~ty ~tz =
  Gg.M4.v 1.0 0.0 0.0 tx 0.0 1.0 0.0 ty 0.0 0.0 1.0 tz 0.0 0.0 0.0 1.0
;;

let rotation_x_matrix angle =
  let c = Float.cos angle in
  let s = Float.sin angle in
  Gg.M4.v 1.0 0.0 0.0 0.0 0.0 c (-.s) 0.0 0.0 s c 0.0 0.0 0.0 0.0 1.0
;;

let rotation_y_matrix angle =
  let c = Float.cos angle in
  let s = Float.sin angle in
  Gg.M4.v c 0.0 s 0.0 0.0 1.0 0.0 0.0 (-.s) 0.0 c 0.0 0.0 0.0 0.0 1.0
;;

let rotation_z_matrix angle =
  let c = Float.cos angle in
  let s = Float.sin angle in
  Gg.M4.v c (-.s) 0.0 0.0 s c 0.0 0.0 0.0 0.0 1.0 0.0 0.0 0.0 0.0 1.0
;;

let scaling_matrix ~sx ~sy ~sz =
  Gg.M4.v sx 0.0 0.0 0.0 0.0 sy 0.0 0.0 0.0 0.0 sz 0.0 0.0 0.0 0.0 1.0
;;

(* Convert Gg.M4 matrix to bigarray in column-major order for WebGPU *)
let matrix_to_bigarray m =
  let data = Bigarray.Array1.create Bigarray.float32 Bigarray.c_layout 16 in
  for col = 0 to 3 do
    for row = 0 to 3 do
      let value = Gg.M4.el row col m in
      Bigarray.Array1.set data ((col * 4) + row) value
    done
  done;
  data
;;

(* Uniform buffer size: mat4x4f = 16 floats = 64 bytes *)
let uniform_buffer_size = 16 * 4

let init () =
  let instance = Wgpu.Instance.create () in
  let adapter = Wgpu.Instance.request_adapter instance () in
  let device = Wgpu.Adapter.request_device adapter in
  let queue = Wgpu.Device.get_queue device in
  let shader =
    Wgpu.Device.create_shader_module
      device
      ~label:"orthographic_3d_f_shader"
      ~wgsl:shader_code
      ()
  in
  instance, adapter, device, queue, shader
;;

let render
  ~device
  ~queue
  ~pipeline
  ~vertex_buffer
  ~vertex_buffer_size
  ~num_vertices
  ~uniform_buffer
  ~bind_group
  ~translation
  ~rotation
  ~scale
  ~output_name
  =
  let tx, ty, tz = translation in
  let rot_x, rot_y, rot_z = rotation in
  let sx, sy, sz = scale in
  (* Create render target texture *)
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
  let readback_buffer =
    Wgpu.Device.create_buffer
      device
      ~label:"readback_buffer"
      ~size:(Int64.of_int buffer_size)
      ~usage:[ Wgpu.Buffer_usage.Item.Map_read; Wgpu.Buffer_usage.Item.Copy_dst ]
      ~mapped_at_creation:false
      ()
  in
  (* Compute transformation matrix: projection * translate * rotateX * rotateY * rotateZ * scale *)
  let proj =
    projection_matrix
      ~width:(Float.of_int width)
      ~height:(Float.of_int height)
      ~depth:400.0
  in
  let translate = translation_matrix ~tx ~ty ~tz in
  let rotate_x = rotation_x_matrix rot_x in
  let rotate_y = rotation_y_matrix rot_y in
  let rotate_z = rotation_z_matrix rot_z in
  let scale_m = scaling_matrix ~sx ~sy ~sz in
  let matrix =
    Gg.M4.mul
      proj
      (Gg.M4.mul
         translate
         (Gg.M4.mul rotate_x (Gg.M4.mul rotate_y (Gg.M4.mul rotate_z scale_m))))
  in
  let uniform_data = matrix_to_bigarray matrix in
  Wgpu.Queue.write_buffer queue ~buffer:uniform_buffer ~offset:0L ~data:uniform_data;
  (* Render *)
  let encoder = Wgpu.Device.create_command_encoder device ~label:"render_encoder" () in
  let render_pass =
    Wgpu.Command_encoder.begin_render_pass
      encoder
      ~label:"orthographic_pass"
      ~color_attachments:
        [ Wgpu.Render_pass_color_attachment.create
            ~view:color_view
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
      ~depth_stencil_attachment:
        (Wgpu.Render_pass_depth_stencil_attachment.create
           ~view:depth_view
           ~depth_load_op:Wgpu.Load_op.Clear
           ~depth_store_op:Wgpu.Store_op.Store
           ~depth_clear_value:1.0
           ~depth_read_only:false
           ~stencil_load_op:Wgpu.Load_op.Clear
           ~stencil_store_op:Wgpu.Store_op.Store
           ~stencil_clear_value:0
           ~stencil_read_only:false
           ())
      ()
  in
  Wgpu.Render_pass_encoder.set_pipeline render_pass ~pipeline;
  Wgpu.Render_pass_encoder.set_vertex_buffer
    render_pass
    ~slot:0
    ~buffer:vertex_buffer
    ~offset:0L
    ~size:(Int64.of_int vertex_buffer_size);
  Wgpu.set_bind_group_render render_pass ~index:0 ~bind_group;
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
  Wgpu.Texture_view.release depth_view;
  Wgpu.Texture.release depth_texture;
  Wgpu.Texture_view.release color_view;
  Wgpu.Texture.release color_texture
;;

let () =
  let instance, adapter, device, queue, shader = init () in
  let vertex_data, num_vertices = create_vertex_data () in
  let vertex_buffer_size = num_vertices * 4 * 4 in
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
  Wgpu.Queue.write_buffer queue ~buffer:vertex_buffer ~offset:0L ~data:vertex_data;
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
      ~visibility:[ Wgpu.Shader_stage.Item.Vertex ]
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
      ~label:"orthographic_pipeline_layout"
      ~bind_group_layouts:[ bind_group_layout ]
      ()
  in
  (* Define vertex buffer layout: 3 floats position + 1 float (packed color) = 4 floats *)
  let vertex_buffer_layout =
    Wgpu.Vertex_buffer_layout.create
      ~step_mode:Wgpu.Vertex_step_mode.Vertex
      ~array_stride:(Int64.of_int (4 * 4))
      ~attributes:
        [ Wgpu.Vertex_attribute.create
            ~format:Wgpu.Vertex_format.Float32x3
            ~offset:0L
            ~shader_location:0
            ()
        ; Wgpu.Vertex_attribute.create
            ~format:Wgpu.Vertex_format.Unorm8x4
            ~offset:12L
            ~shader_location:1
            ()
        ]
      ()
  in
  (* Create render pipeline with depth testing and front-face culling *)
  let pipeline =
    Wgpu.Device.create_render_pipeline
      device
      ~label:"orthographic_pipeline"
      ~layout:pipeline_layout
      ~vertex_module:shader
      ~vertex_entry_point:"vs"
      ~vertex_buffers:[ vertex_buffer_layout ]
      ~primitive_topology:Wgpu.Primitive_topology.Triangle_list
      ~primitive_strip_index_format:Wgpu.Index_format.Undefined
      ~primitive_front_face:Wgpu.Front_face.Ccw
      ~primitive_cull_mode:Wgpu.Cull_mode.Front
      ~primitive_unclipped_depth:false
      ~depth_stencil:
        (Wgpu.Depth_stencil_state.create
           ~format:Wgpu.Texture_format.Depth24_plus
           ~depth_write_enabled:True
           ~depth_compare:Wgpu.Compare_function.Less
           ~stencil_front:
             (Wgpu.Depth_stencil_state.Stencil_face_state.create
                ~compare:Wgpu.Compare_function.Always
                ~fail_op:Wgpu.Stencil_operation.Keep
                ~depth_fail_op:Wgpu.Stencil_operation.Keep
                ~pass_op:Wgpu.Stencil_operation.Keep
                ())
           ~stencil_back:
             (Wgpu.Depth_stencil_state.Stencil_face_state.create
                ~compare:Wgpu.Compare_function.Always
                ~fail_op:Wgpu.Stencil_operation.Keep
                ~depth_fail_op:Wgpu.Stencil_operation.Keep
                ~pass_op:Wgpu.Stencil_operation.Keep
                ())
           ~stencil_read_mask:0xFFFFFFFF
           ~stencil_write_mask:0xFFFFFFFF
           ~depth_bias:0
           ~depth_bias_slope_scale:0.0
           ~depth_bias_clamp:0.0
           ())
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
  (* Render at different rotation angles to show 3D structure *)
  let deg_to_rad d = d *. Float.pi /. 180.0 in
  let frames =
    [ (* Default view from the lesson *)
      ( (45.0, 100.0, 0.0)
      , (deg_to_rad 40.0, deg_to_rad 25.0, deg_to_rad 325.0)
      , (1.0, 1.0, 1.0)
      , "orthographic_3d_f_default" )
    ; (* Front view *)
      (150.0, 100.0, 0.0), (0.0, 0.0, 0.0), (1.0, 1.0, 1.0), "orthographic_3d_f_front"
    ; (* Rotated view 1 *)
      ( (200.0, 150.0, 0.0)
      , (deg_to_rad 30.0, deg_to_rad 45.0, 0.0)
      , (1.0, 1.0, 1.0)
      , "orthographic_3d_f_rotated1" )
    ; (* Rotated view 2 - more rotation *)
      ( (250.0, 120.0, 0.0)
      , (deg_to_rad 60.0, deg_to_rad 90.0, deg_to_rad 15.0)
      , (1.0, 1.0, 1.0)
      , "orthographic_3d_f_rotated2" )
    ]
  in
  List.iter frames ~f:(fun (translation, rotation, scale, output_name) ->
    render
      ~device
      ~queue
      ~pipeline
      ~vertex_buffer
      ~vertex_buffer_size
      ~num_vertices
      ~uniform_buffer
      ~bind_group
      ~translation
      ~rotation
      ~scale
      ~output_name);
  (* Cleanup *)
  Wgpu.Render_pipeline.release pipeline;
  Wgpu.Pipeline_layout.release pipeline_layout;
  Wgpu.Bind_group.release bind_group;
  Wgpu.Bind_group_layout.release bind_group_layout;
  Wgpu.Buffer.release uniform_buffer;
  Wgpu.Buffer.release vertex_buffer;
  Wgpu.Shader_module.release shader;
  Wgpu.Queue.release queue;
  Wgpu.Device.release device;
  Wgpu.Adapter.release adapter;
  Wgpu.Instance.release instance
;;
