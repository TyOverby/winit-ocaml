(*
   WebGPU Fundamentals: Skybox

   This test demonstrates cubemap textures and skybox rendering:
   - Creating a 6-layer texture for the cubemap faces
   - Using texture_cube in the shader to sample from the cubemap
   - Computing view direction from inverse view-projection matrix
   - Rendering a fullscreen triangle at far z to show the "environment"

   The skybox uses procedurally generated colors per face so we can
   easily verify the cubemap is working correctly:
   - +X (right): Red
   - -X (left): Cyan
   - +Y (up): Green
   - -Y (down): Magenta
   - +Z (front): Blue
   - -Z (back): Yellow
*)

open! Core

let width = 600
let height = 400
let bytes_per_pixel = 4
let bytes_per_row = ((width * bytes_per_pixel) + 255) / 256 * 256
let buffer_size = bytes_per_row * height

(* Cubemap face size - a small size is fine for solid colors *)
let cubemap_face_size = 64

let shader_code =
  {|
struct Uniforms {
  viewDirectionProjectionInverse: mat4x4f,
};

struct VSOutput {
  @builtin(position) position: vec4f,
  @location(0) pos: vec4f,
};

@group(0) @binding(0) var<uniform> uni: Uniforms;
@group(0) @binding(1) var ourSampler: sampler;
@group(0) @binding(2) var ourTexture: texture_cube<f32>;

@vertex fn vs(@builtin(vertex_index) vNdx: u32) -> VSOutput {
  // Fullscreen triangle - covers clip space with 3 vertices
  let pos = array(
    vec2f(-1, 3),
    vec2f(-1,-1),
    vec2f( 3,-1),
  );
  var vsOut: VSOutput;
  // z=1 places the triangle at the far plane
  vsOut.position = vec4f(pos[vNdx], 1, 1);
  vsOut.pos = vsOut.position;
  return vsOut;
}

@fragment fn fs(vsOut: VSOutput) -> @location(0) vec4f {
  // Transform clip-space position back to world direction using
  // the inverse view-direction-projection matrix
  let t = uni.viewDirectionProjectionInverse * vsOut.pos;
  // Normalize to get direction, flip Z for coordinate system
  return textureSample(ourTexture, ourSampler, normalize(t.xyz / t.w) * vec3f(1, 1, -1));
}
|}
;;

(* Create a solid-color face for the cubemap *)
let create_face_data ~r ~g ~b =
  let size = cubemap_face_size * cubemap_face_size * 4 in
  let data = Bigarray.Array1.create Bigarray.int8_unsigned Bigarray.c_layout size in
  for y = 0 to cubemap_face_size - 1 do
    for x = 0 to cubemap_face_size - 1 do
      let offset = ((y * cubemap_face_size) + x) * 4 in
      Bigarray.Array1.set data offset r;
      Bigarray.Array1.set data (offset + 1) g;
      Bigarray.Array1.set data (offset + 2) b;
      Bigarray.Array1.set data (offset + 3) 255
    done
  done;
  data
;;

(* Perspective projection matrix *)
let perspective_matrix ~fov_y ~aspect ~z_near ~z_far =
  let f = 1.0 /. Float.tan (fov_y /. 2.0) in
  let nf = 1.0 /. (z_near -. z_far) in
  Gg.M4.v
    (f /. aspect)
    0.0
    0.0
    0.0
    0.0
    f
    0.0
    0.0
    0.0
    0.0
    ((z_far +. z_near) *. nf)
    (2.0 *. z_far *. z_near *. nf)
    0.0
    0.0
    (-1.0)
    0.0
;;

(* Look-at view matrix *)
let look_at_matrix ~eye ~target ~up =
  let open Gg in
  let z = V3.unit (V3.sub eye target) in
  let x = V3.unit (V3.cross up z) in
  let y = V3.cross z x in
  (* View matrix = inverse of camera transform *)
  let ex = -.V3.dot x eye in
  let ey = -.V3.dot y eye in
  let ez = -.V3.dot z eye in
  M4.v
    (V3.x x)
    (V3.y x)
    (V3.z x)
    ex
    (V3.x y)
    (V3.y y)
    (V3.z y)
    ey
    (V3.x z)
    (V3.y z)
    (V3.z z)
    ez
    0.0
    0.0
    0.0
    1.0
;;

(* Convert matrix to bigarray for upload to GPU.
   Gg stores matrices row-major, WebGPU expects column-major,
   so we transpose during upload. *)
let matrix_to_bigarray m =
  let data = Bigarray.Array1.create Bigarray.float32 Bigarray.c_layout 16 in
  for col = 0 to 3 do
    for row = 0 to 3 do
      let value = Gg.M4.el row col m in
      Bigarray.Array1.set data ((col * 4) + row) value
    done
  done;
  data
;;

let uniform_buffer_size = 16 * 4 (* mat4x4f = 64 bytes *)

let init () =
  let instance = Wgpu.Instance.create () in
  let adapter = Wgpu.Instance.request_adapter instance () in
  let device = Wgpu.Adapter.request_device adapter in
  let queue = Wgpu.Device.get_queue device in
  let shader =
    Wgpu.Device.create_shader_module device ~label:"skybox_shader" ~wgsl:shader_code ()
  in
  instance, adapter, device, queue, shader
;;

let render_frame ~device ~queue ~pipeline ~bind_group ~angle ~output_name =
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
      ~label:"skybox_pass"
      ~color_view:texture_view
      ~clear_color:(0.0, 0.0, 0.0, 1.0)
      ()
  in
  Wgpu.Render_pass_encoder.set_pipeline render_pass ~pipeline;
  Wgpu.set_bind_group_render render_pass ~index:0 ~bind_group;
  (* Draw 3 vertices for the fullscreen triangle *)
  Wgpu.Render_pass_encoder.draw
    render_pass
    ~vertex_count:3
    ~instance_count:1
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
    let suffix = sprintf "_%ddeg" (Float.to_int (angle *. 180.0 /. Float.pi)) in
    let ppm_file = Test_util.output_path ("skybox" ^ suffix ^ ".ppm") in
    let png_file = Test_util.output_path ("skybox" ^ output_name ^ ".png") in
    Test_util.write_ppm ~filename:ppm_file ~width ~height ~data:mapped_data ~bytes_per_row;
    Test_util.ppm_to_png ~ppm_file ~png_file;
    ()
  in
  Wgpu.Buffer.unmap readback_buffer;
  (* Cleanup frame resources *)
  Wgpu.Command_buffer.release command_buffer;
  Wgpu.Render_pass_encoder.release render_pass;
  Wgpu.Command_encoder.release encoder;
  Wgpu.Buffer.release readback_buffer;
  Wgpu.Texture_view.release texture_view;
  Wgpu.Texture.release texture
;;

let () =
  let instance, adapter, device, queue, shader = init () in
  (* Create cubemap texture with 6 layers, one per face *)
  let cubemap_texture =
    Wgpu.Device.create_texture
      device
      ~label:"cubemap"
      ~size_width:cubemap_face_size
      ~size_height:cubemap_face_size
      ~size_depth_or_array_layers:6
      ~dimension:N2d
      ~mip_level_count:1
      ~sample_count:1
      ~format:Wgpu.Texture_format.Rgba8_unorm
      ~usage:[ Wgpu.Texture_usage.Item.Texture_binding; Wgpu.Texture_usage.Item.Copy_dst ]
      ()
  in
  (* Upload face data: +X, -X, +Y, -Y, +Z, -Z *)
  let faces =
    [ 255, 0, 0 (* +X: Red *)
    ; 0, 255, 255 (* -X: Cyan *)
    ; 0, 255, 0 (* +Y: Green *)
    ; 255, 0, 255 (* -Y: Magenta *)
    ; 0, 0, 255 (* +Z: Blue *)
    ; 255, 255, 0 (* -Z: Yellow *)
    ]
  in
  List.iteri faces ~f:(fun layer (r, g, b) ->
    let face_data = create_face_data ~r ~g ~b in
    Wgpu.Queue.write_texture
      queue
      ~destination_texture:cubemap_texture
      ~destination_mip_level:0
      ~destination_origin_x:0
      ~destination_origin_y:0
      ~destination_origin_z:layer
      ~destination_aspect:Wgpu.Texture_aspect.All
      ~data_layout_offset:0L
      ~data_layout_bytes_per_row:(cubemap_face_size * 4)
      ~data_layout_rows_per_image:cubemap_face_size
      ~write_size_width:cubemap_face_size
      ~write_size_height:cubemap_face_size
      ~write_size_depth_or_array_layers:1
      ~data:face_data
      ());
  (* Create cube texture view *)
  let cubemap_view =
    Wgpu.create_texture_view
      cubemap_texture
      ~label:"cubemap_view"
      ~dimension:Wgpu.Texture_view_dimension.Cube
      ()
  in
  (* Create sampler *)
  let sampler =
    Wgpu.Device.create_sampler
      device
      ~label:"cubemap_sampler"
      ~address_mode_u:Wgpu.Address_mode.Clamp_to_edge
      ~address_mode_v:Wgpu.Address_mode.Clamp_to_edge
      ~address_mode_w:Wgpu.Address_mode.Clamp_to_edge
      ~mag_filter:Wgpu.Filter_mode.Linear
      ~min_filter:Wgpu.Filter_mode.Linear
      ~mipmap_filter:Wgpu.Mipmap_filter_mode.Nearest
      ~lod_min_clamp:0.0
      ~lod_max_clamp:1.0
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
      ~label:"skybox_bind_group_layout"
      ~entries:
        [ (* Uniform buffer *)
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
        ; (* Sampler *)
          { Wgpu.Bind_group_layout_entry.binding = 1
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
        ; (* Cubemap texture *)
          { Wgpu.Bind_group_layout_entry.binding = 2
          ; visibility = [ Wgpu.Shader_stage.Item.Fragment ]
          ; buffer = None
          ; sampler = None
          ; texture =
              Some
                { Wgpu.Bind_group_layout_entry.Texture_binding_layout.sample_type =
                    Wgpu.Texture_sample_type.Float
                ; view_dimension = Wgpu.Texture_view_dimension.Cube
                ; multisampled = false
                }
          ; storage_texture = None
          }
        ]
      ()
  in
  let bind_group =
    Wgpu.Device.create_bind_group
      device
      ~label:"skybox_bind_group"
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
          ; buffer = None
          ; offset = 0L
          ; size = 0L
          ; sampler = Some sampler
          ; texture_view = None
          }
        ; { Wgpu.Bind_group_entry.binding = 2
          ; buffer = None
          ; offset = 0L
          ; size = 0L
          ; sampler = None
          ; texture_view = Some cubemap_view
          }
        ]
      ()
  in
  let pipeline_layout =
    Wgpu.Device.create_pipeline_layout
      device
      ~label:"skybox_pipeline_layout"
      ~bind_group_layouts:[ bind_group_layout ]
      ()
  in
  let pipeline =
    Wgpu.Device.create_render_pipeline
      device
      ~label:"skybox_pipeline"
      ~shader_module:shader
      ~vertex_entry_point:"vs"
      ~fragment_entry_point:"fs"
      ~color_format:Wgpu.Texture_format.Rgba8_unorm
      ~layout:pipeline_layout
      ()
  in
  (* Render at different camera angles to show different faces *)
  let aspect = Float.of_int width /. Float.of_int height in
  let fov_y = 60.0 *. Float.pi /. 180.0 in
  let z_near = 0.1 in
  let z_far = 10.0 in
  let projection = perspective_matrix ~fov_y ~aspect ~z_near ~z_far in
  let render_at_angle angle output_name =
    (* Camera position rotating around origin *)
    let cam_x = Float.cos angle in
    let cam_z = Float.sin angle in
    let eye = Gg.V3.v cam_x 0.0 cam_z in
    let target = Gg.V3.v 0.0 0.0 0.0 in
    let up = Gg.V3.v 0.0 1.0 0.0 in
    let view = look_at_matrix ~eye ~target ~up in
    (* Zero out translation - we only care about direction *)
    let view_direction =
      Gg.M4.v
        (Gg.M4.e00 view)
        (Gg.M4.e01 view)
        (Gg.M4.e02 view)
        0.0
        (Gg.M4.e10 view)
        (Gg.M4.e11 view)
        (Gg.M4.e12 view)
        0.0
        (Gg.M4.e20 view)
        (Gg.M4.e21 view)
        (Gg.M4.e22 view)
        0.0
        (Gg.M4.e30 view)
        (Gg.M4.e31 view)
        (Gg.M4.e32 view)
        1.0
    in
    let view_projection = Gg.M4.mul projection view_direction in
    let view_dir_proj_inverse = Gg.M4.inv view_projection in
    let uniform_data = matrix_to_bigarray view_dir_proj_inverse in
    Wgpu.Queue.write_buffer queue ~buffer:uniform_buffer ~offset:0L ~data:uniform_data;
    render_frame ~device ~queue ~pipeline ~bind_group ~angle ~output_name
  in
  (* Render looking in different directions *)
  render_at_angle 0.0 "_front";
  render_at_angle (Float.pi /. 2.0) "_right";
  render_at_angle Float.pi "_back";
  render_at_angle (Float.pi *. 1.5) "_left";
  (* Cleanup *)
  Wgpu.Render_pipeline.release pipeline;
  Wgpu.Pipeline_layout.release pipeline_layout;
  Wgpu.Bind_group.release bind_group;
  Wgpu.Bind_group_layout.release bind_group_layout;
  Wgpu.Buffer.release uniform_buffer;
  Wgpu.Sampler.release sampler;
  Wgpu.Texture_view.release cubemap_view;
  Wgpu.Texture.release cubemap_texture;
  Wgpu.Shader_module.release shader;
  Wgpu.Queue.release queue;
  Wgpu.Device.release device;
  Wgpu.Adapter.release adapter;
  Wgpu.Instance.release instance
;;
