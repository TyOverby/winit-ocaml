open! Core

let init () =
  let instance = Wgpu.Instance.create () in
  let adapter = Wgpu.Instance.request_adapter instance () in
  let device = Wgpu.Adapter.request_device adapter in
  instance, adapter, device
;;

let cleanup ~instance ~adapter ~device ~buffer =
  Wgpu.Buffer.release buffer;
  Wgpu.Device.release device;
  Wgpu.Adapter.release adapter;
  Wgpu.Instance.release instance;
  ()
;;

let () =
  let instance, adapter, device = init () in
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
  let buf_size = Wgpu.Buffer.get_size buffer in
  let buf_usage = Wgpu.Buffer.get_usage buffer in
  print_s [%message "" ~buffer_size:(buf_size : int64) ~buffer_usage:(buf_usage : int)];
  assert (Int64.equal buf_size 256L);
  cleanup ~instance ~adapter ~device ~buffer
;;
