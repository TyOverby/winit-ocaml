open! Core

let () =
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
