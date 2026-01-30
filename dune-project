(lang dune 3.5)

(name winit)

(package
 (name winit)
 (synopsis "OCaml bindings for winit - cross-platform window creation and event handling"))

(package
 (name softbuffer)
 (synopsis "OCaml bindings for softbuffer - pixel buffer rendering")
 (depends winit))

(package
 (name wgpu)
 (synopsis "OCaml bindings to wgpu-native (WebGPU)")
 (depends
  (ocaml (>= 4.14.0))
  dune
  (ctypes (>= 0.20.0))))
