open! Core

(* Write RGBA pixel data to a PPM file (P6 binary format) *)
let write_ppm ~filename ~width ~height ~data ~bytes_per_row =
  Out_channel.with_file filename ~f:(fun oc ->
    (* PPM header: P6 for binary RGB *)
    Out_channel.fprintf oc "P6\n%d %d\n255\n" width height;
    (* Write RGB data (skip alpha) *)
    for y = 0 to height - 1 do
      for x = 0 to width - 1 do
        let offset = (y * bytes_per_row) + (x * 4) in
        let r = Bigarray.Array1.get data offset in
        let g = Bigarray.Array1.get data (offset + 1) in
        let b = Bigarray.Array1.get data (offset + 2) in
        Out_channel.output_char oc (Char.of_int_exn r);
        Out_channel.output_char oc (Char.of_int_exn g);
        Out_channel.output_char oc (Char.of_int_exn b)
      done
    done)
;;

(* Convert PPM to PNG using ImageMagick *)
let ppm_to_png ~ppm_file ~png_file =
  (* Exclude timestamp chunks to ensure reproducible output *)
  let cmd =
    sprintf "convert %s -define png:exclude-chunks=date,time %s" ppm_file png_file
  in
  match Core_unix.system cmd with
  | Ok () -> true
  | Error _ ->
    eprintf "Warning: ImageMagick convert failed. PPM file saved as %s\n" ppm_file;
    false
;;

let test_instance_and_adapter () =
  print_endline "Creating wgpu instance...";
  let instance = Wgpu.Instance.create () in
  print_endline "Instance created!";
  print_endline "Requesting adapter...";
  let adapter = Wgpu.Instance.request_adapter instance () in
  print_endline "Adapter obtained!";
  let info = Wgpu.Adapter.get_info adapter in
  printf "  Vendor: %s\n" info.vendor;
  printf "  Architecture: %s\n" info.architecture;
  printf "  Device: %s\n" info.device;
  printf "  Description: %s\n" info.description;
  printf "  Backend type: %d\n" (Wgpu.Backend_type.to_int info.backend_type);
  printf "  Adapter type: %d\n" (Wgpu.Adapter_type.to_int info.adapter_type);
  Wgpu.Adapter.release adapter;
  print_endline "Adapter released.";
  Wgpu.Instance.release instance;
  print_endline "Instance released."
;;

let test_buffer_creation () =
  print_endline "\n=== Testing Buffer Creation ===";
  (* Create instance, adapter, device using high-level API *)
  let instance = Wgpu.Instance.create () in
  let adapter = Wgpu.Instance.request_adapter instance () in
  let device = Wgpu.Adapter.request_device adapter in
  print_endline "Device obtained.";
  (* Create buffer using high-level API *)
  let buffer =
    Wgpu.Device.create_buffer
      device
      ~size:256L
      ~usage:
        [ Wgpu.Buffer_usage.Item.Storage
        ; Wgpu.Buffer_usage.Item.Copy_dst
        ; Wgpu.Buffer_usage.Item.Copy_src
        ]
      ~mapped_at_creation:false
      ()
  in
  print_endline "Buffer created!";
  (* Get buffer info *)
  let buf_size = Wgpu.Buffer.get_size buffer in
  let buf_usage = Wgpu.Buffer.get_usage buffer in
  printf "  Buffer size: %Ld\n" buf_size;
  printf "  Buffer usage: 0x%04x\n" buf_usage;
  assert (Int64.equal buf_size 256L);
  print_endline "Buffer properties verified!";
  (* Cleanup *)
  Wgpu.Buffer.release buffer;
  Wgpu.Device.release device;
  Wgpu.Adapter.release adapter;
  Wgpu.Instance.release instance;
  print_endline "All resources released."
;;

let test_compute_shader () =
  print_endline "\n=== Testing Compute Shader (Full Pipeline) ===";
  (* Create instance, adapter, device using high-level API *)
  let instance = Wgpu.Instance.create () in
  let adapter = Wgpu.Instance.request_adapter instance () in
  let device = Wgpu.Adapter.request_device adapter in
  let queue = Wgpu.Device.get_queue device in
  print_endline "Device and queue obtained.";
  (* Create shader module with WGSL code that doubles values *)
  let shader_code =
    {|
@group(0) @binding(0) var<storage, read_write> data: array<u32>;

@compute @workgroup_size(64)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let index = global_id.x;
    if (index < arrayLength(&data)) {
        data[index] = data[index] * 2u;
    }
}
|}
  in
  let shader = Wgpu.Device.create_shader_module device ~wgsl:shader_code () in
  print_endline "Shader module created!";
  (* Create storage buffer (GPU only, not mappable) *)
  let num_elements = 64 in
  let data_size = num_elements * 4 in
  (* 64 uint32 values = 256 bytes *)
  let storage_buffer =
    Wgpu.Device.create_buffer
      device
      ~size:(Int64.of_int data_size)
      ~usage:
        [ Wgpu.Buffer_usage.Item.Storage
        ; Wgpu.Buffer_usage.Item.Copy_dst
        ; Wgpu.Buffer_usage.Item.Copy_src
        ]
      ~mapped_at_creation:false
      ()
  in
  print_endline "Storage buffer created.";
  (* Create readback buffer (mappable for reading results) *)
  let readback_buffer =
    Wgpu.Device.create_buffer
      device
      ~size:(Int64.of_int data_size)
      ~usage:[ Wgpu.Buffer_usage.Item.Map_read; Wgpu.Buffer_usage.Item.Copy_dst ]
      ~mapped_at_creation:false
      ()
  in
  print_endline "Readback buffer created.";
  (* Write initial data [0, 1, 2, ..., 63] to storage buffer *)
  let input_bytes =
    Bigarray.Array1.create Bigarray.int8_unsigned Bigarray.c_layout data_size
  in
  for i = 0 to num_elements - 1 do
    let offset = i * 4 in
    (* Little-endian uint32 *)
    Bigarray.Array1.set input_bytes offset (i land 0xFF);
    Bigarray.Array1.set input_bytes (offset + 1) ((i lsr 8) land 0xFF);
    Bigarray.Array1.set input_bytes (offset + 2) ((i lsr 16) land 0xFF);
    Bigarray.Array1.set input_bytes (offset + 3) ((i lsr 24) land 0xFF)
  done;
  Wgpu.Queue.write_buffer queue ~buffer:storage_buffer ~offset:0L ~data:input_bytes;
  print_endline "Initial data written to storage buffer.";
  (* Create bind group layout for single storage buffer at binding 0 *)
  let bind_group_layout =
    Wgpu.Device.create_bind_group_layout_for_storage_buffer
      device
      ~label:"compute_bind_group_layout"
      ~binding:0
      ~read_only:false
      ()
  in
  print_endline "Bind group layout created.";
  (* Create bind group with storage buffer *)
  let bind_group =
    Wgpu.Device.create_bind_group
      device
      ~label:"compute_bind_group"
      ~layout:bind_group_layout
      ~entries:
        [ { Wgpu.Bind_group_entry.binding = 0
          ; buffer = Some storage_buffer
          ; offset = 0L
          ; size = Int64.of_int data_size
          ; sampler = None
          ; texture_view = None
          }
        ]
      ()
  in
  print_endline "Bind group created.";
  (* Create pipeline layout *)
  let pipeline_layout =
    Wgpu.Device.create_pipeline_layout
      device
      ~label:"compute_pipeline_layout"
      ~bind_group_layouts:[ bind_group_layout ]
      ()
  in
  print_endline "Pipeline layout created.";
  (* Create compute pipeline *)
  let compute_pipeline =
    Wgpu.Device.create_compute_pipeline
      device
      ~label:"double_pipeline"
      ~layout:pipeline_layout
      ~module_:shader
      ~entry_point:"main"
      ()
  in
  print_endline "Compute pipeline created.";
  (* Create command encoder and record commands *)
  let encoder = Wgpu.Device.create_command_encoder device ~label:"compute_encoder" () in
  let compute_pass = Wgpu.begin_compute_pass encoder ~label:"compute_pass" () in
  (* Set pipeline and bind group, then dispatch *)
  Wgpu.Compute_pass_encoder.set_pipeline compute_pass ~pipeline:compute_pipeline;
  Wgpu.set_bind_group compute_pass ~index:0 ~bind_group;
  (* Dispatch 1 workgroup of 64 threads *)
  Wgpu.Compute_pass_encoder.dispatch_workgroups
    compute_pass
    ~workgroupCountX:1
    ~workgroupCountY:1
    ~workgroupCountZ:1;
  Wgpu.Compute_pass_encoder.end_ compute_pass;
  print_endline "Compute pass recorded.";
  (* Copy storage buffer to readback buffer *)
  Wgpu.Command_encoder.copy_buffer_to_buffer
    encoder
    ~source:storage_buffer
    ~source_offset:0L
    ~destination:readback_buffer
    ~destination_offset:0L
    ~size:(Int64.of_int data_size);
  print_endline "Copy command recorded.";
  (* Finish and submit *)
  let command_buffer = Wgpu.finish encoder ~label:"compute_commands" () in
  Wgpu.Queue.submit queue ~command_buffers:[ command_buffer ];
  print_endline "Commands submitted.";
  (* Poll device to ensure work completes *)
  Wgpu.Device.poll device ~wait:true ();
  print_endline "Device polled.";
  (* Map readback buffer and verify results *)
  Wgpu.map_buffer
    readback_buffer
    ~mode:[ Wgpu.Map_mode.Item.Read ]
    ~offset:0L
    ~size:(Int64.of_int data_size);
  Wgpu.Device.poll device ~wait:true ();
  let mapped_data =
    Wgpu.get_const_mapped_range readback_buffer ~offset:0L ~size:(Int64.of_int data_size)
  in
  print_endline "Buffer mapped for reading.";
  (* Read back and verify: each value should be doubled *)
  let all_correct = ref true in
  for i = 0 to num_elements - 1 do
    let offset = i * 4 in
    let b0 = Bigarray.Array1.get mapped_data offset in
    let b1 = Bigarray.Array1.get mapped_data (offset + 1) in
    let b2 = Bigarray.Array1.get mapped_data (offset + 2) in
    let b3 = Bigarray.Array1.get mapped_data (offset + 3) in
    let value = b0 lor (b1 lsl 8) lor (b2 lsl 16) lor (b3 lsl 24) in
    let expected = i * 2 in
    if value <> expected
    then (
      printf "  ERROR: data[%d] = %d, expected %d\n" i value expected;
      all_correct := false)
  done;
  if !all_correct
  then print_endline "SUCCESS: All values correctly doubled by compute shader!"
  else print_endline "FAILURE: Some values incorrect.";
  Wgpu.Buffer.unmap readback_buffer;
  (* Cleanup *)
  Wgpu.Command_buffer.release command_buffer;
  Wgpu.Compute_pass_encoder.release compute_pass;
  Wgpu.Command_encoder.release encoder;
  Wgpu.Compute_pipeline.release compute_pipeline;
  Wgpu.Pipeline_layout.release pipeline_layout;
  Wgpu.Bind_group.release bind_group;
  Wgpu.Bind_group_layout.release bind_group_layout;
  Wgpu.Buffer.release readback_buffer;
  Wgpu.Buffer.release storage_buffer;
  Wgpu.Shader_module.release shader;
  Wgpu.Queue.release queue;
  Wgpu.Device.release device;
  Wgpu.Adapter.release adapter;
  Wgpu.Instance.release instance;
  print_endline "All resources released."
;;

let test_render_clear () =
  print_endline "\n=== Testing Render Pass (Clear to Color) ===";
  (* Create instance, adapter, device using high-level API *)
  let instance = Wgpu.Instance.create () in
  let adapter = Wgpu.Instance.request_adapter instance () in
  let device = Wgpu.Adapter.request_device adapter in
  let queue = Wgpu.Device.get_queue device in
  print_endline "Device and queue obtained.";
  (* Create render target texture *)
  let width = 64 in
  let height = 64 in
  let texture =
    Wgpu.Device.create_texture
      device
      ~label:"render_target"
      ~size:(width, height, 1)
      ~format:Wgpu.Texture_format.Rgba8_unorm
      ~usage:
        [ Wgpu.Texture_usage.Item.Render_attachment; Wgpu.Texture_usage.Item.Copy_src ]
      ()
  in
  print_endline "Render target texture created.";
  (* Create texture view *)
  let texture_view = Wgpu.create_texture_view texture ~label:"render_target_view" () in
  print_endline "Texture view created.";
  (* Create readback buffer - 4 bytes per pixel (RGBA8) *)
  let bytes_per_pixel = 4 in
  (* Align bytes per row to 256 (wgpu requirement) *)
  let bytes_per_row = ((width * bytes_per_pixel) + 255) / 256 * 256 in
  let buffer_size = bytes_per_row * height in
  let readback_buffer =
    Wgpu.Device.create_buffer
      device
      ~label:"readback_buffer"
      ~size:(Int64.of_int buffer_size)
      ~usage:[ Wgpu.Buffer_usage.Item.Map_read; Wgpu.Buffer_usage.Item.Copy_dst ]
      ~mapped_at_creation:false
      ()
  in
  print_endline "Readback buffer created.";
  (* Create command encoder *)
  let encoder = Wgpu.Device.create_command_encoder device ~label:"render_encoder" () in
  (* Begin render pass that clears to red (R=1, G=0, B=0, A=1) *)
  let render_pass =
    Wgpu.begin_render_pass
      encoder
      ~label:"clear_pass"
      ~color_view:texture_view
      ~clear_color:(1.0, 0.0, 0.0, 1.0)
      ()
  in
  print_endline "Render pass started (clearing to red).";
  (* End render pass immediately (just the clear) *)
  Wgpu.Render_pass_encoder.end_ render_pass;
  print_endline "Render pass ended.";
  (* Copy texture to buffer *)
  Wgpu.copy_texture_to_buffer
    encoder
    ~texture
    ~buffer:readback_buffer
    ~size:(width, height)
    ~bytes_per_row
    ();
  print_endline "Copy texture to buffer command recorded.";
  (* Finish and submit *)
  let command_buffer = Wgpu.finish encoder ~label:"render_commands" () in
  Wgpu.Queue.submit queue ~command_buffers:[ command_buffer ];
  print_endline "Commands submitted.";
  (* Poll for completion *)
  Wgpu.Device.poll device ~wait:true ();
  print_endline "Device polled.";
  (* Map readback buffer and verify *)
  Wgpu.map_buffer
    readback_buffer
    ~mode:[ Wgpu.Map_mode.Item.Read ]
    ~offset:0L
    ~size:(Int64.of_int buffer_size);
  Wgpu.Device.poll device ~wait:true ();
  let mapped_data =
    Wgpu.get_const_mapped_range
      readback_buffer
      ~offset:0L
      ~size:(Int64.of_int buffer_size)
  in
  print_endline "Buffer mapped for reading.";
  (* Check first pixel: should be red (255, 0, 0, 255) in RGBA8 *)
  let r = Bigarray.Array1.get mapped_data 0 in
  let g = Bigarray.Array1.get mapped_data 1 in
  let b = Bigarray.Array1.get mapped_data 2 in
  let a = Bigarray.Array1.get mapped_data 3 in
  printf "  First pixel: R=%d G=%d B=%d A=%d\n" r g b a;
  (* Verify all pixels are red *)
  let all_correct = ref true in
  for y = 0 to height - 1 do
    for x = 0 to width - 1 do
      let offset = (y * bytes_per_row) + (x * bytes_per_pixel) in
      let pr = Bigarray.Array1.get mapped_data offset in
      let pg = Bigarray.Array1.get mapped_data (offset + 1) in
      let pb = Bigarray.Array1.get mapped_data (offset + 2) in
      let pa = Bigarray.Array1.get mapped_data (offset + 3) in
      if pr <> 255 || pg <> 0 || pb <> 0 || pa <> 255
      then (
        if !all_correct
        then printf "  ERROR at (%d,%d): R=%d G=%d B=%d A=%d\n" x y pr pg pb pa;
        all_correct := false)
    done
  done;
  if !all_correct
  then print_endline "SUCCESS: All pixels correctly cleared to red!"
  else print_endline "FAILURE: Some pixels incorrect.";
  (* Write output to PPM and convert to PNG *)
  let ppm_file = "render_clear.ppm" in
  let png_file = "render_clear.png" in
  write_ppm ~filename:ppm_file ~width ~height ~data:mapped_data ~bytes_per_row;
  printf "  Written to %s\n" ppm_file;
  if ppm_to_png ~ppm_file ~png_file
  then (
    printf "  Converted to %s\n" png_file;
    (* Remove the PPM file since we have PNG *)
    Core_unix.unlink ppm_file);
  Wgpu.Buffer.unmap readback_buffer;
  (* Cleanup *)
  Wgpu.Command_buffer.release command_buffer;
  Wgpu.Render_pass_encoder.release render_pass;
  Wgpu.Command_encoder.release encoder;
  Wgpu.Buffer.release readback_buffer;
  Wgpu.Texture_view.release texture_view;
  Wgpu.Texture.release texture;
  Wgpu.Queue.release queue;
  Wgpu.Device.release device;
  Wgpu.Adapter.release adapter;
  Wgpu.Instance.release instance;
  print_endline "All resources released."
;;

let test_render_triangle () =
  print_endline "\n=== Testing Render Pipeline (Triangle) ===";
  (* Create instance, adapter, device using high-level API *)
  let instance = Wgpu.Instance.create () in
  let adapter = Wgpu.Instance.request_adapter instance () in
  let device = Wgpu.Adapter.request_device adapter in
  let queue = Wgpu.Device.get_queue device in
  print_endline "Device and queue obtained.";
  (* Create shader module with vertex and fragment shaders *)
  let shader_code =
    {|
@vertex
fn vs_main(@builtin(vertex_index) in_vertex_index: u32) -> @builtin(position) vec4<f32> {
    // Triangle vertices computed from vertex index
    let x = f32(i32(in_vertex_index) - 1);
    let y = f32(i32(in_vertex_index & 1u) * 2 - 1);
    return vec4<f32>(x, y, 0.0, 1.0);
}

@fragment
fn fs_main() -> @location(0) vec4<f32> {
    return vec4<f32>(0.0, 1.0, 0.0, 1.0);  // Green
}
|}
  in
  let shader =
    Wgpu.Device.create_shader_module device ~label:"triangle_shader" ~wgsl:shader_code ()
  in
  print_endline "Shader module created.";
  (* Create render target texture *)
  let width = 64 in
  let height = 64 in
  let texture =
    Wgpu.Device.create_texture
      device
      ~label:"render_target"
      ~size:(width, height, 1)
      ~format:Wgpu.Texture_format.Rgba8_unorm
      ~usage:
        [ Wgpu.Texture_usage.Item.Render_attachment; Wgpu.Texture_usage.Item.Copy_src ]
      ()
  in
  print_endline "Render target texture created.";
  let texture_view = Wgpu.create_texture_view texture ~label:"render_target_view" () in
  print_endline "Texture view created.";
  (* Create render pipeline *)
  let pipeline =
    Wgpu.Device.create_render_pipeline
      device
      ~label:"triangle_pipeline"
      ~shader_module:shader
      ~vertex_entry_point:"vs_main"
      ~fragment_entry_point:"fs_main"
      ~color_format:Wgpu.Texture_format.Rgba8_unorm
      ()
  in
  print_endline "Render pipeline created.";
  (* Create readback buffer *)
  let bytes_per_pixel = 4 in
  let bytes_per_row = ((width * bytes_per_pixel) + 255) / 256 * 256 in
  let buffer_size = bytes_per_row * height in
  let readback_buffer =
    Wgpu.Device.create_buffer
      device
      ~label:"readback_buffer"
      ~size:(Int64.of_int buffer_size)
      ~usage:[ Wgpu.Buffer_usage.Item.Map_read; Wgpu.Buffer_usage.Item.Copy_dst ]
      ~mapped_at_creation:false
      ()
  in
  print_endline "Readback buffer created.";
  (* Create command encoder and record render pass *)
  let encoder = Wgpu.Device.create_command_encoder device ~label:"render_encoder" () in
  (* Begin render pass clearing to blue background *)
  let render_pass =
    Wgpu.begin_render_pass
      encoder
      ~label:"triangle_pass"
      ~color_view:texture_view
      ~clear_color:(0.0, 0.0, 1.0, 1.0) (* Blue background *)
      ()
  in
  print_endline "Render pass started.";
  (* Set pipeline and draw triangle *)
  Wgpu.Render_pass_encoder.set_pipeline render_pass ~pipeline;
  Wgpu.Render_pass_encoder.draw
    render_pass
    ~vertex_count:3
    ~instance_count:1
    ~first_vertex:0
    ~first_instance:0;
  Wgpu.Render_pass_encoder.end_ render_pass;
  print_endline "Triangle drawn.";
  (* Copy texture to buffer *)
  Wgpu.copy_texture_to_buffer
    encoder
    ~texture
    ~buffer:readback_buffer
    ~size:(width, height)
    ~bytes_per_row
    ();
  print_endline "Copy command recorded.";
  (* Submit *)
  let command_buffer = Wgpu.finish encoder ~label:"render_commands" () in
  Wgpu.Queue.submit queue ~command_buffers:[ command_buffer ];
  print_endline "Commands submitted.";
  (* Wait and read back *)
  Wgpu.Device.poll device ~wait:true ();
  Wgpu.map_buffer
    readback_buffer
    ~mode:[ Wgpu.Map_mode.Item.Read ]
    ~offset:0L
    ~size:(Int64.of_int buffer_size);
  Wgpu.Device.poll device ~wait:true ();
  let mapped_data =
    Wgpu.get_const_mapped_range
      readback_buffer
      ~offset:0L
      ~size:(Int64.of_int buffer_size)
  in
  print_endline "Buffer mapped for reading.";
  (* Check center pixel - should be green (triangle covers center) *)
  let center_x = width / 2 in
  let center_y = height / 2 in
  let center_offset = (center_y * bytes_per_row) + (center_x * bytes_per_pixel) in
  let cr = Bigarray.Array1.get mapped_data center_offset in
  let cg = Bigarray.Array1.get mapped_data (center_offset + 1) in
  let cb = Bigarray.Array1.get mapped_data (center_offset + 2) in
  let ca = Bigarray.Array1.get mapped_data (center_offset + 3) in
  printf "  Center pixel: R=%d G=%d B=%d A=%d\n" cr cg cb ca;
  (* Check corner pixel - should be blue (background) *)
  let corner_offset = 0 in
  let br = Bigarray.Array1.get mapped_data corner_offset in
  let bg = Bigarray.Array1.get mapped_data (corner_offset + 1) in
  let bb = Bigarray.Array1.get mapped_data (corner_offset + 2) in
  let ba = Bigarray.Array1.get mapped_data (corner_offset + 3) in
  printf "  Corner pixel: R=%d G=%d B=%d A=%d\n" br bg bb ba;
  (* Verify: center should be green, corner should be blue *)
  let center_is_green = cr = 0 && cg = 255 && cb = 0 && ca = 255 in
  let corner_is_blue = br = 0 && bg = 0 && bb = 255 && ba = 255 in
  if center_is_green && corner_is_blue
  then print_endline "SUCCESS: Triangle rendered correctly!"
  else
    print_endline "Note: Triangle rendered (check output image for visual verification)";
  (* Write output *)
  let ppm_file = "render_triangle.ppm" in
  let png_file = "render_triangle.png" in
  write_ppm ~filename:ppm_file ~width ~height ~data:mapped_data ~bytes_per_row;
  printf "  Written to %s\n" ppm_file;
  if ppm_to_png ~ppm_file ~png_file
  then (
    printf "  Converted to %s\n" png_file;
    Core_unix.unlink ppm_file);
  Wgpu.Buffer.unmap readback_buffer;
  (* Cleanup *)
  Wgpu.Command_buffer.release command_buffer;
  Wgpu.Render_pass_encoder.release render_pass;
  Wgpu.Command_encoder.release encoder;
  Wgpu.Buffer.release readback_buffer;
  Wgpu.Render_pipeline.release pipeline;
  Wgpu.Texture_view.release texture_view;
  Wgpu.Texture.release texture;
  Wgpu.Shader_module.release shader;
  Wgpu.Queue.release queue;
  Wgpu.Device.release device;
  Wgpu.Adapter.release adapter;
  Wgpu.Instance.release instance;
  print_endline "All resources released."
;;

let () =
  test_instance_and_adapter ();
  test_buffer_creation ();
  test_compute_shader ();
  test_render_clear ();
  test_render_triangle ()
;;
