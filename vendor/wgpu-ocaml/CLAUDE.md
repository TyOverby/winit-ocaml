# wgpu-native-ocaml

This project aims to implement idomatic OCaml bindings to Rust's native webgpu
project (https://github.com/gfx-rs/wgpu-native).

wgpu-native is a rust library that implements and exposes the webgpu C headers
API (https://github.com/webgpu-native/webgpu-headers).

## Project structure
```
codegen/     # Code generator for low level and high level bindings
  templates/ # Storage for hardcoded functions 
    low/     # hardcoded low-level binding functions 
    high/    # hardcoded high-level binding functions
  test/      # unit tests for code generation
low/  # Low level webgpu bindings (generated)
high/ # High level webgpu bindings (generated)
tasks/       # Storage for issue-tracker tasks in markdown format
  open/      # Open issues
  triage/    # Tasks that we aren't sure about working
  completed/ # Completed tasks
test/           # Tests of the high level API
  assets/       # Image assets to use during testing
  util/         # Misc testing utilities
  integration/  # Handwritten integration tests
  fundamentals/ # Tests that mimic the lesson/example layout of the webgpufundamentals.org website. WIP
vendor/ # Vendored copy of the rust wgpu project
webgpu_fundamentals/ # Scraped javascript examples from the webgpufundamentals.org website
```

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
