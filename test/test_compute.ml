open! Core

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

let () =
  test_instance_and_adapter ();
  test_buffer_descriptor ();
  test_buffer_creation ()
;;
