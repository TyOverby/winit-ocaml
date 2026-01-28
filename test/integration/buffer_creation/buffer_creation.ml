open! Core

let () =
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
