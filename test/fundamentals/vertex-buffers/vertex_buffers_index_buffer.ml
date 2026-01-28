(*
   WebGPU Fundamentals: Vertex Buffers with Index Buffer

   This test demonstrates index buffers in WebGPU. Instead of duplicating
   vertices for each triangle, we store unique vertices and use an index
   buffer to specify how they connect into triangles.

   This saves memory (33%) and potentially GPU processing time since the
   GPU can reuse already-computed vertices.

   This example uses:
   - Vertex buffers with per-vertex data (position + color as floats)
   - Instance buffers with per-instance data (color, offset, scale)
   - Index buffers to efficiently share vertices between triangles
*)

open! Core

let width = 600
let height = 400
let bytes_per_pixel = 4
let bytes_per_row = ((width * bytes_per_pixel) + 255) / 256 * 256
let buffer_size = bytes_per_row * height
let num_objects = 100
let num_subdivisions = 24

(* Create circle vertices with per-vertex colors using index buffer approach.
   Instead of 6 vertices per subdivision, we use 4 unique vertices and
   6 indices to form 2 triangles.

   Vertex layout (looking at the circle from above):
   0  2  4  6  8 ...  (outer ring)

   1  3  5  7  9 ...  (inner ring)

   Triangles for each subdivision i:
   - Triangle 1: 2i, 2i+1, 2i+2
   - Triangle 2: 2i+2, 2i+1, 2i+3
*)
let create_circle_vertices ~radius ~inner_radius =
  (* (num_subdivisions + 1) * 2 vertices for the ring *)
  let num_vertices = (num_subdivisions + 1) * 2 in
  (* 5 floats per vertex: x, y, r, g, b *)
  let vertex_data =
    Bigarray.Array1.create Bigarray.float32 Bigarray.c_layout (num_vertices * 5)
  in
  let offset = ref 0 in
  let add_vertex x y r g b =
    Bigarray.Array1.set vertex_data !offset x;
    Bigarray.Array1.set vertex_data (!offset + 1) y;
    Bigarray.Array1.set vertex_data (!offset + 2) r;
    Bigarray.Array1.set vertex_data (!offset + 3) g;
    Bigarray.Array1.set vertex_data (!offset + 4) b;
    offset := !offset + 5
  in
  let inner_r, inner_g, inner_b = 1.0, 1.0, 1.0 in
  let outer_r, outer_g, outer_b = 0.1, 0.1, 0.1 in
  (* Create vertices: alternate outer/inner for each angle *)
  for i = 0 to num_subdivisions do
    let start_angle = 0.0 in
    let end_angle = Float.pi *. 2.0 in
    let angle =
      start_angle
      +. (Float.of_int i *. (end_angle -. start_angle) /. Float.of_int num_subdivisions)
    in
    let c = Float.cos angle in
    let s = Float.sin angle in
    add_vertex (c *. radius) (s *. radius) outer_r outer_g outer_b;
    add_vertex (c *. inner_radius) (s *. inner_radius) inner_r inner_g inner_b
  done;
  (* Create index buffer: 6 indices per subdivision *)
  let num_indices = num_subdivisions * 6 in
  let index_data = Bigarray.Array1.create Bigarray.int32 Bigarray.c_layout num_indices in
  let ndx = ref 0 in
  for i = 0 to num_subdivisions - 1 do
    let ndx_offset = Int32.of_int_exn (i * 2) in
    (* first triangle: 2i, 2i+1, 2i+2 *)
    Bigarray.Array1.set index_data !ndx ndx_offset;
    Bigarray.Array1.set index_data (!ndx + 1) (Int32.( + ) ndx_offset 1l);
    Bigarray.Array1.set index_data (!ndx + 2) (Int32.( + ) ndx_offset 2l);
    (* second triangle: 2i+2, 2i+1, 2i+3 *)
    Bigarray.Array1.set index_data (!ndx + 3) (Int32.( + ) ndx_offset 2l);
    Bigarray.Array1.set index_data (!ndx + 4) (Int32.( + ) ndx_offset 1l);
    Bigarray.Array1.set index_data (!ndx + 5) (Int32.( + ) ndx_offset 3l);
    ndx := !ndx + 6
  done;
  vertex_data, index_data, num_indices
;;

let shader_code =
  {|
struct Vertex {
  @location(0) position: vec2f,
  @location(1) color: vec4f,
  @location(2) offset: vec2f,
  @location(3) scale: vec2f,
  @location(4) perVertexColor: vec3f,
};

struct VSOutput {
  @builtin(position) position: vec4f,
  @location(0) color: vec4f,
};

@vertex fn vs(vert: Vertex) -> VSOutput {
  var vsOut: VSOutput;
  vsOut.position = vec4f(
      vert.position * vert.scale + vert.offset, 0.0, 1.0);
  vsOut.color = vert.color * vec4f(vert.perVertexColor, 1);
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
      ~label:"vertex_buffers_index_buffer_shader"
      ~wgsl:shader_code
      ()
  in
  instance, adapter, device, queue, shader
;;

let () =
  Random.init 42;
  let instance, adapter, device, queue, shader = init () in
  (* Create vertex buffer with circle geometry and per-vertex colors *)
  let vertex_data, index_data, num_indices =
    create_circle_vertices ~radius:0.5 ~inner_radius:0.25
  in
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
  (* Create index buffer *)
  let index_buffer_size = Bigarray.Array1.dim index_data * 4 in
  let index_buffer =
    Wgpu.Device.create_buffer
      device
      ~label:"index_buffer"
      ~size:(Int64.of_int index_buffer_size)
      ~usage:[ Wgpu.Buffer_usage.Item.Index; Wgpu.Buffer_usage.Item.Copy_dst ]
      ~mapped_at_creation:false
      ()
  in
  Wgpu.Queue.write_buffer queue ~buffer:index_buffer ~offset:0L ~data:index_data;
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
    ; array_stride = Int64.of_int (5 * 4)
    ; attributes =
        [ { Wgpu.Vertex_attribute.format = Wgpu.Vertex_format.Float32x2
          ; offset = 0L
          ; shader_location = 0
          }
        ; { Wgpu.Vertex_attribute.format = Wgpu.Vertex_format.Float32x3
          ; offset = Int64.of_int 8
          ; shader_location = 4
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
      ~label:"vertex_buffers_index_buffer_pipeline"
      ~shader_module:shader
      ~vertex_entry_point:"vs"
      ~fragment_entry_point:"fs"
      ~color_format:Wgpu.Texture_format.Rgba8_unorm
      ~vertex_buffer_layouts:
        [ vertex_buffer_layout_position
        ; vertex_buffer_layout_static
        ; vertex_buffer_layout_changing
        ]
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
    Wgpu.begin_render_pass
      encoder
      ~label:"vertex_buffers_index_buffer_pass"
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
  Wgpu.Render_pass_encoder.set_index_buffer
    render_pass
    ~buffer:index_buffer
    ~format:Wgpu.Index_format.Uint32
    ~offset:0L
    ~size:(Int64.of_int index_buffer_size);
  Wgpu.Render_pass_encoder.draw_indexed
    render_pass
    ~index_count:num_indices
    ~instance_count:num_objects
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
    let ppm_file = Test_util.output_path "vertex_buffers_index_buffer.ppm" in
    let png_file = Test_util.output_path "vertex_buffers_index_buffer.png" in
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
  Wgpu.Buffer.release index_buffer;
  Wgpu.Buffer.release vertex_buffer;
  Wgpu.Shader_module.release shader;
  Wgpu.Queue.release queue;
  Wgpu.Device.release device;
  Wgpu.Adapter.release adapter;
  Wgpu.Instance.release instance
;;
