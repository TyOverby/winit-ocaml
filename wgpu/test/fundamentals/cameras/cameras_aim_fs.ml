(*
   WebGPU Fundamentals: Cameras - Step 4 (Aim Fs)

   This test demonstrates:
   - The aim function which orients an object to face a target (positive Z toward target)
   - A 5x5 grid of F shapes, each oriented to face a 26th "target" F
   - Unlike cameraAim (which has Z pointing away from target), aim points Z toward target

   This technique is useful for making characters look at things, turrets aim at targets,
   or objects follow paths while oriented along the path direction.
*)

open! Core

let width = 600
let height = 400
let bytes_per_pixel = 4
let bytes_per_row = ((width * bytes_per_pixel) + 255) / 256 * 256
let buffer_size = bytes_per_row * height

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

let f_positions =
  [| -50.0
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
   ; -20.0
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
   ; -20.0
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
   ; -50.0
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
   ; -20.0
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
   ; -20.0
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
   ; 1
   ; 4
   ; 6
   ; 5
   ; 6
   ; 7
   ; 5
   ; 8
   ; 10
   ; 9
   ; 10
   ; 11
   ; 9
   ; 12
   ; 13
   ; 14
   ; 14
   ; 13
   ; 15
   ; 16
   ; 17
   ; 18
   ; 18
   ; 17
   ; 19
   ; 20
   ; 21
   ; 22
   ; 22
   ; 21
   ; 23
   ; 0
   ; 5
   ; 12
   ; 12
   ; 5
   ; 17
   ; 5
   ; 7
   ; 17
   ; 17
   ; 7
   ; 19
   ; 6
   ; 18
   ; 7
   ; 18
   ; 19
   ; 7
   ; 6
   ; 8
   ; 18
   ; 18
   ; 8
   ; 20
   ; 8
   ; 9
   ; 20
   ; 20
   ; 9
   ; 21
   ; 9
   ; 11
   ; 21
   ; 21
   ; 11
   ; 23
   ; 10
   ; 22
   ; 11
   ; 22
   ; 23
   ; 11
   ; 10
   ; 3
   ; 22
   ; 22
   ; 3
   ; 15
   ; 2
   ; 14
   ; 3
   ; 14
   ; 15
   ; 3
   ; 0
   ; 12
   ; 2
   ; 12
   ; 14
   ; 2
  |]
;;

let quad_colors =
  [| 200
   ; 70
   ; 120
   ; 200
   ; 70
   ; 120
   ; 200
   ; 70
   ; 120
   ; 80
   ; 70
   ; 200
   ; 80
   ; 70
   ; 200
   ; 80
   ; 70
   ; 200
   ; 70
   ; 200
   ; 210
   ; 160
   ; 160
   ; 220
   ; 90
   ; 130
   ; 110
   ; 200
   ; 200
   ; 70
   ; 210
   ; 100
   ; 70
   ; 210
   ; 160
   ; 70
   ; 70
   ; 180
   ; 210
   ; 100
   ; 70
   ; 210
   ; 76
   ; 210
   ; 100
   ; 140
   ; 210
   ; 80
  |]
;;

let num_vertices = Array.length f_indices

let build_vertex_data () =
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
    let quad_idx = i / 6 * 3 in
    let cr = quad_colors.(quad_idx) in
    let cg = quad_colors.(quad_idx + 1) in
    let cb = quad_colors.(quad_idx + 2) in
    let base = i * vertex_size in
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
    Bigarray.Array1.set data (base + 12) cr;
    Bigarray.Array1.set data (base + 13) cg;
    Bigarray.Array1.set data (base + 14) cb;
    Bigarray.Array1.set data (base + 15) 255
  done;
  data
;;

let vertex_buffer_size = num_vertices * 16

(* 5x5 grid + 1 target F *)
let num_fs = (5 * 5) + 1
let uniform_buffer_size = 16 * 4
let radius = 200.0

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

(* Look-at view matrix *)
let look_at_matrix ~eye ~target ~up =
  let open Gg in
  let z = V3.unit (V3.sub eye target) in
  let x = V3.unit (V3.cross up z) in
  let y = V3.cross z x in
  let ex = -.V3.dot x eye in
  let ey = -.V3.dot y eye in
  let ez = -.V3.dot z eye in
  M4.v
    (V3.x x)
    (V3.y x)
    (V3.z x)
    ex
    (V3.x y)
    (V3.y y)
    (V3.z y)
    ey
    (V3.x z)
    (V3.y z)
    (V3.z z)
    ez
    0.0
    0.0
    0.0
    1.0
;;

(* Aim matrix - positions object at eye, oriented with positive Z toward target
   This is the opposite direction from cameraAim *)
let aim_matrix ~eye ~target ~up =
  let open Gg in
  (* Z points from eye toward target (positive Z forward) *)
  let z_axis = V3.unit (V3.sub target eye) in
  let x_axis = V3.unit (V3.cross up z_axis) in
  let y_axis = V3.cross z_axis x_axis in
  M4.v
    (V3.x x_axis)
    (V3.x y_axis)
    (V3.x z_axis)
    (V3.x eye)
    (V3.y x_axis)
    (V3.y y_axis)
    (V3.y z_axis)
    (V3.y eye)
    (V3.z x_axis)
    (V3.z y_axis)
    (V3.z z_axis)
    (V3.z eye)
    0.0
    0.0
    0.0
    1.0
;;

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
  let shader =
    Wgpu.Device.create_shader_module device ~label:"f_shader" ~wgsl:shader_code ()
  in
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
  let aspect = Float.of_int width /. Float.of_int height in
  let fov_y = 60.0 *. Float.pi /. 180.0 in
  let projection = perspective_matrix ~fov_y ~aspect ~z_near:1.0 ~z_far:2000.0 in
  (* Fixed camera position looking at center *)
  let eye = Gg.V3.v (-500.0) 300.0 (-500.0) in
  let camera_target = Gg.V3.v 0.0 (-100.0) 0.0 in
  let up = Gg.V3.v 0.0 1.0 0.0 in
  let view_matrix = look_at_matrix ~eye ~target:camera_target ~up in
  let view_projection = Gg.M4.mul projection view_matrix in
  let render_frame ~target_angle ~target_height ~output_name =
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
    (* Compute target position based on angle *)
    let target_x = Float.cos target_angle *. radius in
    let target_z = Float.sin target_angle *. radius in
    let target_pos = Gg.V3.v target_x target_height target_z in
    (* Update uniform buffers for each F *)
    List.iteri object_infos ~f:(fun i (uniform_buffer, _) ->
      let matrix =
        if i < 25
        then (
          (* Grid F: compute position and aim at target *)
          let across = 5 in
          let deep = 5 in
          let grid_x = i mod across in
          let grid_z = i / across in
          let u = Float.of_int grid_x /. Float.of_int (across - 1) in
          let v = Float.of_int grid_z /. Float.of_int (deep - 1) in
          let x = (u -. 0.5) *. Float.of_int across *. 150.0 in
          let z = (v -. 0.5) *. Float.of_int deep *. 150.0 in
          let f_pos = Gg.V3.v x 0.0 z in
          let aim = aim_matrix ~eye:f_pos ~target:target_pos ~up in
          Gg.M4.mul view_projection aim)
        else (
          (* Target F: just translate to target position *)
          let translate = Gg.M4.move3 target_pos in
          Gg.M4.mul view_projection translate)
      in
      let matrix_data = matrix_to_bigarray matrix in
      Wgpu.Queue.write_buffer queue ~buffer:uniform_buffer ~offset:0L ~data:matrix_data);
    let readback_buffer =
      Wgpu.Device.create_buffer
        device
        ~label:"readback_buffer"
        ~size:(Int64.of_int buffer_size)
        ~usage:[ Wgpu.Buffer_usage.Item.Map_read; Wgpu.Buffer_usage.Item.Copy_dst ]
        ~mapped_at_creation:false
        ()
    in
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
    List.iter object_infos ~f:(fun (_, bind_group) ->
      Wgpu.set_bind_group_render render_pass ~index:0 ~bind_group;
      Wgpu.Render_pass_encoder.draw
        render_pass
        ~vertex_count:num_vertices
        ~instance_count:1
        ~first_vertex:0
        ~first_instance:0);
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
    Wgpu.Command_buffer.release command_buffer;
    Wgpu.Render_pass_encoder.release render_pass;
    Wgpu.Command_encoder.release encoder;
    Wgpu.Buffer.release readback_buffer;
    Wgpu.Texture_view.release depth_view;
    Wgpu.Texture.release depth_texture;
    Wgpu.Texture_view.release color_view;
    Wgpu.Texture.release color_texture
  in
  (* Render at different target positions *)
  render_frame ~target_angle:0.0 ~target_height:200.0 ~output_name:"cameras_aim_fs_center";
  render_frame
    ~target_angle:(Float.pi /. 4.0)
    ~target_height:100.0
    ~output_name:"cameras_aim_fs_corner";
  render_frame
    ~target_angle:(Float.pi /. 2.0)
    ~target_height:0.0
    ~output_name:"cameras_aim_fs_side";
  render_frame
    ~target_angle:Float.pi
    ~target_height:(-50.0)
    ~output_name:"cameras_aim_fs_back";
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
