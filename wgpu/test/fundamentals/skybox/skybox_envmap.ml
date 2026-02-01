(*
   WebGPU Fundamentals: Skybox with Environment-Mapped Cube

   This test demonstrates:
   - A reflective cube using environment mapping (cubemap reflections)
   - A skybox rendered behind the cube using depth testing
   - Two render pipelines sharing the same cubemap texture

   The cube reflects the environment around it, while the skybox fills
   the background wherever the cube doesn't appear.
*)

open! Core

let width = 600
let height = 400
let bytes_per_pixel = 4
let bytes_per_row = ((width * bytes_per_pixel) + 255) / 256 * 256
let buffer_size = bytes_per_row * height

(* Skybox shader - renders fullscreen triangle at z=1 with cubemap sampling *)
let skybox_shader_code =
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
  let pos = array(
    vec2f(-1, 3),
    vec2f(-1,-1),
    vec2f( 3,-1),
  );
  var vsOut: VSOutput;
  vsOut.position = vec4f(pos[vNdx], 1, 1);
  vsOut.pos = vsOut.position;
  return vsOut;
}

@fragment fn fs(vsOut: VSOutput) -> @location(0) vec4f {
  let t = uni.viewDirectionProjectionInverse * vsOut.pos;
  return textureSample(ourTexture, ourSampler, normalize(t.xyz / t.w) * vec3f(1, 1, -1));
}
|}
;;

(* Environment map shader - renders geometry with reflective surface *)
let envmap_shader_code =
  {|
struct Uniforms {
  projection: mat4x4f,
  view: mat4x4f,
  world: mat4x4f,
  cameraPosition: vec3f,
};

struct Vertex {
  @location(0) position: vec4f,
  @location(1) normal: vec3f,
};

struct VSOutput {
  @builtin(position) position: vec4f,
  @location(0) worldPosition: vec3f,
  @location(1) worldNormal: vec3f,
};

@group(0) @binding(0) var<uniform> uni: Uniforms;
@group(0) @binding(1) var ourSampler: sampler;
@group(0) @binding(2) var ourTexture: texture_cube<f32>;

@vertex fn vs(vert: Vertex) -> VSOutput {
  var vsOut: VSOutput;
  vsOut.position = uni.projection * uni.view * uni.world * vert.position;
  vsOut.worldPosition = (uni.world * vert.position).xyz;
  vsOut.worldNormal = (uni.world * vec4f(vert.normal, 0)).xyz;
  return vsOut;
}

@fragment fn fs(vsOut: VSOutput) -> @location(0) vec4f {
  let worldNormal = normalize(vsOut.worldNormal);
  let eyeToSurfaceDir = normalize(vsOut.worldPosition - uni.cameraPosition);
  let direction = reflect(eyeToSurfaceDir, worldNormal);
  return textureSample(ourTexture, ourSampler, direction * vec3f(1, 1, -1));
}
|}
;;

(* Cube vertex data: position (x,y,z) and normal (nx,ny,nz) *)
let cube_vertex_data =
  [| (* front face - positive z *)
     -1.0
   ; 1.0
   ; 1.0
   ; 0.0
   ; 0.0
   ; 1.0
   ; -1.0
   ; -1.0
   ; 1.0
   ; 0.0
   ; 0.0
   ; 1.0
   ; 1.0
   ; 1.0
   ; 1.0
   ; 0.0
   ; 0.0
   ; 1.0
   ; 1.0
   ; -1.0
   ; 1.0
   ; 0.0
   ; 0.0
   ; 1.0
   ; (* right face - positive x *)
     1.0
   ; 1.0
   ; -1.0
   ; 1.0
   ; 0.0
   ; 0.0
   ; 1.0
   ; 1.0
   ; 1.0
   ; 1.0
   ; 0.0
   ; 0.0
   ; 1.0
   ; -1.0
   ; -1.0
   ; 1.0
   ; 0.0
   ; 0.0
   ; 1.0
   ; -1.0
   ; 1.0
   ; 1.0
   ; 0.0
   ; 0.0
   ; (* back face - negative z *)
     1.0
   ; 1.0
   ; -1.0
   ; 0.0
   ; 0.0
   ; -1.0
   ; 1.0
   ; -1.0
   ; -1.0
   ; 0.0
   ; 0.0
   ; -1.0
   ; -1.0
   ; 1.0
   ; -1.0
   ; 0.0
   ; 0.0
   ; -1.0
   ; -1.0
   ; -1.0
   ; -1.0
   ; 0.0
   ; 0.0
   ; -1.0
   ; (* left face - negative x *)
     -1.0
   ; 1.0
   ; 1.0
   ; -1.0
   ; 0.0
   ; 0.0
   ; -1.0
   ; 1.0
   ; -1.0
   ; -1.0
   ; 0.0
   ; 0.0
   ; -1.0
   ; -1.0
   ; 1.0
   ; -1.0
   ; 0.0
   ; 0.0
   ; -1.0
   ; -1.0
   ; -1.0
   ; -1.0
   ; 0.0
   ; 0.0
   ; (* bottom face - negative y *)
     1.0
   ; -1.0
   ; 1.0
   ; 0.0
   ; -1.0
   ; 0.0
   ; -1.0
   ; -1.0
   ; 1.0
   ; 0.0
   ; -1.0
   ; 0.0
   ; 1.0
   ; -1.0
   ; -1.0
   ; 0.0
   ; -1.0
   ; 0.0
   ; -1.0
   ; -1.0
   ; -1.0
   ; 0.0
   ; -1.0
   ; 0.0
   ; (* top face - positive y *)
     -1.0
   ; 1.0
   ; 1.0
   ; 0.0
   ; 1.0
   ; 0.0
   ; 1.0
   ; 1.0
   ; 1.0
   ; 0.0
   ; 1.0
   ; 0.0
   ; -1.0
   ; 1.0
   ; -1.0
   ; 0.0
   ; 1.0
   ; 0.0
   ; 1.0
   ; 1.0
   ; -1.0
   ; 0.0
   ; 1.0
   ; 0.0
  |]
;;

let cube_index_data =
  [| 0
   ; 1
   ; 2
   ; 2
   ; 1
   ; 3 (* front *)
   ; 4
   ; 5
   ; 6
   ; 6
   ; 5
   ; 7 (* right *)
   ; 8
   ; 9
   ; 10
   ; 10
   ; 9
   ; 11 (* back *)
   ; 12
   ; 13
   ; 14
   ; 14
   ; 13
   ; 15 (* left *)
   ; 16
   ; 17
   ; 18
   ; 18
   ; 17
   ; 19 (* bottom *)
   ; 20
   ; 21
   ; 22
   ; 22
   ; 21
   ; 23 (* top *)
  |]
;;

let num_cube_indices = Array.length cube_index_data
let floats_per_cube_vertex = 6
let cube_vertex_buffer_size = Array.length cube_vertex_data * 4
let cube_index_buffer_size = num_cube_indices * 2 (* uint16 *)

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

(* Convert matrix to bigarray for GPU upload (transpose for column-major) *)
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

(* Skybox uniform buffer: mat4x4f viewDirectionProjectionInverse *)
let skybox_uniform_buffer_size = 16 * 4

(* Envmap uniform buffer: projection + view + world + cameraPosition + padding *)
(* Layout: mat4x4f (16) + mat4x4f (16) + mat4x4f (16) + vec3f (3) + pad (1) = 52 floats *)
let envmap_uniform_buffer_size = (16 + 16 + 16 + 3 + 1) * 4

let init () =
  let instance = Wgpu.Instance.create () in
  let adapter = Wgpu.Instance.request_adapter instance () in
  let device = Wgpu.Adapter.request_device adapter in
  let queue = Wgpu.Device.get_queue device in
  instance, adapter, device, queue
;;

let () =
  let instance, adapter, device, queue = init () in
  (* Create shaders *)
  let skybox_shader =
    Wgpu.Device.create_shader_module
      device
      ~label:"skybox_shader"
      ~wgsl:skybox_shader_code
      ()
  in
  let envmap_shader =
    Wgpu.Device.create_shader_module
      device
      ~label:"envmap_shader"
      ~wgsl:envmap_shader_code
      ()
  in
  (* Load cubemap faces - try build directory path first, fallback to workspace path *)
  let face_files =
    [ "pos-x.png"; "neg-x.png"; "pos-y.png"; "neg-y.png"; "pos-z.png"; "neg-z.png" ]
  in
  let faces =
    List.map face_files ~f:(fun filename ->
      (* Try build directory path (used by dune runtest) *)
      let build_path = Filename.concat "../../assets/skybox" filename in
      (* Try workspace path (used by dune exec from workspace root) *)
      let workspace_path = Filename.concat "test/assets/skybox" filename in
      let path =
        if Stdlib.Sys.file_exists build_path then build_path else workspace_path
      in
      Test_util.load_png ~filename:path)
  in
  let cubemap_face_size, _, _ = List.hd_exn faces in
  (* Create cubemap texture *)
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
  (* Upload faces *)
  List.iteri faces ~f:(fun layer (face_width, face_height, data) ->
    Wgpu.Queue.write_texture
      queue
      ~destination_texture:cubemap_texture
      ~destination_mip_level:0
      ~destination_origin_x:0
      ~destination_origin_y:0
      ~destination_origin_z:layer
      ~destination_aspect:Wgpu.Texture_aspect.All
      ~data_layout_offset:0L
      ~data_layout_bytes_per_row:(face_width * 4)
      ~data_layout_rows_per_image:face_height
      ~write_size_width:face_width
      ~write_size_height:face_height
      ~write_size_depth_or_array_layers:1
      ~data
      ());
  let cubemap_view =
    Wgpu.create_texture_view
      cubemap_texture
      ~label:"cubemap_view"
      ~dimension:Wgpu.Texture_view_dimension.Cube
      ()
  in
  (* Sampler shared by both pipelines *)
  let sampler =
    Wgpu.Device.create_sampler
      device
      ~label:"cubemap_sampler"
      ~address_mode_u:Wgpu.Address_mode.Clamp_to_edge
      ~address_mode_v:Wgpu.Address_mode.Clamp_to_edge
      ~address_mode_w:Wgpu.Address_mode.Clamp_to_edge
      ~mag_filter:Wgpu.Filter_mode.Linear
      ~min_filter:Wgpu.Filter_mode.Linear
      ~mipmap_filter:Wgpu.Mipmap_filter_mode.Linear
      ~lod_min_clamp:0.0
      ~lod_max_clamp:32.0
      ~compare:Wgpu.Compare_function.Undefined
      ~max_anisotropy:1
      ()
  in
  (* Skybox uniform buffer *)
  let skybox_uniform_buffer =
    Wgpu.Device.create_buffer
      device
      ~label:"skybox_uniform_buffer"
      ~size:(Int64.of_int skybox_uniform_buffer_size)
      ~usage:[ Wgpu.Buffer_usage.Item.Uniform; Wgpu.Buffer_usage.Item.Copy_dst ]
      ~mapped_at_creation:false
      ()
  in
  (* Envmap uniform buffer *)
  let envmap_uniform_buffer =
    Wgpu.Device.create_buffer
      device
      ~label:"envmap_uniform_buffer"
      ~size:(Int64.of_int envmap_uniform_buffer_size)
      ~usage:[ Wgpu.Buffer_usage.Item.Uniform; Wgpu.Buffer_usage.Item.Copy_dst ]
      ~mapped_at_creation:false
      ()
  in
  (* Cube vertex buffer *)
  let cube_vertex_buffer =
    Wgpu.Device.create_buffer
      device
      ~label:"cube_vertex_buffer"
      ~size:(Int64.of_int cube_vertex_buffer_size)
      ~usage:[ Wgpu.Buffer_usage.Item.Vertex; Wgpu.Buffer_usage.Item.Copy_dst ]
      ~mapped_at_creation:false
      ()
  in
  let vertex_bigarray =
    Bigarray.Array1.of_array Bigarray.float32 Bigarray.c_layout cube_vertex_data
  in
  Wgpu.Queue.write_buffer
    queue
    ~buffer:cube_vertex_buffer
    ~offset:0L
    ~data:vertex_bigarray;
  (* Cube index buffer *)
  let cube_index_buffer =
    Wgpu.Device.create_buffer
      device
      ~label:"cube_index_buffer"
      ~size:(Int64.of_int cube_index_buffer_size)
      ~usage:[ Wgpu.Buffer_usage.Item.Index; Wgpu.Buffer_usage.Item.Copy_dst ]
      ~mapped_at_creation:false
      ()
  in
  let index_bigarray =
    let arr =
      Bigarray.Array1.create Bigarray.int16_unsigned Bigarray.c_layout num_cube_indices
    in
    Array.iteri cube_index_data ~f:(fun i v -> Bigarray.Array1.set arr i v);
    arr
  in
  Wgpu.Queue.write_buffer queue ~buffer:cube_index_buffer ~offset:0L ~data:index_bigarray;
  (* Bind group layout for skybox *)
  let skybox_bind_group_layout =
    Wgpu.Device.create_bind_group_layout
      device
      ~label:"skybox_bind_group_layout"
      ~entries:
        [ Wgpu.Bind_group_layout_entry.create
            ~binding:0
            ~visibility:[ Wgpu.Shader_stage.Item.Vertex; Wgpu.Shader_stage.Item.Fragment ]
            ~buffer:
              (Wgpu.Bind_group_layout_entry.Buffer_binding_layout.create
                 ~type_:Wgpu.Buffer_binding_type.Uniform
                 ~has_dynamic_offset:false
                 ~min_binding_size:0L
                 ())
            ()
        ; Wgpu.Bind_group_layout_entry.create
            ~binding:1
            ~visibility:[ Wgpu.Shader_stage.Item.Fragment ]
            ~sampler:
              (Wgpu.Bind_group_layout_entry.Sampler_binding_layout.create
                 ~type_:Wgpu.Sampler_binding_type.Filtering
                 ())
            ()
        ; Wgpu.Bind_group_layout_entry.create
            ~binding:2
            ~visibility:[ Wgpu.Shader_stage.Item.Fragment ]
            ~texture:
              (Wgpu.Bind_group_layout_entry.Texture_binding_layout.create
                 ~sample_type:Wgpu.Texture_sample_type.Float
                 ~view_dimension:Wgpu.Texture_view_dimension.Cube
                 ~multisampled:false
                 ())
            ()
        ]
      ()
  in
  let skybox_bind_group =
    Wgpu.Device.create_bind_group
      device
      ~label:"skybox_bind_group"
      ~layout:skybox_bind_group_layout
      ~entries:
        [ Wgpu.Bind_group_entry.create
            ~binding:0
            ~buffer:skybox_uniform_buffer
            ~offset:0L
            ~size:(Int64.of_int skybox_uniform_buffer_size)
            ()
        ; Wgpu.Bind_group_entry.create ~binding:1 ~offset:0L ~size:0L ~sampler ()
        ; Wgpu.Bind_group_entry.create
            ~binding:2
            ~offset:0L
            ~size:0L
            ~texture_view:cubemap_view
            ()
        ]
      ()
  in
  let skybox_pipeline_layout =
    Wgpu.Device.create_pipeline_layout
      device
      ~label:"skybox_pipeline_layout"
      ~bind_group_layouts:[ skybox_bind_group_layout ]
      ()
  in
  (* Skybox pipeline with depth less-equal (renders at z=1, depth buffer cleared to 1) *)
  let skybox_pipeline =
    Wgpu.Device.create_render_pipeline
      device
      ~label:"skybox_pipeline"
      ~layout:skybox_pipeline_layout
      ~vertex_module:skybox_shader
      ~vertex_entry_point:"vs"
      ~primitive_topology:Wgpu.Primitive_topology.Triangle_list
      ~primitive_strip_index_format:Wgpu.Index_format.Undefined
      ~primitive_front_face:Wgpu.Front_face.Ccw
      ~primitive_cull_mode:Wgpu.Cull_mode.None
      ~primitive_unclipped_depth:false
      ~depth_stencil:
        (Wgpu.Depth_stencil_state.create
           ~format:Wgpu.Texture_format.Depth24_plus
           ~depth_write_enabled:True
           ~depth_compare:Wgpu.Compare_function.Less_equal
           ~stencil_front:
             (Wgpu.Depth_stencil_state.Stencil_face_state.create
                ~compare:Wgpu.Compare_function.Always
                ~fail_op:Wgpu.Stencil_operation.Keep
                ~depth_fail_op:Wgpu.Stencil_operation.Keep
                ~pass_op:Wgpu.Stencil_operation.Keep
                ())
           ~stencil_back:
             (Wgpu.Depth_stencil_state.Stencil_face_state.create
                ~compare:Wgpu.Compare_function.Always
                ~fail_op:Wgpu.Stencil_operation.Keep
                ~depth_fail_op:Wgpu.Stencil_operation.Keep
                ~pass_op:Wgpu.Stencil_operation.Keep
                ())
           ~stencil_read_mask:0xFFFFFFFF
           ~stencil_write_mask:0xFFFFFFFF
           ~depth_bias:0
           ~depth_bias_slope_scale:0.0
           ~depth_bias_clamp:0.0
           ())
      ~multisample_count:1
      ~multisample_mask:0xFFFFFFFF
      ~multisample_alpha_to_coverage_enabled:false
      ~fragment:
        (Wgpu.Fragment_state.create
           ~module_:skybox_shader
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
  (* Bind group layout for envmap (same structure but different uniform buffer size) *)
  let envmap_bind_group_layout =
    Wgpu.Device.create_bind_group_layout
      device
      ~label:"envmap_bind_group_layout"
      ~entries:
        [ Wgpu.Bind_group_layout_entry.create
            ~binding:0
            ~visibility:[ Wgpu.Shader_stage.Item.Vertex; Wgpu.Shader_stage.Item.Fragment ]
            ~buffer:
              (Wgpu.Bind_group_layout_entry.Buffer_binding_layout.create
                 ~type_:Wgpu.Buffer_binding_type.Uniform
                 ~has_dynamic_offset:false
                 ~min_binding_size:0L
                 ())
            ()
        ; Wgpu.Bind_group_layout_entry.create
            ~binding:1
            ~visibility:[ Wgpu.Shader_stage.Item.Fragment ]
            ~sampler:
              (Wgpu.Bind_group_layout_entry.Sampler_binding_layout.create
                 ~type_:Wgpu.Sampler_binding_type.Filtering
                 ())
            ()
        ; Wgpu.Bind_group_layout_entry.create
            ~binding:2
            ~visibility:[ Wgpu.Shader_stage.Item.Fragment ]
            ~texture:
              (Wgpu.Bind_group_layout_entry.Texture_binding_layout.create
                 ~sample_type:Wgpu.Texture_sample_type.Float
                 ~view_dimension:Wgpu.Texture_view_dimension.Cube
                 ~multisampled:false
                 ())
            ()
        ]
      ()
  in
  let envmap_bind_group =
    Wgpu.Device.create_bind_group
      device
      ~label:"envmap_bind_group"
      ~layout:envmap_bind_group_layout
      ~entries:
        [ Wgpu.Bind_group_entry.create
            ~binding:0
            ~buffer:envmap_uniform_buffer
            ~offset:0L
            ~size:(Int64.of_int envmap_uniform_buffer_size)
            ()
        ; Wgpu.Bind_group_entry.create ~binding:1 ~offset:0L ~size:0L ~sampler ()
        ; Wgpu.Bind_group_entry.create
            ~binding:2
            ~offset:0L
            ~size:0L
            ~texture_view:cubemap_view
            ()
        ]
      ()
  in
  let envmap_pipeline_layout =
    Wgpu.Device.create_pipeline_layout
      device
      ~label:"envmap_pipeline_layout"
      ~bind_group_layouts:[ envmap_bind_group_layout ]
      ()
  in
  (* Envmap pipeline with depth less and backface culling *)
  let envmap_vertex_buffer_layout =
    Wgpu.Vertex_buffer_layout.create
      ~step_mode:Wgpu.Vertex_step_mode.Vertex
      ~array_stride:(Int64.of_int (floats_per_cube_vertex * 4))
      ~attributes:
        [ Wgpu.Vertex_attribute.create
            ~format:Wgpu.Vertex_format.Float32x3
            ~offset:0L
            ~shader_location:0
            ()
        ; Wgpu.Vertex_attribute.create
            ~format:Wgpu.Vertex_format.Float32x3
            ~offset:(Int64.of_int (3 * 4))
            ~shader_location:1
            ()
        ]
      ()
  in
  let envmap_pipeline =
    Wgpu.Device.create_render_pipeline
      device
      ~label:"envmap_pipeline"
      ~layout:envmap_pipeline_layout
      ~vertex_module:envmap_shader
      ~vertex_entry_point:"vs"
      ~vertex_buffers:[ envmap_vertex_buffer_layout ]
      ~primitive_topology:Wgpu.Primitive_topology.Triangle_list
      ~primitive_strip_index_format:Wgpu.Index_format.Undefined
      ~primitive_front_face:Wgpu.Front_face.Ccw
      ~primitive_cull_mode:Wgpu.Cull_mode.Back
      ~primitive_unclipped_depth:false
      ~depth_stencil:
        (Wgpu.Depth_stencil_state.create
           ~format:Wgpu.Texture_format.Depth24_plus
           ~depth_write_enabled:True
           ~depth_compare:Wgpu.Compare_function.Less
           ~stencil_front:
             (Wgpu.Depth_stencil_state.Stencil_face_state.create
                ~compare:Wgpu.Compare_function.Always
                ~fail_op:Wgpu.Stencil_operation.Keep
                ~depth_fail_op:Wgpu.Stencil_operation.Keep
                ~pass_op:Wgpu.Stencil_operation.Keep
                ())
           ~stencil_back:
             (Wgpu.Depth_stencil_state.Stencil_face_state.create
                ~compare:Wgpu.Compare_function.Always
                ~fail_op:Wgpu.Stencil_operation.Keep
                ~depth_fail_op:Wgpu.Stencil_operation.Keep
                ~pass_op:Wgpu.Stencil_operation.Keep
                ())
           ~stencil_read_mask:0xFFFFFFFF
           ~stencil_write_mask:0xFFFFFFFF
           ~depth_bias:0
           ~depth_bias_slope_scale:0.0
           ~depth_bias_clamp:0.0
           ())
      ~multisample_count:1
      ~multisample_mask:0xFFFFFFFF
      ~multisample_alpha_to_coverage_enabled:false
      ~fragment:
        (Wgpu.Fragment_state.create
           ~module_:envmap_shader
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
  (* Render at multiple camera positions/cube rotations *)
  let aspect = Float.of_int width /. Float.of_int height in
  let fov_y = 60.0 *. Float.pi /. 180.0 in
  let z_near = 0.1 in
  let z_far = 10.0 in
  let projection = perspective_matrix ~fov_y ~aspect ~z_near ~z_far in
  let render_frame ~time ~output_name =
    (* Create render target *)
    let color_texture =
      Wgpu.Device.create_texture
        device
        ~label:"color_target"
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
    let color_view = Wgpu.create_texture_view color_texture ~label:"color_view" () in
    (* Create depth texture *)
    let depth_texture =
      Wgpu.Device.create_texture
        device
        ~label:"depth_target"
        ~size_width:width
        ~size_height:height
        ~size_depth_or_array_layers:1
        ~dimension:N2d
        ~mip_level_count:1
        ~sample_count:1
        ~format:Wgpu.Texture_format.Depth24_plus
        ~usage:[ Wgpu.Texture_usage.Item.Render_attachment ]
        ()
    in
    let depth_view = Wgpu.create_texture_view depth_texture ~label:"depth_view" () in
    (* Camera going in circle at distance 5 *)
    let camera_x = Float.cos (time *. 0.1) *. 5.0 in
    let camera_z = Float.sin (time *. 0.1) *. 5.0 in
    let eye = Gg.V3.v camera_x 0.0 camera_z in
    let target = Gg.V3.v 0.0 0.0 0.0 in
    let up = Gg.V3.v 0.0 1.0 0.0 in
    let view = look_at_matrix ~eye ~target ~up in
    (* Skybox uniform: viewDirectionProjectionInverse *)
    let view_direction =
      (* Zero out translation *)
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
    let skybox_uniform_data = matrix_to_bigarray view_dir_proj_inverse in
    Wgpu.Queue.write_buffer
      queue
      ~buffer:skybox_uniform_buffer
      ~offset:0L
      ~data:skybox_uniform_data;
    (* Envmap uniforms: projection, view, world, cameraPosition *)
    let envmap_uniform_data =
      Bigarray.Array1.create Bigarray.float32 Bigarray.c_layout 52
    in
    (* projection at offset 0 *)
    let proj_data = matrix_to_bigarray projection in
    for i = 0 to 15 do
      Bigarray.Array1.set envmap_uniform_data i (Bigarray.Array1.get proj_data i)
    done;
    (* view at offset 16 *)
    let view_data = matrix_to_bigarray view in
    for i = 0 to 15 do
      Bigarray.Array1.set envmap_uniform_data (16 + i) (Bigarray.Array1.get view_data i)
    done;
    (* world (cube rotation) at offset 32 *)
    let world =
      let rot_x = Gg.M4.rot3_axis Gg.V3.ox (time *. -0.1) in
      let rot_y = Gg.M4.rot3_axis Gg.V3.oy (time *. -0.2) in
      Gg.M4.mul rot_y rot_x
    in
    let world_data = matrix_to_bigarray world in
    for i = 0 to 15 do
      Bigarray.Array1.set envmap_uniform_data (32 + i) (Bigarray.Array1.get world_data i)
    done;
    (* cameraPosition at offset 48 *)
    Bigarray.Array1.set envmap_uniform_data 48 camera_x;
    Bigarray.Array1.set envmap_uniform_data 49 0.0;
    Bigarray.Array1.set envmap_uniform_data 50 camera_z;
    Bigarray.Array1.set envmap_uniform_data 51 0.0;
    (* padding *)
    Wgpu.Queue.write_buffer
      queue
      ~buffer:envmap_uniform_buffer
      ~offset:0L
      ~data:envmap_uniform_data;
    (* Create readback buffer *)
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
        ~label:"envmap_pass"
        ~color_attachments:
          [ Wgpu.Render_pass_color_attachment.create
              ~view:color_view
              ~load_op:Wgpu.Load_op.Clear
              ~store_op:Wgpu.Store_op.Store
              ~clear_value:
                (Wgpu.Render_pass_color_attachment.Color.create
                   ~r:0.0
                   ~g:0.0
                   ~b:0.0
                   ~a:1.0
                   ())
              ()
          ]
        ~depth_stencil_attachment:
          (Wgpu.Render_pass_depth_stencil_attachment.create
             ~view:depth_view
             ~depth_load_op:Wgpu.Load_op.Clear
             ~depth_store_op:Wgpu.Store_op.Store
             ~depth_clear_value:1.0
             ~depth_read_only:false
             ~stencil_load_op:Wgpu.Load_op.Clear
             ~stencil_store_op:Wgpu.Store_op.Store
             ~stencil_clear_value:0
             ~stencil_read_only:false
             ())
        ()
    in
    (* Draw cube first (writes to depth buffer) *)
    Wgpu.Render_pass_encoder.set_pipeline render_pass ~pipeline:envmap_pipeline;
    Wgpu.Render_pass_encoder.set_vertex_buffer
      render_pass
      ~slot:0
      ~buffer:cube_vertex_buffer
      ~offset:0L
      ~size:(Int64.of_int cube_vertex_buffer_size);
    Wgpu.Render_pass_encoder.set_index_buffer
      render_pass
      ~buffer:cube_index_buffer
      ~format:Wgpu.Index_format.Uint16
      ~offset:0L
      ~size:(Int64.of_int cube_index_buffer_size);
    Wgpu.set_bind_group_render render_pass ~index:0 ~bind_group:envmap_bind_group;
    Wgpu.Render_pass_encoder.draw_indexed
      render_pass
      ~index_count:num_cube_indices
      ~instance_count:1
      ~first_index:0
      ~base_vertex:0
      ~first_instance:0;
    (* Draw skybox (uses less-equal, fills in where cube didn't draw) *)
    Wgpu.Render_pass_encoder.set_pipeline render_pass ~pipeline:skybox_pipeline;
    Wgpu.set_bind_group_render render_pass ~index:0 ~bind_group:skybox_bind_group;
    Wgpu.Render_pass_encoder.draw
      render_pass
      ~vertex_count:3
      ~instance_count:1
      ~first_vertex:0
      ~first_instance:0;
    Wgpu.Render_pass_encoder.end_ render_pass;
    (* Copy to readback buffer *)
    Wgpu.copy_texture_to_buffer
      encoder
      ~texture:color_texture
      ~buffer:readback_buffer
      ~size:(width, height)
      ~bytes_per_row
      ();
    let command_buffer = Wgpu.finish encoder ~label:"render_commands" () in
    Wgpu.Queue.submit queue ~commands:[ command_buffer ];
    Wgpu.Device.poll device ~wait:true ();
    (* Read back and save *)
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
      let ppm_file = Test_util.output_path ("skybox_envmap" ^ output_name ^ ".ppm") in
      let png_file = Test_util.output_path ("skybox_envmap" ^ output_name ^ ".png") in
      Test_util.write_ppm
        ~filename:ppm_file
        ~width
        ~height
        ~data:mapped_data
        ~bytes_per_row;
      Test_util.ppm_to_png ~ppm_file ~png_file;
      ()
    in
    Wgpu.Buffer.unmap readback_buffer;
    (* Cleanup frame resources *)
    Wgpu.Command_buffer.release command_buffer;
    Wgpu.Render_pass_encoder.release render_pass;
    Wgpu.Command_encoder.release encoder;
    Wgpu.Buffer.release readback_buffer;
    Wgpu.Texture_view.release depth_view;
    Wgpu.Texture.release depth_texture;
    Wgpu.Texture_view.release color_view;
    Wgpu.Texture.release color_texture
  in
  (* Render multiple frames at different times *)
  render_frame ~time:0.0 ~output_name:"_t0";
  render_frame ~time:5.0 ~output_name:"_t5";
  render_frame ~time:10.0 ~output_name:"_t10";
  render_frame ~time:15.0 ~output_name:"_t15";
  (* Cleanup *)
  Wgpu.Render_pipeline.release envmap_pipeline;
  Wgpu.Pipeline_layout.release envmap_pipeline_layout;
  Wgpu.Bind_group.release envmap_bind_group;
  Wgpu.Bind_group_layout.release envmap_bind_group_layout;
  Wgpu.Render_pipeline.release skybox_pipeline;
  Wgpu.Pipeline_layout.release skybox_pipeline_layout;
  Wgpu.Bind_group.release skybox_bind_group;
  Wgpu.Bind_group_layout.release skybox_bind_group_layout;
  Wgpu.Buffer.release cube_index_buffer;
  Wgpu.Buffer.release cube_vertex_buffer;
  Wgpu.Buffer.release envmap_uniform_buffer;
  Wgpu.Buffer.release skybox_uniform_buffer;
  Wgpu.Sampler.release sampler;
  Wgpu.Texture_view.release cubemap_view;
  Wgpu.Texture.release cubemap_texture;
  Wgpu.Shader_module.release envmap_shader;
  Wgpu.Shader_module.release skybox_shader;
  Wgpu.Queue.release queue;
  Wgpu.Device.release device;
  Wgpu.Adapter.release adapter;
  Wgpu.Instance.release instance
;;
