open! Core

let () =
  print_endline "Creating wgpu instance...";
  let instance = Wgpu.Instance.create () in
  print_endline "Instance created successfully!";
  Wgpu.Instance.release instance;
  print_endline "Instance released."
;;
