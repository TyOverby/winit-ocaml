(*
   WebGPU Fundamentals: Vertex Buffers

   This test demonstrates the basic use of vertex buffers in WebGPU.
   We render 100 colored circles using:
   - A vertex buffer with position data (stepped per vertex)
   - Storage buffers for per-instance color/offset and scale data

   The circles are positioned randomly across the canvas and each
   has a random color and size.
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
  (* 2 triangles per subdivision, 3 verts per tri, 2 values (xy) each *)
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
  (* 2 triangles per subdivision:
     0--1 4
     | / /|
     |/ / |
     2 3--5 *)
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
struct OurStruct {
  color: vec4f,
  offset: vec2f,
};

struct OtherStruct {
  scale: vec2f,
};

struct Vertex {
  @location(0) position: vec2f,
};

struct VSOutput {
  @builtin(position) position: vec4f,
  @location(0) color: vec4f,
};

@group(0) @binding(0) var<storage, read> ourStructs: array<OurStruct>;
@group(0) @binding(1) var<storage, read> otherStructs: array<OtherStruct>;

@vertex fn vs(
  vert: Vertex,
  @builtin(instance_index) instanceIndex: u32
) -> VSOutput {
  let otherStruct = otherStructs[instanceIndex];
  let ourStruct = ourStructs[instanceIndex];

  var vsOut: VSOutput;
  vsOut.position = vec4f(
      vert.position * otherStruct.scale + ourStruct.offset, 0.0, 1.0);
  vsOut.color = ourStruct.color;
  return vsOut;
}

@fragment fn fs(vsOut: VSOutput) -> @location(0) vec4f {
  return vsOut.color;
}
|}
;;

(* Storage buffer layout for static data (color + offset):
   - color: vec4f (4 floats, 16 bytes)
   - offset: vec2f (2 floats, 8 bytes)
   - padding: 8 bytes (struct alignment)
   Total per object: 32 bytes *)
let static_unit_size = 32

(* Storage buffer layout for dynamic data (scale):
   - scale: vec2f (2 floats, 8 bytes)
   Total per object: 8 bytes *)
let changing_unit_size = 8

let init () =
  let instance = Wgpu.Instance.create () in
  let adapter = Wgpu.Instance.request_adapter instance () in
  let device = Wgpu.Adapter.request_device adapter in
  let queue = Wgpu.Device.get_queue device in
  let shader =
    Wgpu.Device.create_shader_module
      device
      ~label:"vertex_buffers_shader"
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
  (* Create storage buffers for per-instance data *)
  let static_storage_buffer_size = static_unit_size * num_objects in
  let static_storage_buffer =
    Wgpu.Device.create_buffer
      device
      ~label:"static_storage_buffer"
      ~size:(Int64.of_int static_storage_buffer_size)
      ~usage:[ Wgpu.Buffer_usage.Item.Storage; Wgpu.Buffer_usage.Item.Copy_dst ]
      ~mapped_at_creation:false
      ()
  in
  let changing_storage_buffer_size = changing_unit_size * num_objects in
  let changing_storage_buffer =
    Wgpu.Device.create_buffer
      device
      ~label:"changing_storage_buffer"
      ~size:(Int64.of_int changing_storage_buffer_size)
      ~usage:[ Wgpu.Buffer_usage.Item.Storage; Wgpu.Buffer_usage.Item.Copy_dst ]
      ~mapped_at_creation:false
      ()
  in
  (* Populate static storage buffer with colors and offsets *)
  let object_scales = Array.create ~len:num_objects 0.0 in
  let ( (* Populate static storage data *) ) =
    let static_data =
      Bigarray.Array1.create
        Bigarray.float32
        Bigarray.c_layout
        (static_storage_buffer_size / 4)
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
      (* padding at offset 6,7 *)
      Bigarray.Array1.set static_data (offset + 6) 0.0;
      Bigarray.Array1.set static_data (offset + 7) 0.0;
      object_scales.(i) <- 0.2 +. Random.float 0.3
    done;
    Wgpu.Queue.write_buffer
      queue
      ~buffer:static_storage_buffer
      ~offset:0L
      ~data:static_data
  in
  (* Populate changing storage buffer with scales *)
  let changing_data =
    Bigarray.Array1.create
      Bigarray.float32
      Bigarray.c_layout
      (changing_storage_buffer_size / 4)
  in
  let aspect = Float.of_int width /. Float.of_int height in
  for i = 0 to num_objects - 1 do
    let offset = i * (changing_unit_size / 4) in
    (* scale: xy *)
    Bigarray.Array1.set changing_data offset (object_scales.(i) /. aspect);
    Bigarray.Array1.set changing_data (offset + 1) object_scales.(i)
  done;
  Wgpu.Queue.write_buffer
    queue
    ~buffer:changing_storage_buffer
    ~offset:0L
    ~data:changing_data;
  (* Create bind group layout with two storage buffer bindings *)
  let bind_group_layout =
    Wgpu.Device.create_bind_group_layout
      device
      ~label:"storage_bind_group_layout"
      ~entries:
        [ { Wgpu.Bind_group_layout_entry.binding = 0
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
      ~label:"storage_bind_group"
      ~layout:bind_group_layout
      ~entries:
        [ { Wgpu.Bind_group_entry.binding = 0
          ; buffer = Some static_storage_buffer
          ; offset = 0L
          ; size = Int64.of_int static_storage_buffer_size
          ; sampler = None
          ; texture_view = None
          }
        ; { Wgpu.Bind_group_entry.binding = 1
          ; buffer = Some changing_storage_buffer
          ; offset = 0L
          ; size = Int64.of_int changing_storage_buffer_size
          ; sampler = None
          ; texture_view = None
          }
        ]
      ()
  in
  let pipeline_layout =
    Wgpu.Device.create_pipeline_layout
      device
      ~label:"vertex_buffers_pipeline_layout"
      ~bind_group_layouts:[ bind_group_layout ]
      ()
  in
  (* Define vertex buffer layout: position at @location(0) *)
  let vertex_buffer_layout =
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
  (* Create render pipeline *)
  let pipeline =
    Wgpu.Device.create_render_pipeline
      device
      ~label:"vertex_buffers_pipeline"
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
    Wgpu.Command_encoder.begin_render_pass
      encoder
      ~label:"vertex_buffers_pass"
      ~color_attachments:
        [ { view = Some texture_view
          ; depth_slice = 0xFFFFFFFF
          ; resolve_target = None
          ; load_op = Wgpu.Load_op.Clear
          ; store_op = Wgpu.Store_op.Store
          ; clear_value = Some { r = 0.3; g = 0.3; b = 0.3; a = 1.0 }
          }
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
  Wgpu.set_bind_group_render render_pass ~index:0 ~bind_group;
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
    let ppm_file = Test_util.output_path "vertex_buffers.ppm" in
    let png_file = Test_util.output_path "vertex_buffers.png" in
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
  Wgpu.Pipeline_layout.release pipeline_layout;
  Wgpu.Bind_group.release bind_group;
  Wgpu.Bind_group_layout.release bind_group_layout;
  Wgpu.Buffer.release changing_storage_buffer;
  Wgpu.Buffer.release static_storage_buffer;
  Wgpu.Buffer.release vertex_buffer;
  Wgpu.Shader_module.release shader;
  Wgpu.Queue.release queue;
  Wgpu.Device.release device;
  Wgpu.Adapter.release adapter;
  Wgpu.Instance.release instance
;;
