# wgpu-native-ocaml

This project aims to implement idomatic OCaml bindings to Rust's native webgpu
project (https://github.com/gfx-rs/wgpu-native).

wgpu-native is a rust library that implements and exposes the webgpu C headers
API (https://github.com/webgpu-native/webgpu-headers).

## Available resources
The wgpu-native git repo has been vendored in `./vendor/wgpu-native/` and the
webgpu-headers git repo can be found in
`./vendor/wgpu-native/ffi/webgpu-headers/`.

The full webgpu C header is `./vendor/wgpu-native/ffi/webgpu-headers/webgpu.h`
and a yml file containing a language-agnostic description of the API is in
`./vendor/wgpu-native/ffi/webgpu-headers/webgpu.yml`

The wgpu-native wiki is in `./vendor/wgpu-native-wiki`, which has a "getting
started" page that might be helpful.

An opam executable is available in the working directory `./opam`.

## Developing

Run `dune fmt > /dev/null || true` regularly, and run `dune build @check`
before commiting, ensuring no warnings are present.
