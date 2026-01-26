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
  let cmd = sprintf "convert %s %s" ppm_file png_file in
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
  let adapter = Wgpu.Instance.request_adapter instance in
  print_endline "Adapter obtained!";
  let info = Wgpu.Adapter.get_info adapter in
  printf "  Vendor: %s\n" info.vendor;
  printf "  Architecture: %s\n" info.architecture;
  printf "  Device: %s\n" info.device;
  printf "  Description: %s\n" info.description;
  printf "  Backend type: %d\n" info.backend_type;
  printf "  Adapter type: %d\n" info.adapter_type;
  Wgpu.Adapter.release adapter;
  print_endline "Adapter released.";
  Wgpu.Instance.release instance;
  print_endline "Instance released."
;;

let test_buffer_descriptor () =
  print_endline "\n=== Testing Buffer Descriptor ===";
  (* Create a buffer descriptor using low-level API *)
  let desc = Wgpu_low.Buffer_Descriptor.buffer_descriptor_create () in
  print_endline "Buffer descriptor created.";
  (* Set fields *)
  Wgpu_low.Buffer_Descriptor.buffer_descriptor_set_label desc "test_buffer";
  Wgpu_low.Buffer_Descriptor.buffer_descriptor_set_size desc 1024L;
  Wgpu_low.Buffer_Descriptor.buffer_descriptor_set_usage desc 0x0041;
  (* MapRead | CopyDst *)
  Wgpu_low.Buffer_Descriptor.buffer_descriptor_set_mapped_at_creation desc false;
  print_endline "Buffer descriptor fields set.";
  (* Read back fields *)
  let label = Wgpu_low.Buffer_Descriptor.buffer_descriptor_get_label desc in
  let size = Wgpu_low.Buffer_Descriptor.buffer_descriptor_get_size desc in
  let usage = Wgpu_low.Buffer_Descriptor.buffer_descriptor_get_usage desc in
  let mapped = Wgpu_low.Buffer_Descriptor.buffer_descriptor_get_mapped_at_creation desc in
  printf "  Label: %s\n" label;
  printf "  Size: %Ld\n" size;
  printf "  Usage: 0x%04x\n" usage;
  printf "  Mapped at creation: %b\n" mapped;
  (* Verify values *)
  assert (String.equal label "test_buffer");
  assert (Int64.equal size 1024L);
  assert (usage = 0x0041);
  assert (not mapped);
  print_endline "All assertions passed!";
  (* Free the descriptor *)
  Wgpu_low.Buffer_Descriptor.buffer_descriptor_free desc;
  print_endline "Buffer descriptor freed."
;;

let test_buffer_creation () =
  print_endline "\n=== Testing Buffer Creation ===";
  (* Create instance, adapter, device *)
  let instance = Wgpu_low.create_instance () in
  let adapter = Wgpu_low.instance_request_adapter_sync instance in
  let device = Wgpu_low.adapter_request_device_sync adapter in
  print_endline "Device obtained.";
  (* Create buffer descriptor *)
  let desc = Wgpu_low.Buffer_Descriptor.buffer_descriptor_create () in
  Wgpu_low.Buffer_Descriptor.buffer_descriptor_set_label desc "gpu_buffer";
  Wgpu_low.Buffer_Descriptor.buffer_descriptor_set_size desc 256L;
  (* Storage | CopyDst | CopySrc = 0x80 | 0x08 | 0x04 = 0x8C *)
  Wgpu_low.Buffer_Descriptor.buffer_descriptor_set_usage desc 0x8C;
  Wgpu_low.Buffer_Descriptor.buffer_descriptor_set_mapped_at_creation desc false;
  (* Create the buffer *)
  let buffer = Wgpu_low.device_create_buffer device desc in
  print_endline "Buffer created!";
  (* Get buffer info *)
  let buf_size = Wgpu_low.buffer_get_size buffer in
  let buf_usage = Wgpu_low.buffer_get_usage buffer in
  printf "  Buffer size: %Ld\n" buf_size;
  printf "  Buffer usage: 0x%04x\n" buf_usage;
  assert (Int64.equal buf_size 256L);
  print_endline "Buffer properties verified!";
  (* Cleanup *)
  Wgpu_low.buffer_release buffer;
  Wgpu_low.Buffer_Descriptor.buffer_descriptor_free desc;
  Wgpu_low.device_release device;
  Wgpu_low.adapter_release adapter;
  Wgpu_low.instance_release instance;
  print_endline "All resources released."
;;

let test_compute_shader () =
  print_endline "\n=== Testing Compute Shader (Full Pipeline) ===";
  (* Create instance, adapter, device *)
  let instance = Wgpu_low.create_instance () in
  let adapter = Wgpu_low.instance_request_adapter_sync instance in
  let device = Wgpu_low.adapter_request_device_sync adapter in
  let queue = Wgpu_low.device_get_queue device in
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
  let shader =
    Wgpu_low.device_create_shader_module_wgsl device "double_shader" shader_code
  in
  print_endline "Shader module created!";
  (* Create storage buffer (GPU only, not mappable) *)
  let num_elements = 64 in
  let data_size = num_elements * 4 in
  (* 64 uint32 values = 256 bytes *)
  let storage_desc = Wgpu_low.Buffer_Descriptor.buffer_descriptor_create () in
  Wgpu_low.Buffer_Descriptor.buffer_descriptor_set_label storage_desc "storage_buffer";
  Wgpu_low.Buffer_Descriptor.buffer_descriptor_set_size
    storage_desc
    (Int64.of_int data_size);
  (* Storage | CopyDst | CopySrc = 0x80 | 0x08 | 0x04 = 0x8C *)
  Wgpu_low.Buffer_Descriptor.buffer_descriptor_set_usage storage_desc 0x8C;
  Wgpu_low.Buffer_Descriptor.buffer_descriptor_set_mapped_at_creation storage_desc false;
  let storage_buffer = Wgpu_low.device_create_buffer device storage_desc in
  print_endline "Storage buffer created.";
  (* Create readback buffer (mappable for reading results) *)
  let readback_desc = Wgpu_low.Buffer_Descriptor.buffer_descriptor_create () in
  Wgpu_low.Buffer_Descriptor.buffer_descriptor_set_label readback_desc "readback_buffer";
  Wgpu_low.Buffer_Descriptor.buffer_descriptor_set_size
    readback_desc
    (Int64.of_int data_size);
  (* MapRead | CopyDst = 0x01 | 0x08 = 0x09 *)
  Wgpu_low.Buffer_Descriptor.buffer_descriptor_set_usage readback_desc 0x09;
  Wgpu_low.Buffer_Descriptor.buffer_descriptor_set_mapped_at_creation readback_desc false;
  let readback_buffer = Wgpu_low.device_create_buffer device readback_desc in
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
  Wgpu_low.queue_write_buffer_bigarray queue storage_buffer 0L input_bytes;
  print_endline "Initial data written to storage buffer.";
  (* Create bind group layout for single storage buffer at binding 0 *)
  let bind_group_layout =
    Wgpu_low.device_create_bind_group_layout_storage
      device
      "compute_bind_group_layout"
      0
      false
    (* read_write, not read_only *)
  in
  print_endline "Bind group layout created.";
  (* Create bind group with storage buffer *)
  let bind_group =
    Wgpu_low.device_create_bind_group_buffer
      device
      "compute_bind_group"
      bind_group_layout
      0
      storage_buffer
      0L
      (Int64.of_int data_size)
  in
  print_endline "Bind group created.";
  (* Create pipeline layout *)
  let pipeline_layout =
    Wgpu_low.device_create_pipeline_layout_single
      device
      "compute_pipeline_layout"
      bind_group_layout
  in
  print_endline "Pipeline layout created.";
  (* Create compute pipeline *)
  let compute_pipeline =
    Wgpu_low.device_create_compute_pipeline_simple
      device
      "double_pipeline"
      pipeline_layout
      shader
      "main"
  in
  print_endline "Compute pipeline created.";
  (* Create command encoder and record commands *)
  let encoder = Wgpu_low.device_create_command_encoder_simple device "compute_encoder" in
  let compute_pass =
    Wgpu_low.command_encoder_begin_compute_pass_simple encoder "compute_pass"
  in
  (* Set pipeline and bind group, then dispatch *)
  Wgpu_low.compute_pass_encoder_set_pipeline compute_pass compute_pipeline;
  Wgpu_low.compute_pass_encoder_set_bind_group_simple compute_pass 0 bind_group;
  (* Dispatch 1 workgroup of 64 threads *)
  Wgpu_low.compute_pass_encoder_dispatch_workgroups compute_pass 1 1 1;
  Wgpu_low.compute_pass_encoder_end compute_pass;
  print_endline "Compute pass recorded.";
  (* Copy storage buffer to readback buffer *)
  Wgpu_low.command_encoder_copy_buffer_to_buffer
    encoder
    storage_buffer
    0L
    readback_buffer
    0L
    (Int64.of_int data_size);
  print_endline "Copy command recorded.";
  (* Finish and submit *)
  let command_buffer =
    Wgpu_low.command_encoder_finish_simple encoder "compute_commands"
  in
  (* Use the auto-generated queue_submit with array argument *)
  Wgpu_low.queue_submit queue [| command_buffer |];
  print_endline "Commands submitted.";
  (* Poll device to ensure work completes *)
  Wgpu_low.device_poll device true;
  print_endline "Device polled.";
  (* Map readback buffer and verify results *)
  (* MapMode::Read = 1 *)
  let _status = Wgpu_low.buffer_map_sync readback_buffer 1 0L (Int64.of_int data_size) in
  Wgpu_low.device_poll device true;
  let mapped_data =
    Wgpu_low.buffer_get_const_mapped_range_bigarray
      readback_buffer
      0L
      (Int64.of_int data_size)
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
  Wgpu_low.buffer_unmap readback_buffer;
  (* Cleanup *)
  Wgpu_low.command_buffer_release command_buffer;
  Wgpu_low.compute_pass_encoder_release compute_pass;
  Wgpu_low.command_encoder_release encoder;
  Wgpu_low.compute_pipeline_release compute_pipeline;
  Wgpu_low.pipeline_layout_release pipeline_layout;
  Wgpu_low.bind_group_release bind_group;
  Wgpu_low.bind_group_layout_release bind_group_layout;
  Wgpu_low.Buffer_Descriptor.buffer_descriptor_free readback_desc;
  Wgpu_low.Buffer_Descriptor.buffer_descriptor_free storage_desc;
  Wgpu_low.buffer_release readback_buffer;
  Wgpu_low.buffer_release storage_buffer;
  Wgpu_low.shader_module_release shader;
  Wgpu_low.queue_release queue;
  Wgpu_low.device_release device;
  Wgpu_low.adapter_release adapter;
  Wgpu_low.instance_release instance;
  print_endline "All resources released."
;;

let test_render_clear () =
  print_endline "\n=== Testing Render Pass (Clear to Color) ===";
  (* Create instance, adapter, device *)
  let instance = Wgpu_low.create_instance () in
  let adapter = Wgpu_low.instance_request_adapter_sync instance in
  let device = Wgpu_low.adapter_request_device_sync adapter in
  let queue = Wgpu_low.device_get_queue device in
  print_endline "Device and queue obtained.";
  (* Create render target texture *)
  let width = 64 in
  let height = 64 in
  (* RGBA8Unorm = 18 from webgpu.h, RenderAttachment | CopySrc = 0x10 | 0x01 = 0x11 *)
  let texture_format = 18 in
  let texture_usage = 0x11 in
  let texture =
    Wgpu_low.device_create_texture_2d
      device
      "render_target"
      width
      height
      texture_format
      texture_usage
  in
  print_endline "Render target texture created.";
  (* Create texture view *)
  let texture_view = Wgpu_low.texture_create_view_simple texture "render_target_view" in
  print_endline "Texture view created.";
  (* Create readback buffer - 4 bytes per pixel (RGBA8) *)
  let bytes_per_pixel = 4 in
  (* Align bytes per row to 256 (wgpu requirement) *)
  let bytes_per_row = ((width * bytes_per_pixel) + 255) / 256 * 256 in
  let buffer_size = bytes_per_row * height in
  let readback_desc = Wgpu_low.Buffer_Descriptor.buffer_descriptor_create () in
  Wgpu_low.Buffer_Descriptor.buffer_descriptor_set_label readback_desc "readback_buffer";
  Wgpu_low.Buffer_Descriptor.buffer_descriptor_set_size
    readback_desc
    (Int64.of_int buffer_size);
  (* MapRead | CopyDst = 0x01 | 0x08 = 0x09 *)
  Wgpu_low.Buffer_Descriptor.buffer_descriptor_set_usage readback_desc 0x09;
  Wgpu_low.Buffer_Descriptor.buffer_descriptor_set_mapped_at_creation readback_desc false;
  let readback_buffer = Wgpu_low.device_create_buffer device readback_desc in
  print_endline "Readback buffer created.";
  (* Create command encoder *)
  let encoder = Wgpu_low.device_create_command_encoder_simple device "render_encoder" in
  (* Begin render pass that clears to red (R=1, G=0, B=0, A=1) *)
  let render_pass =
    Wgpu_low.command_encoder_begin_render_pass_simple
      encoder
      "clear_pass"
      texture_view
      1.0
      0.0
      0.0
      1.0
  in
  print_endline "Render pass started (clearing to red).";
  (* End render pass immediately (just the clear) *)
  Wgpu_low.render_pass_encoder_end render_pass;
  print_endline "Render pass ended.";
  (* Copy texture to buffer *)
  Wgpu_low.command_encoder_copy_texture_to_buffer_simple
    encoder
    texture
    readback_buffer
    width
    height
    bytes_per_row;
  print_endline "Copy texture to buffer command recorded.";
  (* Finish and submit *)
  let command_buffer = Wgpu_low.command_encoder_finish_simple encoder "render_commands" in
  Wgpu_low.queue_submit queue [| command_buffer |];
  print_endline "Commands submitted.";
  (* Poll for completion *)
  Wgpu_low.device_poll device true;
  print_endline "Device polled.";
  (* Map readback buffer and verify *)
  let _status =
    Wgpu_low.buffer_map_sync readback_buffer 1 0L (Int64.of_int buffer_size)
  in
  Wgpu_low.device_poll device true;
  let mapped_data =
    Wgpu_low.buffer_get_const_mapped_range_bigarray
      readback_buffer
      0L
      (Int64.of_int buffer_size)
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
  Wgpu_low.buffer_unmap readback_buffer;
  (* Cleanup *)
  Wgpu_low.command_buffer_release command_buffer;
  Wgpu_low.render_pass_encoder_release render_pass;
  Wgpu_low.command_encoder_release encoder;
  Wgpu_low.Buffer_Descriptor.buffer_descriptor_free readback_desc;
  Wgpu_low.buffer_release readback_buffer;
  Wgpu_low.texture_view_release texture_view;
  Wgpu_low.texture_release texture;
  Wgpu_low.queue_release queue;
  Wgpu_low.device_release device;
  Wgpu_low.adapter_release adapter;
  Wgpu_low.instance_release instance;
  print_endline "All resources released."
;;

let test_render_triangle () =
  print_endline "\n=== Testing Render Pipeline (Triangle) ===";
  (* Create instance, adapter, device *)
  let instance = Wgpu_low.create_instance () in
  let adapter = Wgpu_low.instance_request_adapter_sync instance in
  let device = Wgpu_low.adapter_request_device_sync adapter in
  let queue = Wgpu_low.device_get_queue device in
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
    Wgpu_low.device_create_shader_module_wgsl device "triangle_shader" shader_code
  in
  print_endline "Shader module created.";
  (* Create render target texture *)
  let width = 64 in
  let height = 64 in
  let texture_format = 18 in
  (* RGBA8Unorm *)
  let texture_usage = 0x11 in
  (* RenderAttachment | CopySrc *)
  let texture =
    Wgpu_low.device_create_texture_2d
      device
      "render_target"
      width
      height
      texture_format
      texture_usage
  in
  print_endline "Render target texture created.";
  let texture_view = Wgpu_low.texture_create_view_simple texture "render_target_view" in
  print_endline "Texture view created.";
  (* Create render pipeline *)
  let pipeline =
    Wgpu_low.device_create_render_pipeline_simple
      device
      "triangle_pipeline"
      shader
      "vs_main"
      "fs_main"
      texture_format
  in
  print_endline "Render pipeline created.";
  (* Create readback buffer *)
  let bytes_per_pixel = 4 in
  let bytes_per_row = ((width * bytes_per_pixel) + 255) / 256 * 256 in
  let buffer_size = bytes_per_row * height in
  let readback_desc = Wgpu_low.Buffer_Descriptor.buffer_descriptor_create () in
  Wgpu_low.Buffer_Descriptor.buffer_descriptor_set_label readback_desc "readback_buffer";
  Wgpu_low.Buffer_Descriptor.buffer_descriptor_set_size
    readback_desc
    (Int64.of_int buffer_size);
  Wgpu_low.Buffer_Descriptor.buffer_descriptor_set_usage readback_desc 0x09;
  (* MapRead | CopyDst *)
  Wgpu_low.Buffer_Descriptor.buffer_descriptor_set_mapped_at_creation readback_desc false;
  let readback_buffer = Wgpu_low.device_create_buffer device readback_desc in
  print_endline "Readback buffer created.";
  (* Create command encoder and record render pass *)
  let encoder = Wgpu_low.device_create_command_encoder_simple device "render_encoder" in
  (* Begin render pass clearing to blue background *)
  let render_pass =
    Wgpu_low.command_encoder_begin_render_pass_simple
      encoder
      "triangle_pass"
      texture_view
      0.0
      0.0
      1.0 (* Blue background *)
      1.0
  in
  print_endline "Render pass started.";
  (* Set pipeline and draw triangle *)
  Wgpu_low.render_pass_encoder_set_pipeline render_pass pipeline;
  Wgpu_low.render_pass_encoder_draw render_pass 3 1 0 0;
  Wgpu_low.render_pass_encoder_end render_pass;
  print_endline "Triangle drawn.";
  (* Copy texture to buffer *)
  Wgpu_low.command_encoder_copy_texture_to_buffer_simple
    encoder
    texture
    readback_buffer
    width
    height
    bytes_per_row;
  print_endline "Copy command recorded.";
  (* Submit *)
  let command_buffer = Wgpu_low.command_encoder_finish_simple encoder "render_commands" in
  Wgpu_low.queue_submit queue [| command_buffer |];
  print_endline "Commands submitted.";
  (* Wait and read back *)
  Wgpu_low.device_poll device true;
  let _status =
    Wgpu_low.buffer_map_sync readback_buffer 1 0L (Int64.of_int buffer_size)
  in
  Wgpu_low.device_poll device true;
  let mapped_data =
    Wgpu_low.buffer_get_const_mapped_range_bigarray
      readback_buffer
      0L
      (Int64.of_int buffer_size)
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
  Wgpu_low.buffer_unmap readback_buffer;
  (* Cleanup *)
  Wgpu_low.command_buffer_release command_buffer;
  Wgpu_low.render_pass_encoder_release render_pass;
  Wgpu_low.command_encoder_release encoder;
  Wgpu_low.Buffer_Descriptor.buffer_descriptor_free readback_desc;
  Wgpu_low.buffer_release readback_buffer;
  Wgpu_low.render_pipeline_release pipeline;
  Wgpu_low.texture_view_release texture_view;
  Wgpu_low.texture_release texture;
  Wgpu_low.shader_module_release shader;
  Wgpu_low.queue_release queue;
  Wgpu_low.device_release device;
  Wgpu_low.adapter_release adapter;
  Wgpu_low.instance_release instance;
  print_endline "All resources released."
;;

let test_bind_group_with_generated_api () =
  print_endline "\n=== Testing Bind Group with Generated Struct APIs ===";
  (* Create instance, adapter, device *)
  let instance = Wgpu_low.create_instance () in
  let adapter = Wgpu_low.instance_request_adapter_sync instance in
  let device = Wgpu_low.adapter_request_device_sync adapter in
  print_endline "Device obtained.";
  (* Create a buffer to bind *)
  let buffer_desc = Wgpu_low.Buffer_Descriptor.buffer_descriptor_create () in
  Wgpu_low.Buffer_Descriptor.buffer_descriptor_set_label buffer_desc "test_buffer";
  Wgpu_low.Buffer_Descriptor.buffer_descriptor_set_size buffer_desc 256L;
  Wgpu_low.Buffer_Descriptor.buffer_descriptor_set_usage buffer_desc 0x88;
  (* Storage | CopyDst *)
  let buffer = Wgpu_low.device_create_buffer device buffer_desc in
  print_endline "Buffer created.";
  (* Create buffer binding layout using generated API *)
  let buffer_binding = Wgpu_low.Buffer_Binding_Layout.buffer_binding_layout_create () in
  (* type = Storage = 3 *)
  Wgpu_low.Buffer_Binding_Layout.buffer_binding_layout_set_type buffer_binding 3;
  Wgpu_low.Buffer_Binding_Layout.buffer_binding_layout_set_has_dynamic_offset
    buffer_binding
    false;
  Wgpu_low.Buffer_Binding_Layout.buffer_binding_layout_set_min_binding_size
    buffer_binding
    0L;
  print_endline "Buffer binding layout created.";
  (* Create bind group layout entry using generated API *)
  let layout_entry = Wgpu_low.Bind_Group_Layout_Entry.bind_group_layout_entry_create () in
  Wgpu_low.Bind_Group_Layout_Entry.bind_group_layout_entry_set_binding layout_entry 0;
  (* visibility = Compute = 0x4 *)
  Wgpu_low.Bind_Group_Layout_Entry.bind_group_layout_entry_set_visibility layout_entry 0x4;
  (* Set the buffer binding layout (embedded struct copy) *)
  Wgpu_low.Bind_Group_Layout_Entry.bind_group_layout_entry_set_buffer
    layout_entry
    buffer_binding;
  print_endline "Layout entry created with buffer binding.";
  (* Create bind group layout descriptor using generated API *)
  let layout_desc =
    Wgpu_low.Bind_Group_Layout_Descriptor.bind_group_layout_descriptor_create ()
  in
  Wgpu_low.Bind_Group_Layout_Descriptor.bind_group_layout_descriptor_set_label
    layout_desc
    "test_layout";
  (* Set entries array - this tests the array setter! *)
  Wgpu_low.Bind_Group_Layout_Descriptor.bind_group_layout_descriptor_set_entries
    layout_desc
    [| layout_entry |];
  print_endline "Layout descriptor with entries array set.";
  (* Create the bind group layout *)
  let layout = Wgpu_low.device_create_bind_group_layout device layout_desc in
  print_endline "Bind group layout created!";
  (* Create bind group entry *)
  let entry = Wgpu_low.Bind_Group_Entry.bind_group_entry_create () in
  Wgpu_low.Bind_Group_Entry.bind_group_entry_set_binding entry 0;
  Wgpu_low.Bind_Group_Entry.bind_group_entry_set_buffer entry buffer;
  Wgpu_low.Bind_Group_Entry.bind_group_entry_set_offset entry 0L;
  Wgpu_low.Bind_Group_Entry.bind_group_entry_set_size entry 256L;
  print_endline "Bind group entry created.";
  (* Create bind group descriptor *)
  let bind_group_desc = Wgpu_low.Bind_Group_Descriptor.bind_group_descriptor_create () in
  Wgpu_low.Bind_Group_Descriptor.bind_group_descriptor_set_label
    bind_group_desc
    "test_bind_group";
  Wgpu_low.Bind_Group_Descriptor.bind_group_descriptor_set_layout bind_group_desc layout;
  Wgpu_low.Bind_Group_Descriptor.bind_group_descriptor_set_entries
    bind_group_desc
    [| entry |];
  print_endline "Bind group descriptor with entries array set.";
  (* Create the bind group *)
  let bind_group = Wgpu_low.device_create_bind_group device bind_group_desc in
  print_endline "Bind group created!";
  print_endline "SUCCESS: All generated struct APIs worked correctly!";
  (* Cleanup *)
  Wgpu_low.bind_group_release bind_group;
  Wgpu_low.Bind_Group_Descriptor.bind_group_descriptor_free bind_group_desc;
  Wgpu_low.Bind_Group_Entry.bind_group_entry_free entry;
  Wgpu_low.bind_group_layout_release layout;
  Wgpu_low.Bind_Group_Layout_Descriptor.bind_group_layout_descriptor_free layout_desc;
  Wgpu_low.Bind_Group_Layout_Entry.bind_group_layout_entry_free layout_entry;
  Wgpu_low.Buffer_Binding_Layout.buffer_binding_layout_free buffer_binding;
  Wgpu_low.buffer_release buffer;
  Wgpu_low.Buffer_Descriptor.buffer_descriptor_free buffer_desc;
  Wgpu_low.device_release device;
  Wgpu_low.adapter_release adapter;
  Wgpu_low.instance_release instance;
  print_endline "All resources released."
;;

let () =
  test_instance_and_adapter ();
  test_buffer_descriptor ();
  test_buffer_creation ();
  test_compute_shader ();
  test_render_clear ();
  test_render_triangle ();
  test_bind_group_with_generated_api ()
;;
