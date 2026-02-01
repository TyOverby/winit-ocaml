(*
   WebGPU Fundamentals: Split Uniform Buffers

   This test demonstrates using multiple uniform buffers to separate static and
   dynamic data. This is an optimization pattern where:
   - Static data (color, offset) is uploaded once at initialization
   - Dynamic data (scale) is uploaded every frame

   By splitting the uniforms, we only upload the data that changes, reducing
   the amount of data transferred to the GPU each frame.

   This example uses:
   - @binding(0): OurStruct with color (vec4f) and offset (vec2f)
   - @binding(1): OtherStruct with scale (vec2f)
*)

open! Core

let width = 600
let height = 400
let bytes_per_pixel = 4
let bytes_per_row = ((width * bytes_per_pixel) + 255) / 256 * 256
let buffer_size = bytes_per_row * height

(* Static uniform buffer layout (OurStruct):
   - color: vec4f (4 floats, 16 bytes)
   - offset: vec2f (2 floats, 8 bytes)
   - padding: 8 bytes to align to 16 bytes
   Total: 32 bytes *)
let num_static_floats = 8
let static_uniform_buffer_size = num_static_floats * 4

(* Dynamic uniform buffer layout (OtherStruct):
   - scale: vec2f (2 floats, 8 bytes)
   - padding: 8 bytes to align to 16 bytes
   Total: 16 bytes *)
let num_dynamic_floats = 4
let dynamic_uniform_buffer_size = num_dynamic_floats * 4
let num_objects = 100

let shader_code =
  {|
struct OurStruct {
  color: vec4f,
  offset: vec2f,
};

struct OtherStruct {
  scale: vec2f,
};

@group(0) @binding(0) var<uniform> ourStruct: OurStruct;
@group(0) @binding(1) var<uniform> otherStruct: OtherStruct;

@vertex fn vs(
  @builtin(vertex_index) vertexIndex : u32
) -> @builtin(position) vec4f {
  let pos = array(
    vec2f( 0.0,  0.5),  // top center
    vec2f(-0.5, -0.5),  // bottom left
    vec2f( 0.5, -0.5)   // bottom right
  );

  return vec4f(
    pos[vertexIndex] * otherStruct.scale + ourStruct.offset, 0.0, 1.0);
}

@fragment fn fs() -> @location(0) vec4f {
  return ourStruct.color;
}
|}
;;

(* Random number in range [min, max) *)
let rand ~min ~max = min +. Random.float (max -. min)

type object_info =
  { scale : float
  ; dynamic_buffer : Wgpu.Buffer.t
  ; dynamic_values : (float, Bigarray.float32_elt, Bigarray.c_layout) Bigarray.Array1.t
  ; bind_group : Wgpu.Bind_group.t
  ; static_buffer : Wgpu.Buffer.t
  }

let init () =
  let instance = Wgpu.Instance.create () in
  let adapter = Wgpu.Instance.request_adapter instance () in
  let device = Wgpu.Adapter.request_device adapter in
  let queue = Wgpu.Device.get_queue device in
  let shader =
    Wgpu.Device.create_shader_module
      device
      ~label:"uniforms_split_shader"
      ~wgsl:shader_code
      ()
  in
  instance, adapter, device, queue, shader
;;

let () =
  (* Use a fixed seed for reproducible output *)
  Random.init 42;
  let instance, adapter, device, queue, shader = init () in
  (* Create bind group layout with two buffer bindings *)
  let bind_group_layout =
    Wgpu.Device.create_bind_group_layout
      device
      ~label:"split_uniform_bind_group_layout"
      ~entries:
        [ (* Binding 0: static uniforms (color, offset) *)
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
        ; (* Binding 1: dynamic uniforms (scale) *)
          { Wgpu.Bind_group_layout_entry.binding = 1
          ; visibility = [ Wgpu.Shader_stage.Item.Vertex ]
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
        ]
      ()
  in
  (* Create pipeline layout *)
  let pipeline_layout =
    Wgpu.Device.create_pipeline_layout
      device
      ~label:"uniforms_split_pipeline_layout"
      ~bind_group_layouts:[ bind_group_layout ]
      ()
  in
  (* Create render pipeline *)
  let pipeline =
    Wgpu.Device.create_render_pipeline
      device
      ~label:"uniforms_split_pipeline"
      ~layout:pipeline_layout
      ~vertex_module:shader
      ~vertex_entry_point:"vs"
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
  (* Offsets into static uniform buffer *)
  let k_color_offset = 0 in
  let k_offset_offset = 4 in
  (* Create object infos with random colors and offsets *)
  let object_infos =
    List.init num_objects ~f:(fun i ->
      (* Create static uniform buffer *)
      let static_buffer =
        Wgpu.Device.create_buffer
          device
          ~label:(sprintf "static uniforms for obj: %d" i)
          ~size:(Int64.of_int static_uniform_buffer_size)
          ~usage:[ Wgpu.Buffer_usage.Item.Uniform; Wgpu.Buffer_usage.Item.Copy_dst ]
          ~mapped_at_creation:false
          ()
      in
      (* Set static values (only done once) *)
      let static_values =
        Bigarray.Array1.create Bigarray.float32 Bigarray.c_layout num_static_floats
      in
      (* Random color *)
      Bigarray.Array1.set static_values (k_color_offset + 0) (Random.float 1.0);
      Bigarray.Array1.set static_values (k_color_offset + 1) (Random.float 1.0);
      Bigarray.Array1.set static_values (k_color_offset + 2) (Random.float 1.0);
      Bigarray.Array1.set static_values (k_color_offset + 3) 1.0;
      (* Random offset in [-0.9, 0.9] *)
      Bigarray.Array1.set static_values (k_offset_offset + 0) (rand ~min:(-0.9) ~max:0.9);
      Bigarray.Array1.set static_values (k_offset_offset + 1) (rand ~min:(-0.9) ~max:0.9);
      (* Padding *)
      Bigarray.Array1.set static_values 6 0.0;
      Bigarray.Array1.set static_values 7 0.0;
      (* Upload static values *)
      Wgpu.Queue.write_buffer queue ~buffer:static_buffer ~offset:0L ~data:static_values;
      (* Create dynamic uniform buffer *)
      let dynamic_buffer =
        Wgpu.Device.create_buffer
          device
          ~label:(sprintf "dynamic uniforms for obj: %d" i)
          ~size:(Int64.of_int dynamic_uniform_buffer_size)
          ~usage:[ Wgpu.Buffer_usage.Item.Uniform; Wgpu.Buffer_usage.Item.Copy_dst ]
          ~mapped_at_creation:false
          ()
      in
      let dynamic_values =
        Bigarray.Array1.create Bigarray.float32 Bigarray.c_layout num_dynamic_floats
      in
      (* Create bind group with both buffers *)
      let bind_group =
        Wgpu.Device.create_bind_group
          device
          ~label:(sprintf "bind group for obj: %d" i)
          ~layout:bind_group_layout
          ~entries:
            [ { Wgpu.Bind_group_entry.binding = 0
              ; buffer = Some static_buffer
              ; offset = 0L
              ; size = Int64.of_int static_uniform_buffer_size
              ; sampler = None
              ; texture_view = None
              }
            ; { Wgpu.Bind_group_entry.binding = 1
              ; buffer = Some dynamic_buffer
              ; offset = 0L
              ; size = Int64.of_int dynamic_uniform_buffer_size
              ; sampler = None
              ; texture_view = None
              }
            ]
          ()
      in
      let scale = rand ~min:0.2 ~max:0.5 in
      { scale; dynamic_buffer; dynamic_values; bind_group; static_buffer })
  in
  (* Create render target *)
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
  (* Render *)
  let encoder = Wgpu.Device.create_command_encoder device ~label:"render_encoder" () in
  let render_pass =
    Wgpu.Command_encoder.begin_render_pass
      encoder
      ~label:"uniforms_split_pass"
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
  (* Update and draw each object - only updating the dynamic scale buffer *)
  let aspect = Float.of_int width /. Float.of_int height in
  let k_scale_offset = 0 in
  List.iter
    object_infos
    ~f:(fun { scale; dynamic_buffer; dynamic_values; bind_group; _ } ->
      (* Only update scale (the dynamic part) *)
      Bigarray.Array1.set dynamic_values (k_scale_offset + 0) (scale /. aspect);
      Bigarray.Array1.set dynamic_values (k_scale_offset + 1) scale;
      (* Padding *)
      Bigarray.Array1.set dynamic_values 2 0.0;
      Bigarray.Array1.set dynamic_values 3 0.0;
      Wgpu.Queue.write_buffer queue ~buffer:dynamic_buffer ~offset:0L ~data:dynamic_values;
      Wgpu.set_bind_group_render render_pass ~index:0 ~bind_group;
      Wgpu.Render_pass_encoder.draw
        render_pass
        ~vertex_count:3
        ~instance_count:1
        ~first_vertex:0
        ~first_instance:0);
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
    let ppm_file = Test_util.output_path "simple_triangle_uniforms_split.ppm" in
    let png_file = Test_util.output_path "simple_triangle_uniforms_split.png" in
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
  List.iter object_infos ~f:(fun { dynamic_buffer; bind_group; static_buffer; _ } ->
    Wgpu.Bind_group.release bind_group;
    Wgpu.Buffer.release dynamic_buffer;
    Wgpu.Buffer.release static_buffer);
  Wgpu.Bind_group_layout.release bind_group_layout;
  Wgpu.Shader_module.release shader;
  Wgpu.Queue.release queue;
  Wgpu.Device.release device;
  Wgpu.Adapter.release adapter;
  Wgpu.Instance.release instance
;;
