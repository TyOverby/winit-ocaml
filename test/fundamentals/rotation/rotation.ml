(*
   WebGPU Fundamentals: Rotation

   This test demonstrates 2D rotation using sine and cosine values.
   The F shape is rotated around its origin by passing rotation
   parameters (cos(angle), sin(angle)) to the shader.

   Based on: webgpufundamentals.org rotation lesson (rotation.js)

   Key concepts:
   - Rotation using unit circle: cos and sin values
   - Uniform buffers for transform parameters
   - Pixel-space to clip-space conversion with Y flip

   We render at multiple rotation angles to demonstrate the effect:
   - 0 degrees
   - 45 degrees
   - 90 degrees
   - 180 degrees
*)

open! Core

let width = 600
let height = 400
let bytes_per_pixel = 4
let bytes_per_row = ((width * bytes_per_pixel) + 255) / 256 * 256
let buffer_size = bytes_per_row * height

(* The F shape vertices (12 vertices for 6 triangles via indexed drawing) *)
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

let f_indices =
  [| (* left column *)
     0
   ; 1
   ; 2
   ; 2
   ; 1
   ; 3
   ; (* top rung *)
     4
   ; 5
   ; 6
   ; 6
   ; 5
   ; 7
   ; (* middle rung *)
     8
   ; 9
   ; 10
   ; 10
   ; 9
   ; 11
  |]
;;

let num_indices = Array.length f_indices

(* Uniform buffer layout:
   - color: vec4f (16 bytes, offset 0)
   - resolution: vec2f (8 bytes, offset 16)
   - translation: vec2f (8 bytes, offset 24)
   - rotation: vec2f (8 bytes, offset 32)
   Total: 40 bytes, but we pad to 48 for alignment *)
let uniform_buffer_size = 48

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
@group(0) @binding(1) var<storage, read> vertices: array<vec2f>;

@vertex fn vs_main(@builtin(vertex_index) vertex_index: u32) -> VSOutput {
  var vsOut: VSOutput;

  let position = vertices[vertex_index];

  // Rotate the position
  // rotation.x = cos(angle), rotation.y = sin(angle)
  let rotatedPosition = vec2f(
    position.x * uni.rotation.x - position.y * uni.rotation.y,
    position.x * uni.rotation.y + position.y * uni.rotation.x
  );

  // Add in the translation
  let translated = rotatedPosition + uni.translation;

  // Convert from pixel space to clip space
  // First, convert to 0..1
  let zeroToOne = translated / uni.resolution;

  // Convert from 0..1 to 0..2
  let zeroToTwo = zeroToOne * 2.0;

  // Convert from 0..2 to -1..1 (clip space)
  let flippedClipSpace = zeroToTwo - 1.0;

  // Flip Y (pixel space has Y going down, clip space has Y going up)
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
  (* Create and upload the F vertex data as a storage buffer *)
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
  (* Create and upload index data *)
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

let deg_to_rad deg = deg *. Float.pi /. 180.0

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
  ~rotation_deg
  ~color_r
  ~color_g
  ~color_b
  ~output_name
  =
  (* Update uniform buffer *)
  let uniform_data = Bigarray.Array1.create Bigarray.float32 Bigarray.c_layout 12 in
  let rotation_rad = deg_to_rad rotation_deg in
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
  (* rotation (vec2f): cos and sin *)
  Bigarray.Array1.set uniform_data 8 (Float.cos rotation_rad);
  Bigarray.Array1.set uniform_data 9 (Float.sin rotation_rad);
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
  (* Cleanup this frame's resources *)
  Wgpu.Command_buffer.release command_buffer;
  Wgpu.Render_pass_encoder.release render_pass;
  Wgpu.Command_encoder.release encoder
;;

let () =
  let instance, adapter, device, queue = init () in
  let shader =
    Wgpu.Device.create_shader_module device ~label:"rotation_shader" ~wgsl:shader_code ()
  in
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
  (* Create vertex storage buffer and index buffer *)
  let vertex_buffer = create_f_vertex_buffer device queue in
  let index_buffer = create_index_buffer device queue in
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
  (* Create bind group layout with uniform buffer and storage buffer *)
  let bind_group_layout =
    Wgpu.Device.create_bind_group_layout
      device
      ~label:"rotation_bind_group_layout"
      ~entries:
        [ (* binding 0: uniform buffer *)
          { Wgpu.Bind_group_layout_entry.binding = 0
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
        ; (* binding 1: storage buffer for vertices *)
          { Wgpu.Bind_group_layout_entry.binding = 1
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
  (* Create bind group *)
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
  (* Create pipeline layout *)
  let pipeline_layout =
    Wgpu.Device.create_pipeline_layout
      device
      ~label:"rotation_pipeline_layout"
      ~bind_group_layouts:[ bind_group_layout ]
      ()
  in
  (* Create render pipeline *)
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
  (* Render frames at different rotation angles *)
  let frames =
    [ "rotation_0deg", 0.0
    ; "rotation_45deg", 45.0
    ; "rotation_90deg", 90.0
    ; "rotation_180deg", 180.0
    ]
  in
  List.iter frames ~f:(fun (output_name, rotation_deg) ->
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
      ~rotation_deg
      ~color_r:0.8
      ~color_g:0.2
      ~color_b:0.1
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
