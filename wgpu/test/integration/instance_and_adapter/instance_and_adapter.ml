open! Core

let cleanup ~instance ~adapter =
  Wgpu.Adapter.release adapter;
  Wgpu.Instance.release instance
;;

let () =
  let instance = Wgpu.Instance.create () in
  let adapter = Wgpu.Instance.request_adapter instance () in
  let info = Wgpu.Adapter.get_info adapter in
  print_s
    [%message
      ""
        ~vendor:(info.vendor : string)
        ~architecture:(info.architecture : string)
        ~device:(info.device : string)
        ~description:(info.description : string)
        ~backend_type:(Wgpu.Backend_type.to_int info.backend_type : int)
        ~adapter_type:(Wgpu.Adapter_type.to_int info.adapter_type : int)];
  cleanup ~instance ~adapter
;;
