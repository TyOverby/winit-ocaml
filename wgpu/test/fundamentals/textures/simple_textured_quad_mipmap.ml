(*
   WebGPU Fundamentals: Textured Quad with Mipmaps

   This test demonstrates mipmap generation and usage:
   - Creating textures with multiple mip levels
   - Generating mip levels via bilinear filtering
   - Using mipmapFilter for smooth mip level transitions

   We display a texture mapped onto a quad that recedes into the distance
   to show how different mip levels are selected based on screen coverage.
*)

open! Core

let width = 600
let height = 400
let bytes_per_pixel = 4
let bytes_per_row = ((width * bytes_per_pixel) + 255) / 256 * 256
let buffer_size = bytes_per_row * height

(* 16x16 texture that will have 5 mip levels: 16, 8, 4, 2, 1 *)
let base_texture_size = 16

let shader_code =
  {|
struct OurVertexShaderOutput {
  @builtin(position) position: vec4f,
  @location(0) texcoord: vec2f,
};

struct Uniforms {
  matrix: mat4x4f,
};

@group(0) @binding(0) var ourSampler: sampler;
@group(0) @binding(1) var ourTexture: texture_2d<f32>;
@group(0) @binding(2) var<uniform> uniforms: Uniforms;

@vertex fn vs(
  @builtin(vertex_index) vertexIndex : u32
) -> OurVertexShaderOutput {
  // Unit quad
  let pos = array(
    vec2f( 0.0,  0.0),
    vec2f( 1.0,  0.0),
    vec2f( 0.0,  1.0),
    vec2f( 0.0,  1.0),
    vec2f( 1.0,  0.0),
    vec2f( 1.0,  1.0),
  );

  var vsOutput: OurVertexShaderOutput;
  let xy = pos[vertexIndex];
  vsOutput.position = uniforms.matrix * vec4f(xy, 0.0, 1.0);
  // Stretch texture coordinates to see mip selection along the plane
  vsOutput.texcoord = xy * vec2f(1.0, 50.0);
  return vsOutput;
}

@fragment fn fs(fsInput: OurVertexShaderOutput) -> @location(0) vec4f {
  return textureSample(ourTexture, ourSampler, fsInput.texcoord);
}
|}
;;

(* Linear interpolation *)
let lerp a b t = a +. ((b -. a) *. t)

(* Bilinear filter for generating mipmaps *)
let bilinear_filter ~src ~src_width ~src_height ~dst_width ~dst_height =
  let dst =
    Bigarray.Array1.create
      Bigarray.int8_unsigned
      Bigarray.c_layout
      (dst_width * dst_height * 4)
  in
  let get_src_pixel x y =
    let x = Int.min x (src_width - 1) in
    let y = Int.min y (src_height - 1) in
    let offset = ((y * src_width) + x) * 4 in
    ( Bigarray.Array1.get src offset
    , Bigarray.Array1.get src (offset + 1)
    , Bigarray.Array1.get src (offset + 2)
    , Bigarray.Array1.get src (offset + 3) )
  in
  for y = 0 to dst_height - 1 do
    for x = 0 to dst_width - 1 do
      (* Compute texcoord of destination texel center *)
      let u = (Float.of_int x +. 0.5) /. Float.of_int dst_width in
      let v = (Float.of_int y +. 0.5) /. Float.of_int dst_height in
      (* Map to source coordinates *)
      let au = (u *. Float.of_int src_width) -. 0.5 in
      let av = (v *. Float.of_int src_height) -. 0.5 in
      let tx = Int.max 0 (Float.to_int au) in
      let ty = Int.max 0 (Float.to_int av) in
      let t1 = Float.mod_float au 1.0 in
      let t2 = Float.mod_float av 1.0 in
      (* Get 4 source pixels *)
      let r0, g0, b0, a0 = get_src_pixel tx ty in
      let r1, g1, b1, a1 = get_src_pixel (tx + 1) ty in
      let r2, g2, b2, a2 = get_src_pixel tx (ty + 1) in
      let r3, g3, b3, a3 = get_src_pixel (tx + 1) (ty + 1) in
      (* Bilinear interpolation *)
      let interp c0 c1 c2 c3 =
        let top = lerp (Float.of_int c0) (Float.of_int c1) t1 in
        let bot = lerp (Float.of_int c2) (Float.of_int c3) t1 in
        Int.of_float (lerp top bot t2)
      in
      let r = interp r0 r1 r2 r3 in
      let g = interp g0 g1 g2 g3 in
      let b = interp b0 b1 b2 b3 in
      let a = interp a0 a1 a2 a3 in
      let offset = ((y * dst_width) + x) * 4 in
      Bigarray.Array1.set dst offset r;
      Bigarray.Array1.set dst (offset + 1) g;
      Bigarray.Array1.set dst (offset + 2) b;
      Bigarray.Array1.set dst (offset + 3) a
    done
  done;
  dst
;;

(* Create a blended mipmap texture with a colorful pattern *)
let create_blended_mipmap () =
  let w = [| 255; 255; 255; 255 |] in
  (* white *)
  let r = [| 255; 0; 0; 255 |] in
  (* red *)
  let b = [| 0; 28; 116; 255 |] in
  (* blue *)
  let y = [| 255; 231; 0; 255 |] in
  (* yellow *)
  let g = [| 58; 181; 75; 255 |] in
  (* green *)
  let a = [| 38; 123; 167; 255 |] in
  (* aqua *)
  let pattern =
    [| [| w; r; r; r; r; r; r; a; a; r; r; r; r; r; r; w |]
     ; [| w; w; r; r; r; r; r; a; a; r; r; r; r; r; w; w |]
     ; [| w; w; w; r; r; r; r; a; a; r; r; r; r; w; w; w |]
     ; [| w; w; w; w; r; r; r; a; a; r; r; r; w; w; w; w |]
     ; [| w; w; w; w; w; r; r; a; a; r; r; w; w; w; w; w |]
     ; [| w; w; w; w; w; w; r; a; a; r; w; w; w; w; w; w |]
     ; [| w; w; w; w; w; w; w; a; a; w; w; w; w; w; w; w |]
     ; [| b; b; b; b; b; b; b; b; a; y; y; y; y; y; y; y |]
     ; [| b; b; b; b; b; b; b; g; y; y; y; y; y; y; y; y |]
     ; [| w; w; w; w; w; w; w; g; g; w; w; w; w; w; w; w |]
     ; [| w; w; w; w; w; w; r; g; g; r; w; w; w; w; w; w |]
     ; [| w; w; w; w; w; r; r; g; g; r; r; w; w; w; w; w |]
     ; [| w; w; w; w; r; r; r; g; g; r; r; r; w; w; w; w |]
     ; [| w; w; w; r; r; r; r; g; g; r; r; r; r; w; w; w |]
     ; [| w; w; r; r; r; r; r; g; g; r; r; r; r; r; w; w |]
     ; [| w; r; r; r; r; r; r; g; g; r; r; r; r; r; r; w |]
    |]
  in
  let base_data =
    Bigarray.Array1.create
      Bigarray.int8_unsigned
      Bigarray.c_layout
      (base_texture_size * base_texture_size * 4)
  in
  for py = 0 to base_texture_size - 1 do
    for px = 0 to base_texture_size - 1 do
      let color = pattern.(py).(px) in
      let offset = ((py * base_texture_size) + px) * 4 in
      Bigarray.Array1.set base_data offset color.(0);
      Bigarray.Array1.set base_data (offset + 1) color.(1);
      Bigarray.Array1.set base_data (offset + 2) color.(2);
      Bigarray.Array1.set base_data (offset + 3) color.(3)
    done
  done;
  (* Generate mip levels *)
  let rec generate_mips mips current_data current_w current_h =
    if current_w <= 1 && current_h <= 1
    then List.rev mips
    else (
      let next_w = Int.max 1 (current_w / 2) in
      let next_h = Int.max 1 (current_h / 2) in
      let next_data =
        bilinear_filter
          ~src:current_data
          ~src_width:current_w
          ~src_height:current_h
          ~dst_width:next_w
          ~dst_height:next_h
      in
      generate_mips ((next_data, next_w, next_h) :: mips) next_data next_w next_h)
  in
  let mip_0 = base_data, base_texture_size, base_texture_size in
  let mips = generate_mips [ mip_0 ] base_data base_texture_size base_texture_size in
  mips
;;

let upload_mip_levels ~device:_ ~queue ~texture ~mips =
  List.iteri mips ~f:(fun mip_level (mip_data, mip_width, mip_height) ->
    (* Write mip level data directly using Queue.write_texture *)
    Wgpu.Queue.write_texture
      queue
      ~destination_texture:texture
      ~destination_mip_level:mip_level
      ~destination_origin_x:0
      ~destination_origin_y:0
      ~destination_origin_z:0
      ~destination_aspect:Wgpu.Texture_aspect.All
      ~data_layout_offset:0L
      ~data_layout_bytes_per_row:(mip_width * 4)
      ~data_layout_rows_per_image:mip_height
      ~write_size_width:mip_width
      ~write_size_height:mip_height
      ~write_size_depth_or_array_layers:1
      ~data:mip_data
      ())
;;

(* Create a simple 2D scale+offset matrix that stretches and positions the quad *)
let create_2d_transform_matrix ~scale_x ~scale_y ~offset_x ~offset_y =
  (* This creates a matrix that transforms the unit quad [0,1]x[0,1] to
     screen clip space [-1,1]x[-1,1], with optional scale and offset *)
  Gg.M4.v
    scale_x
    0.0
    0.0
    offset_x
    (* col 0 *)
    0.0
    scale_y
    0.0
    offset_y
    (* col 1 *)
    0.0
    0.0
    1.0
    0.0
    (* col 2 *)
    0.0
    0.0
    0.0
    1.0
;;

let matrix_to_bigarray m =
  let data = Bigarray.Array1.create Bigarray.float32 Bigarray.c_layout 16 in
  (* Gg stores matrices transposed relative to WebGPU's expected column-major format.
     We transpose when uploading to WebGPU. *)
  for col = 0 to 3 do
    for row = 0 to 3 do
      let value = Gg.M4.el row col m in
      (* Note: swapped row and col to transpose *)
      Bigarray.Array1.set data ((col * 4) + row) value
    done
  done;
  data
;;

let uniform_buffer_size = 16 * 4 (* mat4x4f = 16 floats = 64 bytes *)

let init () =
  let instance = Wgpu.Instance.create () in
  let adapter = Wgpu.Instance.request_adapter instance () in
  let device = Wgpu.Adapter.request_device adapter in
  let queue = Wgpu.Device.get_queue device in
  let shader =
    Wgpu.Device.create_shader_module
      device
      ~label:"textured_quad_mipmap_shader"
      ~wgsl:shader_code
      ()
  in
  instance, adapter, device, queue, shader
;;

let () =
  let instance, adapter, device, queue, shader = init () in
  (* Generate mipmaps *)
  let mips = create_blended_mipmap () in
  let num_mip_levels = List.length mips in
  (* Create texture with mip levels *)
  let texture =
    Wgpu.Device.create_texture
      device
      ~label:"mipmap_texture"
      ~size_width:base_texture_size
      ~size_height:base_texture_size
      ~size_depth_or_array_layers:1
      ~dimension:N2d
      ~mip_level_count:num_mip_levels
      ~sample_count:1
      ~format:Wgpu.Texture_format.Rgba8_unorm
      ~usage:[ Wgpu.Texture_usage.Item.Texture_binding; Wgpu.Texture_usage.Item.Copy_dst ]
      ()
  in
  upload_mip_levels ~device ~queue ~texture ~mips;
  let texture_view = Wgpu.create_texture_view texture ~label:"mipmap_texture_view" () in
  (* Create sampler with linear mipmap filtering *)
  let sampler =
    Wgpu.Device.create_sampler
      device
      ~label:"mipmap_sampler"
      ~address_mode_u:Wgpu.Address_mode.Repeat
      ~address_mode_v:Wgpu.Address_mode.Repeat
      ~address_mode_w:Wgpu.Address_mode.Clamp_to_edge
      ~mag_filter:Wgpu.Filter_mode.Linear
      ~min_filter:Wgpu.Filter_mode.Linear
      ~mipmap_filter:Wgpu.Mipmap_filter_mode.Linear
      ~lod_min_clamp:0.0
      ~lod_max_clamp:(Float.of_int num_mip_levels)
      ~compare:Wgpu.Compare_function.Undefined
      ~max_anisotropy:1
      ()
  in
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
  (* Create bind group layout *)
  let bind_group_layout =
    Wgpu.Device.create_bind_group_layout
      device
      ~label:"mipmap_bind_group_layout"
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
  let bind_group =
    Wgpu.Device.create_bind_group
      device
      ~label:"mipmap_bind_group"
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
          ; texture_view = Some texture_view
          }
        ; { Wgpu.Bind_group_entry.binding = 2
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
      ~label:"mipmap_pipeline_layout"
      ~bind_group_layouts:[ bind_group_layout ]
      ()
  in
  let pipeline =
    Wgpu.Device.create_render_pipeline
      device
      ~label:"mipmap_pipeline"
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
  (* Create a simple 2D transform that fills most of the screen.
     The shader stretches texture coordinates by 50 in Y, which will cause
     different mip levels to be selected across the quad. *)
  let matrix =
    create_2d_transform_matrix ~scale_x:1.8 ~scale_y:1.8 ~offset_x:(-0.9) ~offset_y:(-0.9)
  in
  let matrix_data = matrix_to_bigarray matrix in
  Wgpu.Queue.write_buffer queue ~buffer:uniform_buffer ~offset:0L ~data:matrix_data;
  (* Render *)
  let encoder = Wgpu.Device.create_command_encoder device ~label:"render_encoder" () in
  let render_pass =
    Wgpu.begin_render_pass_simple
      encoder
      ~label:"mipmap_pass"
      ~color_view:render_texture_view
      ~clear_color:(0.3, 0.3, 0.3, 1.0)
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
    let ppm_file = Test_util.output_path "simple_textured_quad_mipmap.ppm" in
    let png_file = Test_util.output_path "simple_textured_quad_mipmap.png" in
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
  Wgpu.Buffer.release uniform_buffer;
  Wgpu.Sampler.release sampler;
  Wgpu.Texture_view.release texture_view;
  Wgpu.Texture.release texture;
  Wgpu.Shader_module.release shader;
  Wgpu.Queue.release queue;
  Wgpu.Device.release device;
  Wgpu.Adapter.release adapter;
  Wgpu.Instance.release instance
;;
