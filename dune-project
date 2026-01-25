(lang dune 3.0)

(name wgpu)

(generate_opam_files true)

(source
 (github anthropics/wgpu-native-ocaml))

(authors "Anthropic")

(maintainers "Anthropic")

(license MIT)

(documentation https://github.com/anthropics/wgpu-native-ocaml)

(package
 (name wgpu)
 (synopsis "OCaml bindings to wgpu-native (WebGPU)")
 (description
  "Idiomatic OCaml bindings to wgpu-native, providing access to modern GPU APIs through WebGPU.")
 (depends
  (ocaml
   (>= 4.14.0))
  dune
  (ctypes
   (>= 0.20.0))
  ctypes-foreign
  yaml))
