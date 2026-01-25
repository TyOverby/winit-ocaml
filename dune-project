(lang dune 3.0)

(name wgpu)

(generate_opam_files true)

(source
 (github TyOverby/wgpu-native-ocaml))

(authors "Ty Overby")

(maintainers "Ty Overby")

(license MIT)

(documentation https://github.com/TyOverby/wgpu-native-ocaml)

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
   (>= 0.20.0))))
