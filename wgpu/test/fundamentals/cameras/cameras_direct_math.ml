(*
   WebGPU Fundamentals: Cameras - Step 1 (Direct Math)

   This test demonstrates:
   - A circle of 5 F shapes rendered with perspective projection
   - A camera that orbits around the circle using rotation and translation
   - Depth testing to properly occlude overlapping geometry

   The camera position is computed by rotating around the Y axis and translating
   along the Z axis. The inverse of this camera matrix becomes the view matrix.
*)

open! Core

let width = 600
let height = 400
let bytes_per_pixel = 4
let bytes_per_row = ((width * bytes_per_pixel) + 255) / 256 * 256
let buffer_size = bytes_per_row * height

(* Shader code - transforms vertices by a matrix and passes through vertex colors *)
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

(* F vertex positions - centered around origin, positive Y up *)
let f_positions =
  [| (* left column *)
     -50.0
   ; 75.0
   ; 15.0
   ; -20.0
   ; 75.0
   ; 15.0
   ; -50.0
   ; -75.0
   ; 15.0
   ; -20.0
   ; -75.0
   ; 15.0
   ; (* top rung *)
     -20.0
   ; 75.0
   ; 15.0
   ; 50.0
   ; 75.0
   ; 15.0
   ; -20.0
   ; 45.0
   ; 15.0
   ; 50.0
   ; 45.0
   ; 15.0
   ; (* middle rung *)
     -20.0
   ; 15.0
   ; 15.0
   ; 20.0
   ; 15.0
   ; 15.0
   ; -20.0
   ; -15.0
   ; 15.0
   ; 20.0
   ; -15.0
   ; 15.0
   ; (* left column back *)
     -50.0
   ; 75.0
   ; -15.0
   ; -20.0
   ; 75.0
   ; -15.0
   ; -50.0
   ; -75.0
   ; -15.0
   ; -20.0
   ; -75.0
   ; -15.0
   ; (* top rung back *)
     -20.0
   ; 75.0
   ; -15.0
   ; 50.0
   ; 75.0
   ; -15.0
   ; -20.0
   ; 45.0
   ; -15.0
   ; 50.0
   ; 45.0
   ; -15.0
   ; (* middle rung back *)
     -20.0
   ; 15.0
   ; -15.0
   ; 20.0
   ; 15.0
   ; -15.0
   ; -20.0
   ; -15.0
   ; -15.0
   ; 20.0
   ; -15.0
   ; -15.0
  |]
;;

let f_indices =
  [| 0
   ; 2
   ; 1
   ; 2
   ; 3
   ; 1 (* left column *)
   ; 4
   ; 6
   ; 5
   ; 6
   ; 7
   ; 5 (* top rung *)
   ; 8
   ; 10
   ; 9
   ; 10
   ; 11
   ; 9 (* middle rung *)
   ; 12
   ; 13
   ; 14
   ; 14
   ; 13
   ; 15 (* left column back *)
   ; 16
   ; 17
   ; 18
   ; 18
   ; 17
   ; 19 (* top rung back *)
   ; 20
   ; 21
   ; 22
   ; 22
   ; 21
   ; 23 (* middle rung back *)
   ; 0
   ; 5
   ; 12
   ; 12
   ; 5
   ; 17 (* top *)
   ; 5
   ; 7
   ; 17
   ; 17
   ; 7
   ; 19 (* top rung right *)
   ; 6
   ; 18
   ; 7
   ; 18
   ; 19
   ; 7 (* top rung bottom *)
   ; 6
   ; 8
   ; 18
   ; 18
   ; 8
   ; 20 (* between top and middle rung *)
   ; 8
   ; 9
   ; 20
   ; 20
   ; 9
   ; 21 (* middle rung top *)
   ; 9
   ; 11
   ; 21
   ; 21
   ; 11
   ; 23 (* middle rung right *)
   ; 10
   ; 22
   ; 11
   ; 22
   ; 23
   ; 11 (* middle rung bottom *)
   ; 10
   ; 3
   ; 22
   ; 22
   ; 3
   ; 15 (* stem right *)
   ; 2
   ; 14
   ; 3
   ; 14
   ; 15
   ; 3 (* bottom *)
   ; 0
   ; 12
   ; 2
   ; 12
   ; 14
   ; 2 (* left *)
  |]
;;

(* Colors for each quad (6 vertices per quad, 16 quads) *)
let quad_colors =
  [| 200
   ; 70
   ; 120 (* left column front *)
   ; 200
   ; 70
   ; 120 (* top rung front *)
   ; 200
   ; 70
   ; 120 (* middle rung front *)
   ; 80
   ; 70
   ; 200 (* left column back *)
   ; 80
   ; 70
   ; 200 (* top rung back *)
   ; 80
   ; 70
   ; 200 (* middle rung back *)
   ; 70
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

let num_vertices = Array.length f_indices

(* Build interleaved vertex data: 3 floats position + 4 bytes color (as unorm8x4) *)
let build_vertex_data () =
  (* Each vertex: float32x3 (12 bytes) + unorm8x4 (4 bytes) = 16 bytes *)
  let vertex_size = 16 in
  let data =
    Bigarray.Array1.create
      Bigarray.int8_unsigned
      Bigarray.c_layout
      (num_vertices * vertex_size)
  in
  for i = 0 to num_vertices - 1 do
    let pos_idx = f_indices.(i) * 3 in
    let px = f_positions.(pos_idx) in
    let py = f_positions.(pos_idx + 1) in
    let pz = f_positions.(pos_idx + 2) in
    (* Get color for this quad (each quad has 6 vertices) *)
    let quad_idx = i / 6 * 3 in
    let cr = quad_colors.(quad_idx) in
    let cg = quad_colors.(quad_idx + 1) in
    let cb = quad_colors.(quad_idx + 2) in
    let base = i * vertex_size in
    (* Write position as float32 (little endian) *)
    let write_float offset value =
      let bits = Int32.bits_of_float value in
      Bigarray.Array1.set
        data
        (base + offset)
        (Int32.to_int_exn (Int32.bit_and bits 0xFFl));
      Bigarray.Array1.set
        data
        (base + offset + 1)
        (Int32.to_int_exn (Int32.bit_and (Int32.shift_right_logical bits 8) 0xFFl));
      Bigarray.Array1.set
        data
        (base + offset + 2)
        (Int32.to_int_exn (Int32.bit_and (Int32.shift_right_logical bits 16) 0xFFl));
      Bigarray.Array1.set
        data
        (base + offset + 3)
        (Int32.to_int_exn (Int32.bit_and (Int32.shift_right_logical bits 24) 0xFFl))
    in
    write_float 0 px;
    write_float 4 py;
    write_float 8 pz;
    (* Write color as unorm8x4 *)
    Bigarray.Array1.set data (base + 12) cr;
    Bigarray.Array1.set data (base + 13) cg;
    Bigarray.Array1.set data (base + 14) cb;
    Bigarray.Array1.set data (base + 15) 255
  done;
  data
;;

let vertex_buffer_size = num_vertices * 16

(* Number of F shapes and uniform buffer configuration *)
let num_fs = 5
let uniform_buffer_size = 16 * 4 (* mat4x4f *)
let radius = 200.0

(* Perspective projection matrix *)
let perspective_matrix ~fov_y ~aspect ~z_near ~z_far =
  let f = 1.0 /. Float.tan (fov_y /. 2.0) in
  let nf = 1.0 /. (z_near -. z_far) in
  Gg.M4.v
    (f /. aspect)
    0.0
    0.0
    0.0
    0.0
    f
    0.0
    0.0
    0.0
    0.0
    ((z_far +. z_near) *. nf)
    (2.0 *. z_far *. z_near *. nf)
    0.0
    0.0
    (-1.0)
    0.0
;;

(* Convert matrix to bigarray for GPU upload (transpose for column-major) *)
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

let init () =
  let instance = Wgpu.Instance.create () in
  let adapter = Wgpu.Instance.request_adapter instance () in
  let device = Wgpu.Adapter.request_device adapter in
  let queue = Wgpu.Device.get_queue device in
  instance, adapter, device, queue
;;

let () =
  let instance, adapter, device, queue = init () in
  (* Create shader *)
  let shader =
    Wgpu.Device.create_shader_module device ~label:"f_shader" ~wgsl:shader_code ()
  in
  (* Create vertex buffer *)
  let vertex_data = build_vertex_data () in
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
  (* Create bind group layout for uniform buffer *)
  let bind_group_layout =
    Wgpu.Device.create_bind_group_layout
      device
      ~label:"bind_group_layout"
      ~entries:
        [ Wgpu.Bind_group_layout_entry.create
            ~binding:0
            ~visibility:[ Wgpu.Shader_stage.Item.Vertex ]
            ~buffer:
              (Wgpu.Bind_group_layout_entry.Buffer_binding_layout.create
                 ~type_:Wgpu.Buffer_binding_type.Uniform
                 ~has_dynamic_offset:false
                 ~min_binding_size:0L
                 ())
            ()
        ]
      ()
  in
  let pipeline_layout =
    Wgpu.Device.create_pipeline_layout
      device
      ~label:"pipeline_layout"
      ~bind_group_layouts:[ bind_group_layout ]
      ()
  in
  (* Vertex buffer layout: position (float32x3) + color (unorm8x4) *)
  let vertex_buffer_layout =
    Wgpu.Vertex_buffer_layout.create
      ~step_mode:Wgpu.Vertex_step_mode.Vertex
      ~array_stride:16L
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
  (* Create render pipeline with depth testing and back-face culling *)
  let pipeline =
    Wgpu.Device.create_render_pipeline
      device
      ~label:"f_pipeline"
      ~layout:pipeline_layout
      ~vertex_module:shader
      ~vertex_entry_point:"vs"
      ~vertex_buffers:[ vertex_buffer_layout ]
      ~primitive_topology:Wgpu.Primitive_topology.Triangle_list
      ~primitive_strip_index_format:Wgpu.Index_format.Undefined
      ~primitive_front_face:Wgpu.Front_face.Ccw
      ~primitive_cull_mode:Wgpu.Cull_mode.Back
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
  (* Create uniform buffers and bind groups for each F *)
  let object_infos =
    List.init num_fs ~f:(fun _ ->
      let uniform_buffer =
        Wgpu.Device.create_buffer
          device
          ~label:"uniform_buffer"
          ~size:(Int64.of_int uniform_buffer_size)
          ~usage:[ Wgpu.Buffer_usage.Item.Uniform; Wgpu.Buffer_usage.Item.Copy_dst ]
          ~mapped_at_creation:false
          ()
      in
      let bind_group =
        Wgpu.Device.create_bind_group
          device
          ~label:"bind_group"
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
      uniform_buffer, bind_group)
  in
  (* Render at different camera angles *)
  let aspect = Float.of_int width /. Float.of_int height in
  let fov_y = 100.0 *. Float.pi /. 180.0 in
  let projection = perspective_matrix ~fov_y ~aspect ~z_near:1.0 ~z_far:2000.0 in
  let render_frame ~camera_angle ~output_name =
    (* Create render target *)
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
    (* Compute camera matrix: rotate around Y, then translate along Z *)
    let camera_matrix =
      let rot_y = Gg.M4.rot3_axis Gg.V3.oy camera_angle in
      let translate = Gg.M4.move3 (Gg.V3.v 0.0 0.0 (radius *. 1.5)) in
      Gg.M4.mul rot_y translate
    in
    (* View matrix is the inverse of the camera matrix *)
    let view_matrix = Gg.M4.inv camera_matrix in
    (* Combine projection and view *)
    let view_projection = Gg.M4.mul projection view_matrix in
    (* Update uniform buffers for each F *)
    List.iteri object_infos ~f:(fun i (uniform_buffer, _) ->
      let angle = Float.of_int i /. Float.of_int num_fs *. Float.pi *. 2.0 in
      let x = Float.cos angle *. radius in
      let z = Float.sin angle *. radius in
      let translate = Gg.M4.move3 (Gg.V3.v x 0.0 z) in
      let matrix = Gg.M4.mul view_projection translate in
      let matrix_data = matrix_to_bigarray matrix in
      Wgpu.Queue.write_buffer queue ~buffer:uniform_buffer ~offset:0L ~data:matrix_data);
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
    (* Render *)
    let encoder = Wgpu.Device.create_command_encoder device ~label:"render_encoder" () in
    let render_pass =
      Wgpu.Command_encoder.begin_render_pass
        encoder
        ~label:"render_pass"
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
    (* Draw each F *)
    List.iter object_infos ~f:(fun (_, bind_group) ->
      Wgpu.set_bind_group_render render_pass ~index:0 ~bind_group;
      Wgpu.Render_pass_encoder.draw
        render_pass
        ~vertex_count:num_vertices
        ~instance_count:1
        ~first_vertex:0
        ~first_instance:0);
    Wgpu.Render_pass_encoder.end_ render_pass;
    (* Copy to readback buffer *)
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
    (* Read back and save *)
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
      Test_util.write_ppm
        ~filename:ppm_file
        ~width
        ~height
        ~data:mapped_data
        ~bytes_per_row;
      Test_util.ppm_to_png ~ppm_file ~png_file;
      ()
    in
    Wgpu.Buffer.unmap readback_buffer;
    (* Cleanup frame resources *)
    Wgpu.Command_buffer.release command_buffer;
    Wgpu.Render_pass_encoder.release render_pass;
    Wgpu.Command_encoder.release encoder;
    Wgpu.Buffer.release readback_buffer;
    Wgpu.Texture_view.release depth_view;
    Wgpu.Texture.release depth_texture;
    Wgpu.Texture_view.release color_view;
    Wgpu.Texture.release color_texture
  in
  (* Render at different camera angles *)
  render_frame ~camera_angle:0.0 ~output_name:"cameras_direct_math_0deg";
  render_frame ~camera_angle:(Float.pi /. 4.0) ~output_name:"cameras_direct_math_45deg";
  render_frame ~camera_angle:(Float.pi /. 2.0) ~output_name:"cameras_direct_math_90deg";
  render_frame ~camera_angle:Float.pi ~output_name:"cameras_direct_math_180deg";
  (* Cleanup *)
  List.iter object_infos ~f:(fun (uniform_buffer, bind_group) ->
    Wgpu.Bind_group.release bind_group;
    Wgpu.Buffer.release uniform_buffer);
  Wgpu.Render_pipeline.release pipeline;
  Wgpu.Pipeline_layout.release pipeline_layout;
  Wgpu.Bind_group_layout.release bind_group_layout;
  Wgpu.Buffer.release vertex_buffer;
  Wgpu.Shader_module.release shader;
  Wgpu.Queue.release queue;
  Wgpu.Device.release device;
  Wgpu.Adapter.release adapter;
  Wgpu.Instance.release instance
;;
