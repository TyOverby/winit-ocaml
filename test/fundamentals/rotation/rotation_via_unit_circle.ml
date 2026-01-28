(*
   WebGPU Fundamentals: Rotation via Unit Circle

   This test demonstrates the relationship between the unit circle
   and rotation. Instead of thinking in terms of angles (degrees),
   we think in terms of points on the unit circle.

   A point (x, y) on the unit circle satisfies x^2 + y^2 = 1.
   For any angle theta:
   - x = cos(theta)
   - y = sin(theta)

   The rotation formula uses these x and y values directly:
   - rotatedX = position.x * x - position.y * y
   - rotatedY = position.x * y + position.y * x

   Based on: webgpufundamentals.org rotation lesson (rotation-via-unit-circle.js)

   This version renders frames at notable points on the unit circle
   to illustrate the concept:
   - (1, 0): 0 degrees / 3 o'clock position
   - (0.707, 0.707): 45 degrees
   - (0, 1): 90 degrees / 12 o'clock position
   - (-1, 0): 180 degrees / 9 o'clock position
*)

open! Core

let width = 600
let height = 400
let bytes_per_pixel = 4
let bytes_per_row = ((width * bytes_per_pixel) + 255) / 256 * 256
let buffer_size = bytes_per_row * height

(* The F shape vertices *)
let f_vertices =
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
;;

let f_indices = [| 0; 1; 2; 2; 1; 3; 4; 5; 6; 6; 5; 7; 8; 9; 10; 10; 9; 11 |]
let num_indices = Array.length f_indices
let uniform_buffer_size = 48

let shader_code =
  {|
struct Uniforms {
  color: vec4f,
  resolution: vec2f,
  translation: vec2f,
  rotation: vec2f,  // (cos, sin) - point on unit circle
};

@group(0) @binding(0) var<uniform> uni: Uniforms;
@group(0) @binding(1) var<storage, read> vertices: array<vec2f>;

struct VSOutput {
  @builtin(position) position: vec4f,
};

@vertex fn vs_main(@builtin(vertex_index) vertex_index: u32) -> VSOutput {
  var vsOut: VSOutput;

  let position = vertices[vertex_index];

  // Rotation matrix applied via unit circle point:
  // | cos  -sin |   | x |   | x*cos - y*sin |
  // | sin   cos | * | y | = | x*sin + y*cos |
  let rotatedPosition = vec2f(
    position.x * uni.rotation.x - position.y * uni.rotation.y,
    position.x * uni.rotation.y + position.y * uni.rotation.x
  );

  let translated = rotatedPosition + uni.translation;

  // Pixel space to clip space
  let zeroToOne = translated / uni.resolution;
  let zeroToTwo = zeroToOne * 2.0;
  let flippedClipSpace = zeroToTwo - 1.0;
  let clipSpace = flippedClipSpace * vec2f(1, -1);

  vsOut.position = vec4f(clipSpace, 0.0, 1.0);
  return vsOut;
}

@fragment fn fs_main(vsOut: VSOutput) -> @location(0) vec4f {
  return uni.color;
}
|}
;;

let init () =
  let instance = Wgpu.Instance.create () in
  let adapter = Wgpu.Instance.request_adapter instance () in
  let device = Wgpu.Adapter.request_device adapter in
  let queue = Wgpu.Device.get_queue device in
  instance, adapter, device, queue
;;

let create_f_vertex_buffer device queue =
  let vertex_data =
    Bigarray.Array1.create Bigarray.float32 Bigarray.c_layout (Array.length f_vertices)
  in
  Array.iteri f_vertices ~f:(fun i v -> Bigarray.Array1.set vertex_data i v);
  let vertex_buffer =
    Wgpu.Device.create_buffer
      device
      ~label:"f_vertex_storage"
      ~size:(Int64.of_int (Array.length f_vertices * 4))
      ~usage:[ Wgpu.Buffer_usage.Item.Storage; Wgpu.Buffer_usage.Item.Copy_dst ]
      ~mapped_at_creation:false
      ()
  in
  Wgpu.Queue.write_buffer queue ~buffer:vertex_buffer ~offset:0L ~data:vertex_data;
  vertex_buffer
;;

let create_index_buffer device queue =
  let index_data =
    Bigarray.Array1.create Bigarray.int32 Bigarray.c_layout (Array.length f_indices)
  in
  Array.iteri f_indices ~f:(fun i v ->
    Bigarray.Array1.set index_data i (Int32.of_int_exn v));
  let index_buffer =
    Wgpu.Device.create_buffer
      device
      ~label:"f_index_buffer"
      ~size:(Int64.of_int (Array.length f_indices * 4))
      ~usage:[ Wgpu.Buffer_usage.Item.Index; Wgpu.Buffer_usage.Item.Copy_dst ]
      ~mapped_at_creation:false
      ()
  in
  Wgpu.Queue.write_buffer queue ~buffer:index_buffer ~offset:0L ~data:index_data;
  index_buffer
;;

let render_frame
  ~device
  ~queue
  ~pipeline
  ~bind_group
  ~uniform_buffer
  ~index_buffer
  ~texture
  ~texture_view
  ~readback_buffer
  ~translation_x
  ~translation_y
  ~rotation_cos
  ~rotation_sin
  ~color_r
  ~color_g
  ~color_b
  ~output_name
  =
  (* Update uniform buffer with unit circle point directly *)
  let uniform_data = Bigarray.Array1.create Bigarray.float32 Bigarray.c_layout 12 in
  (* color (vec4f) *)
  Bigarray.Array1.set uniform_data 0 color_r;
  Bigarray.Array1.set uniform_data 1 color_g;
  Bigarray.Array1.set uniform_data 2 color_b;
  Bigarray.Array1.set uniform_data 3 1.0;
  (* resolution (vec2f) *)
  Bigarray.Array1.set uniform_data 4 (Float.of_int width);
  Bigarray.Array1.set uniform_data 5 (Float.of_int height);
  (* translation (vec2f) *)
  Bigarray.Array1.set uniform_data 6 translation_x;
  Bigarray.Array1.set uniform_data 7 translation_y;
  (* rotation (vec2f): directly use unit circle point (cos, sin) *)
  Bigarray.Array1.set uniform_data 8 rotation_cos;
  Bigarray.Array1.set uniform_data 9 rotation_sin;
  (* padding *)
  Bigarray.Array1.set uniform_data 10 0.0;
  Bigarray.Array1.set uniform_data 11 0.0;
  Wgpu.Queue.write_buffer queue ~buffer:uniform_buffer ~offset:0L ~data:uniform_data;
  (* Render *)
  let encoder = Wgpu.Device.create_command_encoder device ~label:"rotation_encoder" () in
  let render_pass =
    Wgpu.begin_render_pass
      encoder
      ~label:"rotation_pass"
      ~color_view:texture_view
      ~clear_color:(0.3, 0.3, 0.3, 1.0)
      ()
  in
  Wgpu.Render_pass_encoder.set_pipeline render_pass ~pipeline;
  Wgpu.set_bind_group_render render_pass ~index:0 ~bind_group;
  Wgpu.Render_pass_encoder.set_index_buffer
    render_pass
    ~buffer:index_buffer
    ~format:Wgpu.Index_format.Uint32
    ~offset:0L
    ~size:(Int64.of_int (num_indices * 4));
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
  let command_buffer = Wgpu.finish encoder ~label:"rotation_commands" () in
  Wgpu.Queue.submit queue ~commands:[ command_buffer ];
  Wgpu.Device.poll device ~wait:true ();
  (* Read back and save image *)
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
  Wgpu.Command_encoder.release encoder
;;

let () =
  let instance, adapter, device, queue = init () in
  let shader =
    Wgpu.Device.create_shader_module device ~label:"rotation_shader" ~wgsl:shader_code ()
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
  let vertex_buffer = create_f_vertex_buffer device queue in
  let index_buffer = create_index_buffer device queue in
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
    Wgpu.Device.create_bind_group_layout
      device
      ~label:"rotation_bind_group_layout"
      ~entries:
        [ { Wgpu.Bind_group_layout_entry.binding = 0
          ; visibility =
              [ Wgpu.Shader_stage.Item.Vertex; Wgpu.Shader_stage.Item.Fragment ]
          ; buffer =
              Some
                { Wgpu.Bind_group_layout_entry.Buffer_binding_layout.type_ =
                    Wgpu.Buffer_binding_type.Uniform
                ; has_dynamic_offset = false
                ; min_binding_size = 0L
                }
          ; sampler = None
          ; texture = None
          ; storage_texture = None
          }
        ; { Wgpu.Bind_group_layout_entry.binding = 1
          ; visibility = [ Wgpu.Shader_stage.Item.Vertex ]
          ; buffer =
              Some
                { Wgpu.Bind_group_layout_entry.Buffer_binding_layout.type_ =
                    Wgpu.Buffer_binding_type.Read_only_storage
                ; has_dynamic_offset = false
                ; min_binding_size = 0L
                }
          ; sampler = None
          ; texture = None
          ; storage_texture = None
          }
        ]
      ()
  in
  let bind_group =
    Wgpu.Device.create_bind_group
      device
      ~label:"rotation_bind_group"
      ~layout:bind_group_layout
      ~entries:
        [ { Wgpu.Bind_group_entry.binding = 0
          ; buffer = Some uniform_buffer
          ; offset = 0L
          ; size = Int64.of_int uniform_buffer_size
          ; sampler = None
          ; texture_view = None
          }
        ; { Wgpu.Bind_group_entry.binding = 1
          ; buffer = Some vertex_buffer
          ; offset = 0L
          ; size = Int64.of_int (Array.length f_vertices * 4)
          ; sampler = None
          ; texture_view = None
          }
        ]
      ()
  in
  let pipeline_layout =
    Wgpu.Device.create_pipeline_layout
      device
      ~label:"rotation_pipeline_layout"
      ~bind_group_layouts:[ bind_group_layout ]
      ()
  in
  let pipeline =
    Wgpu.Device.create_render_pipeline
      device
      ~label:"rotation_pipeline"
      ~shader_module:shader
      ~vertex_entry_point:"vs_main"
      ~fragment_entry_point:"fs_main"
      ~color_format:Wgpu.Texture_format.Rgba8_unorm
      ~layout:pipeline_layout
      ()
  in
  (* Render frames at notable unit circle points
     The unit circle has Y going down in our pixel space coordinate system
     to match the lesson's convention. *)
  let sqrt2_over_2 = Float.sqrt 2.0 /. 2.0 in
  let frames =
    [ (* (1, 0): 0 degrees, pointing right (3 o'clock) *)
      "rotation_unit_circle_1_0", 1.0, 0.0
    ; (* (sqrt(2)/2, sqrt(2)/2): 45 degrees *)
      "rotation_unit_circle_0707_0707", sqrt2_over_2, sqrt2_over_2
    ; (* (0, 1): 90 degrees, pointing down (6 o'clock in pixel space) *)
      "rotation_unit_circle_0_1", 0.0, 1.0
    ; (* (-1, 0): 180 degrees, pointing left (9 o'clock) *)
      "rotation_unit_circle_neg1_0", -1.0, 0.0
    ]
  in
  List.iter frames ~f:(fun (output_name, rotation_cos, rotation_sin) ->
    render_frame
      ~device
      ~queue
      ~pipeline
      ~bind_group
      ~uniform_buffer
      ~index_buffer
      ~texture
      ~texture_view
      ~readback_buffer
      ~translation_x:200.0
      ~translation_y:150.0
      ~rotation_cos
      ~rotation_sin
      ~color_r:0.2
      ~color_g:0.6
      ~color_b:0.9
      ~output_name);
  (* Cleanup *)
  Wgpu.Render_pipeline.release pipeline;
  Wgpu.Pipeline_layout.release pipeline_layout;
  Wgpu.Bind_group.release bind_group;
  Wgpu.Bind_group_layout.release bind_group_layout;
  Wgpu.Buffer.release uniform_buffer;
  Wgpu.Buffer.release index_buffer;
  Wgpu.Buffer.release vertex_buffer;
  Wgpu.Buffer.release readback_buffer;
  Wgpu.Texture_view.release texture_view;
  Wgpu.Texture.release texture;
  Wgpu.Shader_module.release shader;
  Wgpu.Queue.release queue;
  Wgpu.Device.release device;
  Wgpu.Adapter.release adapter;
  Wgpu.Instance.release instance
;;
