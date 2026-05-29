(* WebGPU Fundamentals: Simple Textured Quad

   This test demonstrates basic texture creation and sampling. A 5x7 pixel texture
   containing a yellow "F" on a red background with a blue corner pixel is applied to a
   quad covering part of the screen.

   The texture is sampled using a simple sampler with nearest filtering, showing how
   texture coordinates work.
*)

open! Core

let width = 600
let height = 400
let bytes_per_pixel = 4
let bytes_per_row = ((width * bytes_per_pixel) + 255) / 256 * 256
let buffer_size = bytes_per_row * height
let texture_width = 5
let texture_height = 7

let shader_code =
  {|
struct OurVertexShaderOutput {
  @builtin(position) position: vec4f,
  @location(0) texcoord: vec2f,
};

@vertex fn vs(
  @builtin(vertex_index) vertexIndex : u32
) -> OurVertexShaderOutput {
  // Quad vertices covering top-right quadrant (in clip space, 0 to 1)
  let pos = array(
    // 1st triangle
    vec2f( 0.0,  0.0),  // center
    vec2f( 1.0,  0.0),  // right, center
    vec2f( 0.0,  1.0),  // center, top

    // 2nd triangle
    vec2f( 0.0,  1.0),  // center, top
    vec2f( 1.0,  0.0),  // right, center
    vec2f( 1.0,  1.0),  // right, top
  );

  var vsOutput: OurVertexShaderOutput;
  let xy = pos[vertexIndex];
  vsOutput.position = vec4f(xy, 0.0, 1.0);
  // Flip Y texture coordinate so texture appears right-side up
  vsOutput.texcoord = vec2f(xy.x, 1.0 - xy.y);
  return vsOutput;
}

@group(0) @binding(0) var ourSampler: sampler;
@group(0) @binding(1) var ourTexture: texture_2d<f32>;

@fragment fn fs(fsInput: OurVertexShaderOutput) -> @location(0) vec4f {
  return textureSample(ourTexture, ourSampler, fsInput.texcoord);
}
|}
;;

(* Create the F texture data - a 5x7 yellow F on red background with blue corner *)
let create_f_texture_data () =
  (* Colors in RGBA format *)
  let red = [| 255; 0; 0; 255 |] in
  let yellow = [| 255; 255; 0; 255 |] in
  let blue = [| 0; 0; 255; 255 |] in
  (* Pattern for the F (flipped for correct orientation) *)
  let pattern =
    [| (* Row 0 - bottom *)
       [| red; red; red; red; red |]
     ; (* Row 1 *)
       [| red; yellow; red; red; red |]
     ; (* Row 2 *)
       [| red; yellow; red; red; red |]
     ; (* Row 3 *)
       [| red; yellow; yellow; red; red |]
     ; (* Row 4 *)
       [| red; yellow; red; red; red |]
     ; (* Row 5 *)
       [| red; yellow; yellow; yellow; red |]
     ; (* Row 6 - top, with blue corner *)
       [| blue; red; red; red; red |]
    |]
  in
  let data =
    Bigarray.Array1.create
      Bigarray.int8_unsigned
      Bigarray.c_layout
      (texture_width * texture_height * 4)
  in
  for y = 0 to texture_height - 1 do
    for x = 0 to texture_width - 1 do
      let color = pattern.(y).(x) in
      let offset = ((y * texture_width) + x) * 4 in
      Bigarray.Array1.set data offset color.(0);
      Bigarray.Array1.set data (offset + 1) color.(1);
      Bigarray.Array1.set data (offset + 2) color.(2);
      Bigarray.Array1.set data (offset + 3) color.(3)
    done
  done;
  data
;;

let init () =
  let instance = Wgpu.Instance.create () in
  let adapter = Wgpu.Instance.request_adapter instance () in
  let device = Wgpu.Adapter.request_device adapter in
  let queue = Wgpu.Device.get_queue device in
  let shader =
    Wgpu.Device.create_shader_module
      device
      ~label:"textured_quad_shader"
      ~wgsl:shader_code
      ()
  in
  instance, adapter, device, queue, shader
;;

let () =
  let instance, adapter, device, queue, shader = init () in
  (* Create the F texture *)
  let texture_data = create_f_texture_data () in
  let texture =
    Wgpu.Device.create_texture
      device
      ~label:"yellow_f_on_red"
      ~size_width:texture_width
      ~size_height:texture_height
      ~size_depth_or_array_layers:1
      ~dimension:N2d
      ~mip_level_count:1
      ~sample_count:1
      ~format:Wgpu.Texture_format.Rgba8_unorm
      ~usage:[ Wgpu.Texture_usage.Item.Texture_binding; Wgpu.Texture_usage.Item.Copy_dst ]
      ()
  in
  (* Write texture data directly using Queue.write_texture *)
  Wgpu.Queue.write_texture
    queue
    ~destination_texture:texture
    ~destination_mip_level:0
    ~destination_origin_x:0
    ~destination_origin_y:0
    ~destination_origin_z:0
    ~destination_aspect:Wgpu.Texture_aspect.All
    ~data_layout_offset:0L
    ~data_layout_bytes_per_row:(texture_width * 4)
    ~data_layout_rows_per_image:texture_height
    ~write_size_width:texture_width
    ~write_size_height:texture_height
    ~write_size_depth_or_array_layers:1
    ~data:texture_data
    ();
  let f_texture_view = Wgpu.create_texture_view texture ~label:"f_texture_view" () in
  (* Create sampler with default (nearest) filtering *)
  let sampler =
    Wgpu.Device.create_sampler
      device
      ~label:"nearest_sampler"
      ~address_mode_u:Wgpu.Address_mode.Clamp_to_edge
      ~address_mode_v:Wgpu.Address_mode.Clamp_to_edge
      ~address_mode_w:Wgpu.Address_mode.Clamp_to_edge
      ~mag_filter:Wgpu.Filter_mode.Nearest
      ~min_filter:Wgpu.Filter_mode.Nearest
      ~mipmap_filter:Wgpu.Mipmap_filter_mode.Nearest
      ~lod_min_clamp:0.0
      ~lod_max_clamp:32.0
      ~compare:Wgpu.Compare_function.Undefined
      ~max_anisotropy:1
      ()
  in
  (* Create bind group layout for sampler and texture *)
  let bind_group_layout =
    Wgpu.Device.create_bind_group_layout
      device
      ~label:"texture_bind_group_layout"
      ~entries:
        [ (* Sampler at binding 0 *)
          Wgpu.Bind_group_layout_entry.create
            ~binding:0
            ~visibility:[ Wgpu.Shader_stage.Item.Fragment ]
            ~sampler:
              (Wgpu.Bind_group_layout_entry.Sampler_binding_layout.create
                 ~type_:Wgpu.Sampler_binding_type.Filtering
                 ())
            ()
        ; (* Texture at binding 1 *)
          Wgpu.Bind_group_layout_entry.create
            ~binding:1
            ~visibility:[ Wgpu.Shader_stage.Item.Fragment ]
            ~texture:
              (Wgpu.Bind_group_layout_entry.Texture_binding_layout.create
                 ~sample_type:Wgpu.Texture_sample_type.Float
                 ~view_dimension:Wgpu.Texture_view_dimension.N2d
                 ~multisampled:false
                 ())
            ()
        ]
      ()
  in
  let bind_group =
    Wgpu.Device.create_bind_group
      device
      ~label:"texture_bind_group"
      ~layout:bind_group_layout
      ~entries:
        [ Wgpu.Bind_group_entry.create ~binding:0 ~offset:0L ~size:0L ~sampler ()
        ; Wgpu.Bind_group_entry.create
            ~binding:1
            ~offset:0L
            ~size:0L
            ~texture_view:f_texture_view
            ()
        ]
      ()
  in
  let pipeline_layout =
    Wgpu.Device.create_pipeline_layout
      device
      ~label:"textured_quad_pipeline_layout"
      ~bind_group_layouts:[ bind_group_layout ]
      ()
  in
  (* Create render pipeline *)
  let pipeline =
    Wgpu.Device.create_render_pipeline
      device
      ~label:"textured_quad_pipeline"
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
  (* Create render target *)
  let render_texture =
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
  let render_texture_view =
    Wgpu.create_texture_view render_texture ~label:"render_target_view" ()
  in
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
      ~label:"textured_quad_pass"
      ~color_attachments:
        [ Wgpu.Render_pass_color_attachment.create
            ~view:render_texture_view
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
      ()
  in
  Wgpu.Render_pass_encoder.set_pipeline render_pass ~pipeline;
  Wgpu.set_bind_group_render render_pass ~index:0 ~bind_group;
  Wgpu.Render_pass_encoder.draw
    render_pass
    ~vertex_count:6
    ~instance_count:1
    ~first_vertex:0
    ~first_instance:0;
  Wgpu.Render_pass_encoder.end_ render_pass;
  Wgpu.copy_texture_to_buffer
    encoder
    ~texture:render_texture
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
    let ppm_file = Test_util.output_path "simple_textured_quad.ppm" in
    let png_file = Test_util.output_path "simple_textured_quad.png" in
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
  Wgpu.Texture_view.release render_texture_view;
  Wgpu.Texture.release render_texture;
  Wgpu.Render_pipeline.release pipeline;
  Wgpu.Pipeline_layout.release pipeline_layout;
  Wgpu.Bind_group.release bind_group;
  Wgpu.Bind_group_layout.release bind_group_layout;
  Wgpu.Sampler.release sampler;
  Wgpu.Texture_view.release f_texture_view;
  Wgpu.Texture.release texture;
  Wgpu.Shader_module.release shader;
  Wgpu.Queue.release queue;
  Wgpu.Device.release device;
  Wgpu.Adapter.release adapter;
  Wgpu.Instance.release instance
;;
