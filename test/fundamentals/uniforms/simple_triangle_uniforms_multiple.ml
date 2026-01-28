(*
   WebGPU Fundamentals: Multiple Triangles with Uniforms

   This test demonstrates drawing multiple objects, each with its own uniform buffer
   and bind group. We create 100 triangles with random colors and positions, each
   using its own uniform buffer.

   This pattern is essential for real applications where many objects need to be
   drawn with different parameters. Each object has:
   - Its own uniform buffer with color/scale/offset
   - Its own bind group that references that buffer
   - Its own random scale value stored on the CPU side

   At render time, we update each uniform buffer with the aspect-corrected scale,
   then draw with the corresponding bind group.
*)

open! Core

let width = 600
let height = 400
let bytes_per_pixel = 4
let bytes_per_row = ((width * bytes_per_pixel) + 255) / 256 * 256
let buffer_size = bytes_per_row * height

(* Uniform buffer layout:
   - color: vec4f (4 floats, 16 bytes)
   - scale: vec2f (2 floats, 8 bytes)
   - offset: vec2f (2 floats, 8 bytes)
   Total: 32 bytes *)
let num_uniform_floats = 8
let uniform_buffer_size = num_uniform_floats * 4
let num_objects = 100

let shader_code =
  {|
struct OurStruct {
  color: vec4f,
  scale: vec2f,
  offset: vec2f,
};

@group(0) @binding(0) var<uniform> ourStruct: OurStruct;

@vertex fn vs(
  @builtin(vertex_index) vertexIndex : u32
) -> @builtin(position) vec4f {
  let pos = array(
    vec2f( 0.0,  0.5),  // top center
    vec2f(-0.5, -0.5),  // bottom left
    vec2f( 0.5, -0.5)   // bottom right
  );

  return vec4f(
    pos[vertexIndex] * ourStruct.scale + ourStruct.offset, 0.0, 1.0);
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
  ; uniform_buffer : Wgpu.Buffer.t
  ; uniform_values : (float, Bigarray.float32_elt, Bigarray.c_layout) Bigarray.Array1.t
  ; bind_group : Wgpu.Bind_group.t
  }

let init () =
  let instance = Wgpu.Instance.create () in
  let adapter = Wgpu.Instance.request_adapter instance () in
  let device = Wgpu.Adapter.request_device adapter in
  let queue = Wgpu.Device.get_queue device in
  let shader =
    Wgpu.Device.create_shader_module
      device
      ~label:"uniforms_multiple_shader"
      ~wgsl:shader_code
      ()
  in
  instance, adapter, device, queue, shader
;;

let () =
  (* Use a fixed seed for reproducible output *)
  Random.init 42;
  let instance, adapter, device, queue, shader = init () in
  (* Create bind group layout (shared by all objects) *)
  let bind_group_layout =
    Wgpu.Device.create_bind_group_layout_for_uniform_buffer
      device
      ~label:"uniform_bind_group_layout"
      ~binding:0
      ~visibility:[ Wgpu.Shader_stage.Item.Vertex; Wgpu.Shader_stage.Item.Fragment ]
      ()
  in
  (* Create pipeline layout *)
  let pipeline_layout =
    Wgpu.Device.create_pipeline_layout
      device
      ~label:"uniforms_pipeline_layout"
      ~bind_group_layouts:[ bind_group_layout ]
      ()
  in
  (* Create render pipeline *)
  let pipeline =
    Wgpu.Device.create_render_pipeline
      device
      ~label:"uniforms_multiple_pipeline"
      ~shader_module:shader
      ~vertex_entry_point:"vs"
      ~fragment_entry_point:"fs"
      ~color_format:Wgpu.Texture_format.Rgba8_unorm
      ~layout:pipeline_layout
      ()
  in
  (* Create object infos with random colors and offsets *)
  let k_color_offset = 0 in
  let k_scale_offset = 4 in
  let k_offset_offset = 6 in
  let object_infos =
    List.init num_objects ~f:(fun i ->
      let uniform_buffer =
        Wgpu.Device.create_buffer
          device
          ~label:(sprintf "uniforms for obj: %d" i)
          ~size:(Int64.of_int uniform_buffer_size)
          ~usage:[ Wgpu.Buffer_usage.Item.Uniform; Wgpu.Buffer_usage.Item.Copy_dst ]
          ~mapped_at_creation:false
          ()
      in
      let uniform_values =
        Bigarray.Array1.create Bigarray.float32 Bigarray.c_layout num_uniform_floats
      in
      (* Random color *)
      Bigarray.Array1.set uniform_values (k_color_offset + 0) (Random.float 1.0);
      Bigarray.Array1.set uniform_values (k_color_offset + 1) (Random.float 1.0);
      Bigarray.Array1.set uniform_values (k_color_offset + 2) (Random.float 1.0);
      Bigarray.Array1.set uniform_values (k_color_offset + 3) 1.0;
      (* Random offset in [-0.9, 0.9] *)
      Bigarray.Array1.set uniform_values (k_offset_offset + 0) (rand ~min:(-0.9) ~max:0.9);
      Bigarray.Array1.set uniform_values (k_offset_offset + 1) (rand ~min:(-0.9) ~max:0.9);
      (* Scale will be set at render time *)
      Bigarray.Array1.set uniform_values (k_scale_offset + 0) 0.0;
      Bigarray.Array1.set uniform_values (k_scale_offset + 1) 0.0;
      let bind_group =
        Wgpu.Device.create_bind_group
          device
          ~label:(sprintf "bind group for obj: %d" i)
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
      let scale = rand ~min:0.2 ~max:0.5 in
      { scale; uniform_buffer; uniform_values; bind_group })
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
    Wgpu.begin_render_pass
      encoder
      ~label:"uniforms_multiple_pass"
      ~color_view:texture_view
      ~clear_color:(0.3, 0.3, 0.3, 1.0)
      ()
  in
  Wgpu.Render_pass_encoder.set_pipeline render_pass ~pipeline;
  (* Update and draw each object *)
  let aspect = Float.of_int width /. Float.of_int height in
  List.iter object_infos ~f:(fun { scale; uniform_buffer; uniform_values; bind_group } ->
    (* Set scale with aspect correction *)
    Bigarray.Array1.set uniform_values (k_scale_offset + 0) (scale /. aspect);
    Bigarray.Array1.set uniform_values (k_scale_offset + 1) scale;
    Wgpu.Queue.write_buffer queue ~buffer:uniform_buffer ~offset:0L ~data:uniform_values;
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
    let ppm_file = Test_util.output_path "simple_triangle_uniforms_multiple.ppm" in
    let png_file = Test_util.output_path "simple_triangle_uniforms_multiple.png" in
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
  List.iter object_infos ~f:(fun { uniform_buffer; bind_group; _ } ->
    Wgpu.Bind_group.release bind_group;
    Wgpu.Buffer.release uniform_buffer);
  Wgpu.Bind_group_layout.release bind_group_layout;
  Wgpu.Shader_module.release shader;
  Wgpu.Queue.release queue;
  Wgpu.Device.release device;
  Wgpu.Adapter.release adapter;
  Wgpu.Instance.release instance
;;
