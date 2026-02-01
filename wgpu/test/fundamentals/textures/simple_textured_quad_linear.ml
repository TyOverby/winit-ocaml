(*
   WebGPU Fundamentals: Textured Quad with Linear Filtering

   This test demonstrates different sampler settings:
   - Linear mag filter (smooths magnification)
   - Different address modes (repeat vs clamp-to-edge)

   We draw multiple quads showing different combinations to illustrate
   how these settings affect texture sampling.
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

struct Uniforms {
  offset: vec2f,
  scale: vec2f,
};

@group(0) @binding(0) var ourSampler: sampler;
@group(0) @binding(1) var ourTexture: texture_2d<f32>;
@group(0) @binding(2) var<uniform> uniforms: Uniforms;

@vertex fn vs(
  @builtin(vertex_index) vertexIndex : u32
) -> OurVertexShaderOutput {
  // Quad vertices (unit quad)
  let pos = array(
    // 1st triangle
    vec2f( 0.0,  0.0),
    vec2f( 1.0,  0.0),
    vec2f( 0.0,  1.0),

    // 2nd triangle
    vec2f( 0.0,  1.0),
    vec2f( 1.0,  0.0),
    vec2f( 1.0,  1.0),
  );

  var vsOutput: OurVertexShaderOutput;
  let xy = pos[vertexIndex];
  // Apply scale and offset
  vsOutput.position = vec4f(xy * uniforms.scale + uniforms.offset, 0.0, 1.0);
  // Flip Y and apply UV scale to show repeat behavior
  vsOutput.texcoord = vec2f(xy.x * 2.0, (1.0 - xy.y) * 2.0);
  return vsOutput;
}

@fragment fn fs(fsInput: OurVertexShaderOutput) -> @location(0) vec4f {
  return textureSample(ourTexture, ourSampler, fsInput.texcoord);
}
|}
;;

(* Create the F texture data - same as the basic test *)
let create_f_texture_data () =
  let red = [| 255; 0; 0; 255 |] in
  let yellow = [| 255; 255; 0; 255 |] in
  let blue = [| 0; 0; 255; 255 |] in
  let pattern =
    [| [| red; red; red; red; red |]
     ; [| red; yellow; red; red; red |]
     ; [| red; yellow; red; red; red |]
     ; [| red; yellow; yellow; red; red |]
     ; [| red; yellow; red; red; red |]
     ; [| red; yellow; yellow; yellow; red |]
     ; [| blue; red; red; red; red |]
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

let upload_texture ~device:_ ~queue ~texture ~texture_data =
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
    ()
;;

type sampler_config =
  { address_u : Wgpu.Address_mode.t
  ; address_v : Wgpu.Address_mode.t
  ; mag_filter : Wgpu.Filter_mode.t
  ; min_filter : Wgpu.Filter_mode.t
  }

(* Grid of 4 quads showing different filter combinations:
   Top-left: nearest + clamp
   Top-right: linear + clamp
   Bottom-left: nearest + repeat
   Bottom-right: linear + repeat *)
let sampler_configs =
  [| (* nearest + clamp *)
     { address_u = Wgpu.Address_mode.Clamp_to_edge
     ; address_v = Wgpu.Address_mode.Clamp_to_edge
     ; mag_filter = Wgpu.Filter_mode.Nearest
     ; min_filter = Wgpu.Filter_mode.Nearest
     }
   ; (* linear + clamp *)
     { address_u = Wgpu.Address_mode.Clamp_to_edge
     ; address_v = Wgpu.Address_mode.Clamp_to_edge
     ; mag_filter = Wgpu.Filter_mode.Linear
     ; min_filter = Wgpu.Filter_mode.Linear
     }
   ; (* nearest + repeat *)
     { address_u = Wgpu.Address_mode.Repeat
     ; address_v = Wgpu.Address_mode.Repeat
     ; mag_filter = Wgpu.Filter_mode.Nearest
     ; min_filter = Wgpu.Filter_mode.Nearest
     }
   ; (* linear + repeat *)
     { address_u = Wgpu.Address_mode.Repeat
     ; address_v = Wgpu.Address_mode.Repeat
     ; mag_filter = Wgpu.Filter_mode.Linear
     ; min_filter = Wgpu.Filter_mode.Linear
     }
  |]
;;

let uniform_buffer_size = 4 * 4 (* 2 vec2f = 4 floats = 16 bytes *)

let init () =
  let instance = Wgpu.Instance.create () in
  let adapter = Wgpu.Instance.request_adapter instance () in
  let device = Wgpu.Adapter.request_device adapter in
  let queue = Wgpu.Device.get_queue device in
  let shader =
    Wgpu.Device.create_shader_module
      device
      ~label:"textured_quad_linear_shader"
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
  upload_texture ~device ~queue ~texture ~texture_data;
  let f_texture_view = Wgpu.create_texture_view texture ~label:"f_texture_view" () in
  (* Create samplers for each configuration *)
  let samplers =
    Array.map sampler_configs ~f:(fun config ->
      Wgpu.Device.create_sampler
        device
        ~label:"sampler"
        ~address_mode_u:config.address_u
        ~address_mode_v:config.address_v
        ~address_mode_w:Wgpu.Address_mode.Clamp_to_edge
        ~mag_filter:config.mag_filter
        ~min_filter:config.min_filter
        ~mipmap_filter:Wgpu.Mipmap_filter_mode.Nearest
        ~lod_min_clamp:0.0
        ~lod_max_clamp:32.0
        ~compare:Wgpu.Compare_function.Undefined
        ~max_anisotropy:1
        ())
  in
  (* Create uniform buffer for offset/scale *)
  let uniform_buffer =
    Wgpu.Device.create_buffer
      device
      ~label:"uniform_buffer"
      ~size:(Int64.of_int uniform_buffer_size)
      ~usage:[ Wgpu.Buffer_usage.Item.Uniform; Wgpu.Buffer_usage.Item.Copy_dst ]
      ~mapped_at_creation:false
      ()
  in
  (* Create bind group layout *)
  let bind_group_layout =
    Wgpu.Device.create_bind_group_layout
      device
      ~label:"texture_bind_group_layout"
      ~entries:
        [ { Wgpu.Bind_group_layout_entry.binding = 0
          ; visibility = [ Wgpu.Shader_stage.Item.Fragment ]
          ; buffer = None
          ; sampler =
              Some
                { Wgpu.Bind_group_layout_entry.Sampler_binding_layout.type_ =
                    Wgpu.Sampler_binding_type.Filtering
                }
          ; texture = None
          ; storage_texture = None
          }
        ; { Wgpu.Bind_group_layout_entry.binding = 1
          ; visibility = [ Wgpu.Shader_stage.Item.Fragment ]
          ; buffer = None
          ; sampler = None
          ; texture =
              Some
                { Wgpu.Bind_group_layout_entry.Texture_binding_layout.sample_type =
                    Wgpu.Texture_sample_type.Float
                ; view_dimension = Wgpu.Texture_view_dimension.N2d
                ; multisampled = false
                }
          ; storage_texture = None
          }
        ; { Wgpu.Bind_group_layout_entry.binding = 2
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
  (* Create bind groups for each sampler *)
  let bind_groups =
    Array.map samplers ~f:(fun sampler ->
      Wgpu.Device.create_bind_group
        device
        ~label:"texture_bind_group"
        ~layout:bind_group_layout
        ~entries:
          [ { Wgpu.Bind_group_entry.binding = 0
            ; buffer = None
            ; offset = 0L
            ; size = 0L
            ; sampler = Some sampler
            ; texture_view = None
            }
          ; { Wgpu.Bind_group_entry.binding = 1
            ; buffer = None
            ; offset = 0L
            ; size = 0L
            ; sampler = None
            ; texture_view = Some f_texture_view
            }
          ; { Wgpu.Bind_group_entry.binding = 2
            ; buffer = Some uniform_buffer
            ; offset = 0L
            ; size = Int64.of_int uniform_buffer_size
            ; sampler = None
            ; texture_view = None
            }
          ]
        ())
  in
  let pipeline_layout =
    Wgpu.Device.create_pipeline_layout
      device
      ~label:"textured_quad_pipeline_layout"
      ~bind_group_layouts:[ bind_group_layout ]
      ()
  in
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
  (* Render 4 quads in a 2x2 grid *)
  let encoder = Wgpu.Device.create_command_encoder device ~label:"render_encoder" () in
  let render_pass =
    Wgpu.Command_encoder.begin_render_pass
      encoder
      ~label:"textured_quad_pass"
      ~color_attachments:
        [ { view = Some render_texture_view
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
  (* Draw each quad with its sampler configuration *)
  let quad_positions =
    [| -1.0, 0.0 (* top-left *)
     ; 0.0, 0.0 (* top-right *)
     ; -1.0, -1.0 (* bottom-left *)
     ; 0.0, -1.0 (* bottom-right *)
    |]
  in
  let uniform_data = Bigarray.Array1.create Bigarray.float32 Bigarray.c_layout 4 in
  Array.iteri bind_groups ~f:(fun i bind_group ->
    let offset_x, offset_y = quad_positions.(i) in
    (* Set uniforms: offset and scale *)
    Bigarray.Array1.set uniform_data 0 offset_x;
    Bigarray.Array1.set uniform_data 1 offset_y;
    Bigarray.Array1.set uniform_data 2 0.95;
    (* scale x - slightly smaller than 1 for gap *)
    Bigarray.Array1.set uniform_data 3 0.95;
    (* scale y *)
    Wgpu.Queue.write_buffer queue ~buffer:uniform_buffer ~offset:0L ~data:uniform_data;
    Wgpu.Device.poll device ~wait:true ();
    Wgpu.set_bind_group_render render_pass ~index:0 ~bind_group;
    Wgpu.Render_pass_encoder.draw
      render_pass
      ~vertex_count:6
      ~instance_count:1
      ~first_vertex:0
      ~first_instance:0);
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
    let ppm_file = Test_util.output_path "simple_textured_quad_linear.ppm" in
    let png_file = Test_util.output_path "simple_textured_quad_linear.png" in
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
  Array.iter bind_groups ~f:Wgpu.Bind_group.release;
  Wgpu.Bind_group_layout.release bind_group_layout;
  Wgpu.Buffer.release uniform_buffer;
  Array.iter samplers ~f:Wgpu.Sampler.release;
  Wgpu.Texture_view.release f_texture_view;
  Wgpu.Texture.release texture;
  Wgpu.Shader_module.release shader;
  Wgpu.Queue.release queue;
  Wgpu.Device.release device;
  Wgpu.Adapter.release adapter;
  Wgpu.Instance.release instance
;;
