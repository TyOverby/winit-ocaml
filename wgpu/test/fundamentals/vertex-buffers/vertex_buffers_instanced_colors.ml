(*
   WebGPU Fundamentals: Vertex Buffers with Instanced Colors

   This test demonstrates instanced vertex attributes in WebGPU.
   We render 100 colored circles using only vertex buffers (no storage buffers):
   - A vertex buffer with position data (stepped per vertex)
   - A vertex buffer with color and offset (stepped per instance)
   - A vertex buffer with scale (stepped per instance)

   This shows how attributes can advance per instance instead of per vertex.
*)

open! Core

let width = 600
let height = 400
let bytes_per_pixel = 4
let bytes_per_row = ((width * bytes_per_pixel) + 255) / 256 * 256
let buffer_size = bytes_per_row * height
let num_objects = 100
let num_subdivisions = 24

(* Create circle vertices as an array of (x, y) positions *)
let create_circle_vertices ~radius ~inner_radius =
  let num_vertices = num_subdivisions * 3 * 2 in
  let vertex_data =
    Bigarray.Array1.create Bigarray.float32 Bigarray.c_layout (num_vertices * 2)
  in
  let offset = ref 0 in
  let add_vertex x y =
    Bigarray.Array1.set vertex_data !offset x;
    Bigarray.Array1.set vertex_data (!offset + 1) y;
    offset := !offset + 2
  in
  for i = 0 to num_subdivisions - 1 do
    let start_angle = 0.0 in
    let end_angle = Float.pi *. 2.0 in
    let angle1 =
      start_angle
      +. (Float.of_int i *. (end_angle -. start_angle) /. Float.of_int num_subdivisions)
    in
    let angle2 =
      start_angle
      +. (Float.of_int (i + 1)
          *. (end_angle -. start_angle)
          /. Float.of_int num_subdivisions)
    in
    let c1 = Float.cos angle1 in
    let s1 = Float.sin angle1 in
    let c2 = Float.cos angle2 in
    let s2 = Float.sin angle2 in
    (* first triangle *)
    add_vertex (c1 *. radius) (s1 *. radius);
    add_vertex (c2 *. radius) (s2 *. radius);
    add_vertex (c1 *. inner_radius) (s1 *. inner_radius);
    (* second triangle *)
    add_vertex (c1 *. inner_radius) (s1 *. inner_radius);
    add_vertex (c2 *. radius) (s2 *. radius);
    add_vertex (c2 *. inner_radius) (s2 *. inner_radius)
  done;
  vertex_data, num_vertices
;;

let shader_code =
  {|
struct Vertex {
  @location(0) position: vec2f,
  @location(1) color: vec4f,
  @location(2) offset: vec2f,
  @location(3) scale: vec2f,
};

struct VSOutput {
  @builtin(position) position: vec4f,
  @location(0) color: vec4f,
};

@vertex fn vs(vert: Vertex) -> VSOutput {
  var vsOut: VSOutput;
  vsOut.position = vec4f(
      vert.position * vert.scale + vert.offset, 0.0, 1.0);
  vsOut.color = vert.color;
  return vsOut;
}

@fragment fn fs(vsOut: VSOutput) -> @location(0) vec4f {
  return vsOut.color;
}
|}
;;

(* Static vertex buffer layout (color + offset):
   - color: vec4f (4 floats, 16 bytes)
   - offset: vec2f (2 floats, 8 bytes)
   Total per instance: 24 bytes *)
let static_unit_size = 24

(* Changing vertex buffer layout (scale):
   - scale: vec2f (2 floats, 8 bytes)
   Total per instance: 8 bytes *)
let changing_unit_size = 8

let init () =
  let instance = Wgpu.Instance.create () in
  let adapter = Wgpu.Instance.request_adapter instance () in
  let device = Wgpu.Adapter.request_device adapter in
  let queue = Wgpu.Device.get_queue device in
  let shader =
    Wgpu.Device.create_shader_module
      device
      ~label:"vertex_buffers_instanced_shader"
      ~wgsl:shader_code
      ()
  in
  instance, adapter, device, queue, shader
;;

let () =
  Random.init 42;
  let instance, adapter, device, queue, shader = init () in
  (* Create vertex buffer with circle geometry *)
  let vertex_data, num_vertices = create_circle_vertices ~radius:0.5 ~inner_radius:0.25 in
  let vertex_buffer_size = Bigarray.Array1.dim vertex_data * 4 in
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
  (* Create static vertex buffer (color + offset, per instance) *)
  let static_vertex_buffer_size = static_unit_size * num_objects in
  let static_vertex_buffer =
    Wgpu.Device.create_buffer
      device
      ~label:"static_vertex_buffer"
      ~size:(Int64.of_int static_vertex_buffer_size)
      ~usage:[ Wgpu.Buffer_usage.Item.Vertex; Wgpu.Buffer_usage.Item.Copy_dst ]
      ~mapped_at_creation:false
      ()
  in
  (* Create changing vertex buffer (scale, per instance) *)
  let changing_vertex_buffer_size = changing_unit_size * num_objects in
  let changing_vertex_buffer =
    Wgpu.Device.create_buffer
      device
      ~label:"changing_vertex_buffer"
      ~size:(Int64.of_int changing_vertex_buffer_size)
      ~usage:[ Wgpu.Buffer_usage.Item.Vertex; Wgpu.Buffer_usage.Item.Copy_dst ]
      ~mapped_at_creation:false
      ()
  in
  (* Populate static vertex buffer with colors and offsets *)
  let object_scales = Array.create ~len:num_objects 0.0 in
  let ( (* Populate static vertex data *) ) =
    let static_data =
      Bigarray.Array1.create
        Bigarray.float32
        Bigarray.c_layout
        (static_vertex_buffer_size / 4)
    in
    for i = 0 to num_objects - 1 do
      let offset = i * (static_unit_size / 4) in
      (* color at offset 0: rgba *)
      Bigarray.Array1.set static_data offset (Random.float 1.0);
      Bigarray.Array1.set static_data (offset + 1) (Random.float 1.0);
      Bigarray.Array1.set static_data (offset + 2) (Random.float 1.0);
      Bigarray.Array1.set static_data (offset + 3) 1.0;
      (* offset at offset 4: xy *)
      Bigarray.Array1.set static_data (offset + 4) (Random.float 1.8 -. 0.9);
      Bigarray.Array1.set static_data (offset + 5) (Random.float 1.8 -. 0.9);
      object_scales.(i) <- 0.2 +. Random.float 0.3
    done;
    Wgpu.Queue.write_buffer
      queue
      ~buffer:static_vertex_buffer
      ~offset:0L
      ~data:static_data
  in
  (* Populate changing vertex buffer with scales *)
  let changing_data =
    Bigarray.Array1.create
      Bigarray.float32
      Bigarray.c_layout
      (changing_vertex_buffer_size / 4)
  in
  let aspect = Float.of_int width /. Float.of_int height in
  for i = 0 to num_objects - 1 do
    let offset = i * (changing_unit_size / 4) in
    Bigarray.Array1.set changing_data offset (object_scales.(i) /. aspect);
    Bigarray.Array1.set changing_data (offset + 1) object_scales.(i)
  done;
  Wgpu.Queue.write_buffer
    queue
    ~buffer:changing_vertex_buffer
    ~offset:0L
    ~data:changing_data;
  (* Define vertex buffer layouts *)
  let vertex_buffer_layout_position =
    { Wgpu.Vertex_buffer_layout.step_mode = Wgpu.Vertex_step_mode.Vertex
    ; array_stride = Int64.of_int (2 * 4)
    ; attributes =
        [ { Wgpu.Vertex_attribute.format = Wgpu.Vertex_format.Float32x2
          ; offset = 0L
          ; shader_location = 0
          }
        ]
    }
  in
  let vertex_buffer_layout_static =
    { Wgpu.Vertex_buffer_layout.step_mode = Wgpu.Vertex_step_mode.Instance
    ; array_stride = Int64.of_int static_unit_size
    ; attributes =
        [ { Wgpu.Vertex_attribute.format = Wgpu.Vertex_format.Float32x4
          ; offset = 0L
          ; shader_location = 1
          }
        ; { Wgpu.Vertex_attribute.format = Wgpu.Vertex_format.Float32x2
          ; offset = Int64.of_int 16
          ; shader_location = 2
          }
        ]
    }
  in
  let vertex_buffer_layout_changing =
    { Wgpu.Vertex_buffer_layout.step_mode = Wgpu.Vertex_step_mode.Instance
    ; array_stride = Int64.of_int changing_unit_size
    ; attributes =
        [ { Wgpu.Vertex_attribute.format = Wgpu.Vertex_format.Float32x2
          ; offset = 0L
          ; shader_location = 3
          }
        ]
    }
  in
  (* Create render pipeline *)
  let pipeline =
    Wgpu.Device.create_render_pipeline
      device
      ~label:"vertex_buffers_instanced_pipeline"
      ~vertex_module:shader
      ~vertex_entry_point:"vs"
      ~vertex_buffers:
        [ vertex_buffer_layout_position
        ; vertex_buffer_layout_static
        ; vertex_buffer_layout_changing
        ]
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
  (* Create render target and render *)
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
  let encoder = Wgpu.Device.create_command_encoder device ~label:"render_encoder" () in
  let render_pass =
    Wgpu.begin_render_pass_simple
      encoder
      ~label:"vertex_buffers_instanced_pass"
      ~color_view:texture_view
      ~clear_color:(0.3, 0.3, 0.3, 1.0)
      ()
  in
  Wgpu.Render_pass_encoder.set_pipeline render_pass ~pipeline;
  Wgpu.Render_pass_encoder.set_vertex_buffer
    render_pass
    ~slot:0
    ~buffer:vertex_buffer
    ~offset:0L
    ~size:(Int64.of_int vertex_buffer_size);
  Wgpu.Render_pass_encoder.set_vertex_buffer
    render_pass
    ~slot:1
    ~buffer:static_vertex_buffer
    ~offset:0L
    ~size:(Int64.of_int static_vertex_buffer_size);
  Wgpu.Render_pass_encoder.set_vertex_buffer
    render_pass
    ~slot:2
    ~buffer:changing_vertex_buffer
    ~offset:0L
    ~size:(Int64.of_int changing_vertex_buffer_size);
  Wgpu.Render_pass_encoder.draw
    render_pass
    ~vertex_count:num_vertices
    ~instance_count:num_objects
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
  let ( (* Write output *) ) =
    let ppm_file = Test_util.output_path "vertex_buffers_instanced_colors.ppm" in
    let png_file = Test_util.output_path "vertex_buffers_instanced_colors.png" in
    Test_util.write_ppm ~filename:ppm_file ~width ~height ~data:mapped_data ~bytes_per_row;
    Test_util.ppm_to_png ~ppm_file ~png_file;
    ()
  in
  Wgpu.Buffer.unmap readback_buffer;
  (* Cleanup *)
  Wgpu.Command_buffer.release command_buffer;
  Wgpu.Render_pass_encoder.release render_pass;
  Wgpu.Command_encoder.release encoder;
  Wgpu.Buffer.release readback_buffer;
  Wgpu.Texture_view.release texture_view;
  Wgpu.Texture.release texture;
  Wgpu.Render_pipeline.release pipeline;
  Wgpu.Buffer.release changing_vertex_buffer;
  Wgpu.Buffer.release static_vertex_buffer;
  Wgpu.Buffer.release vertex_buffer;
  Wgpu.Shader_module.release shader;
  Wgpu.Queue.release queue;
  Wgpu.Device.release device;
  Wgpu.Adapter.release adapter;
  Wgpu.Instance.release instance
;;
