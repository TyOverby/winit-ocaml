# wgpu-native-ocaml

This project aims to implement idomatic OCaml bindings to Rust's native webgpu project (https://github.com/gfx-rs/wgpu-native).

wgpu-native is a rust library that implements and exposes the webgpu C headers API (https://github.com/webgpu-native/webgpu-headers).

## Available resources
The wgpu-native git repo has been vendored in `./vendor/wgpu-native/` and the webgpu-headers git repo can be found in `./vendor/wgpu-native/ffi/webgpu-headers/`.

The full webgpu C header is `./vendor/wgpu-native/ffi/webgpu-headers/webgpu.h` and a yml file containing a language-agnostic description of the API is in `./vendor/wgpu-native/ffi/webgpu-headers/webgpu.yml`

The wgpu-native wiki is in `./vendor/wgpu-native-wiki`, which has a "getting started" page that might be helpful.

## Broad plan

1. Using the `.h` file, build a generator that produces low-level bindings to the APIs.
2. Using the `yml` file, write a generator that produces high-level, idiomatic ocaml code which calls out to the APIs in the low-level bindings.

## High level API goals

- Be safe
  - Type safety is paramount (not able to confuse values that should be different kinds of objects)
  - Memory safe (finalizers or explicit destructors shouldn't be able to free parent resources before children)
- Be ergonomic 
  - Break the API up into modules when it makes sense
  - Follow Jane Street API guidelines
    - Types are always named `t` and live inside the modules that contain their functionality 
    - Within a module, parameters should be either optional or named, with `t` values being the only positional (unnamed) arg 
  - use optional parameters when applicable
- Be readable
  - Generate a `.mli` file for the high level bindings, not just a `.ml` - Include comments in the `.mli` code that are associated with the functions and types that are described

## Developing

A fast developer iteration loop is critical!  Make sure to always write code in such a way that it's easy to validate your work!  

Build test executables and run them regularly.  (These tests may need to be headless, you won't always have access to a display driver).  If you can have a headless binary produce `.png` files that you can read, that's excellent!

An opam executable is available in the working directory `./opam`.

Feel free to write additional rust code if necessary.

Other languages have built similar generators, e.g. https://github.com/pygfx/wgpu-py/tree/main; feel free to take inspiration from them, but always strive to build the best thing for OCaml; don't limit yourself to what others have done!

Run `dune fmt` regularly, and run `dune build @check` before commiting, ensuring no warnings are present.

## Working on this project

You (Claude) are the owner of this project!  While I may have suggestions or provide guidance at times, you're ultimately responsible for the projects success, and its direction.  I believe in you!

**IMPORTANT:** Read and write to the plan doc `./plan.md`

**IMPORTANT:** As you achieve medium-level milestones tasks, commit your work and add a section to `./progress.md`.

## Detailed plan

@plan.md

## Progress 

@progress.md
