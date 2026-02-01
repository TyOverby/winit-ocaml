(*
   WebGPU Fundamentals: Orthographic Projection - Ortho Matrix

   This test demonstrates the standard orthographic projection matrix
   (ortho function) which provides more flexibility than the simple
   projection function. The ortho function takes left, right, bottom,
   top, near, and far parameters.

   ortho(left, right, bottom, top, near, far)

   This is the standard way to set up orthographic projection in 3D
   graphics libraries. We demonstrate it by rendering the same 3D F
   shape as in orthographic_3d_f but using the standard ortho matrix.

   The ortho matrix maps:
   - x: [left, right] -> [-1, 1]
   - y: [bottom, top] -> [-1, 1]
   - z: [near, far] -> [0, 1] (WebGPU depth range)
*)

open! Core

let width = 600
let height = 400
let bytes_per_pixel = 4
let bytes_per_row = ((width * bytes_per_pixel) + 255) / 256 * 256
let buffer_size = bytes_per_row * height

(* Same shader as orthographic_3d_f *)
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

(* Same 3D F vertex data as orthographic_3d_f *)
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

let indices =
  [| (* front faces *)
     0
   ; 1
   ; 2
   ; 2
   ; 1
   ; 3
   ; 4
   ; 5
   ; 6
   ; 6
   ; 5
   ; 7
   ; 8
   ; 9
   ; 10
   ; 10
   ; 9
   ; 11
   ; (* back faces *)
     12
   ; 14
   ; 13
   ; 14
   ; 15
   ; 13
   ; 16
   ; 18
   ; 17
   ; 18
   ; 19
   ; 17
   ; 20
   ; 22
   ; 21
   ; 22
   ; 23
   ; 21
   ; (* connecting faces *)
     0
   ; 12
   ; 5
   ; 12
   ; 17
   ; 5
   ; 5
   ; 17
   ; 7
   ; 17
   ; 19
   ; 7
   ; 6
   ; 7
   ; 18
   ; 18
   ; 7
   ; 19
   ; 6
   ; 18
   ; 8
   ; 18
   ; 20
   ; 8
   ; 8
   ; 20
   ; 9
   ; 20
   ; 21
   ; 9
   ; 9
   ; 21
   ; 11
   ; 21
   ; 23
   ; 11
   ; 10
   ; 11
   ; 22
   ; 22
   ; 11
   ; 23
   ; 10
   ; 22
   ; 3
   ; 22
   ; 15
   ; 3
   ; 2
   ; 3
   ; 14
   ; 14
   ; 3
   ; 15
   ; 0
   ; 2
   ; 12
   ; 12
   ; 2
   ; 14
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

let create_vertex_data () =
  let num_vertices = Array.length indices in
  let vertex_data =
    Bigarray.Array1.create Bigarray.float32 Bigarray.c_layout (num_vertices * 4)
  in
  let color_data =
    Bigarray.Array1.create Bigarray.int8_unsigned Bigarray.c_layout (num_vertices * 16)
  in
  for i = 0 to num_vertices - 1 do
    let idx = indices.(i) in
    let pos_offset = idx * 3 in
    Bigarray.Array1.set vertex_data ((i * 4) + 0) positions.(pos_offset + 0);
    Bigarray.Array1.set vertex_data ((i * 4) + 1) positions.(pos_offset + 1);
    Bigarray.Array1.set vertex_data ((i * 4) + 2) positions.(pos_offset + 2);
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
  for i = 0 to num_vertices - 1 do
    let r = Bigarray.Array1.get color_data ((i * 16) + 12) in
    let g = Bigarray.Array1.get color_data ((i * 16) + 13) in
    let b = Bigarray.Array1.get color_data ((i * 16) + 14) in
    let a = Bigarray.Array1.get color_data ((i * 16) + 15) in
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

(* Standard orthographic projection matrix
   Maps [left,right] x [bottom,top] x [near,far] to [-1,1] x [-1,1] x [0,1] *)
let ortho_matrix ~left ~right ~bottom ~top ~near ~far =
  let width = right -. left in
  let height = top -. bottom in
  let depth = near -. far in
  Gg.M4.v
    (2.0 /. width)
    0.0
    0.0
    ((right +. left) /. (left -. right))
    0.0
    (2.0 /. height)
    0.0
    ((top +. bottom) /. (bottom -. top))
    0.0
    0.0
    (1.0 /. depth)
    (near /. depth)
    0.0
    0.0
    0.0
    1.0
;;

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

let uniform_buffer_size = 16 * 4

let init () =
  let instance = Wgpu.Instance.create () in
  let adapter = Wgpu.Instance.request_adapter instance () in
  let device = Wgpu.Adapter.request_device adapter in
  let queue = Wgpu.Device.get_queue device in
  let shader =
    Wgpu.Device.create_shader_module device ~label:"ortho_shader" ~wgsl:shader_code ()
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
  let readback_buffer =
    Wgpu.Device.create_buffer
      device
      ~label:"readback_buffer"
      ~size:(Int64.of_int buffer_size)
      ~usage:[ Wgpu.Buffer_usage.Item.Map_read; Wgpu.Buffer_usage.Item.Copy_dst ]
      ~mapped_at_creation:false
      ()
  in
  (* Use the standard ortho matrix
     ortho(left=0, right=width, bottom=height, top=0, near=400, far=-400)
     Note: bottom > top flips Y, and near > far for the depth range we want *)
  let proj =
    ortho_matrix
      ~left:0.0
      ~right:(Float.of_int width)
      ~bottom:(Float.of_int height)
      ~top:0.0
      ~near:400.0
      ~far:(-400.0)
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
  let encoder = Wgpu.Device.create_command_encoder device ~label:"render_encoder" () in
  let render_pass =
    Wgpu.Command_encoder.begin_render_pass
      encoder
      ~label:"ortho_pass"
      ~color_attachments:
        [ { view = Some color_view
          ; depth_slice = 0xFFFFFFFF
          ; resolve_target = None
          ; load_op = Wgpu.Load_op.Clear
          ; store_op = Wgpu.Store_op.Store
          ; clear_value = Some { r = 0.3; g = 0.3; b = 0.3; a = 1.0 }
          }
        ]
      ~depth_stencil_attachment:
        { view = depth_view
        ; depth_load_op = Wgpu.Load_op.Clear
        ; depth_store_op = Wgpu.Store_op.Store
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
  let uniform_buffer =
    Wgpu.Device.create_buffer
      device
      ~label:"uniform_buffer"
      ~size:(Int64.of_int uniform_buffer_size)
      ~usage:[ Wgpu.Buffer_usage.Item.Uniform; Wgpu.Buffer_usage.Item.Copy_dst ]
      ~mapped_at_creation:false
      ()
  in
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
        [ { Wgpu.Bind_group_entry.binding = 0
          ; buffer = Some uniform_buffer
          ; offset = 0L
          ; size = Int64.of_int uniform_buffer_size
          ; sampler = None
          ; texture_view = None
          }
        ]
      ()
  in
  let pipeline_layout =
    Wgpu.Device.create_pipeline_layout
      device
      ~label:"ortho_pipeline_layout"
      ~bind_group_layouts:[ bind_group_layout ]
      ()
  in
  let vertex_buffer_layout =
    { Wgpu.Vertex_buffer_layout.step_mode = Wgpu.Vertex_step_mode.Vertex
    ; array_stride = Int64.of_int (4 * 4)
    ; attributes =
        [ { Wgpu.Vertex_attribute.format = Wgpu.Vertex_format.Float32x3
          ; offset = 0L
          ; shader_location = 0
          }
        ; { Wgpu.Vertex_attribute.format = Wgpu.Vertex_format.Unorm8x4
          ; offset = 12L
          ; shader_location = 1
          }
        ]
    }
  in
  let pipeline =
    Wgpu.Device.create_render_pipeline
      device
      ~label:"ortho_pipeline"
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
        ; entry_point = "fs"
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
  let deg_to_rad d = d *. Float.pi /. 180.0 in
  (* Render same frames as orthographic_3d_f to show ortho produces equivalent results *)
  let frames =
    [ ( (45.0, 100.0, 0.0)
      , (deg_to_rad 40.0, deg_to_rad 25.0, deg_to_rad 325.0)
      , (1.0, 1.0, 1.0)
      , "orthographic_ortho_default" )
    ; (150.0, 100.0, 0.0), (0.0, 0.0, 0.0), (1.0, 1.0, 1.0), "orthographic_ortho_front"
    ; ( (200.0, 150.0, 0.0)
      , (deg_to_rad 30.0, deg_to_rad 45.0, 0.0)
      , (1.0, 1.0, 1.0)
      , "orthographic_ortho_rotated1" )
    ; ( (250.0, 120.0, 0.0)
      , (deg_to_rad 60.0, deg_to_rad 90.0, deg_to_rad 15.0)
      , (1.0, 1.0, 1.0)
      , "orthographic_ortho_rotated2" )
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
