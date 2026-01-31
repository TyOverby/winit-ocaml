# wgpu-native codegen

This document outlines the implementation strategy for creating idiomatic OCaml
bindings to wgpu-native. The approach uses code generation from the
machine-readable `webgpu.yml` specification to produce both low-level
C bindings and high-level OCaml APIs.

## Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                        User OCaml Code                              │
└─────────────────────────────────────────────────────────────────────┘
                                  │
                                  ▼
┌─────────────────────────────────────────────────────────────────────┐
│                    High-Level OCaml API                             │
│  (wgpu.mli / wgpu.ml - generated from webgpu.yml)                   │
│  - Type-safe modules: Device, Buffer, Texture, etc.                 │
│  - OCaml variants for enums                                         │
│  - Optional parameters, labeled arguments                           │
│  - Automatic memory management                                      │
└─────────────────────────────────────────────────────────────────────┘
                                  │
                                  ▼
┌─────────────────────────────────────────────────────────────────────┐
│                    Low-Level External Bindings                      │
│  (wgpu_low.{ml,mli}, wgpu_low_stubs.c - generated from webgpu.yml)  │
│  - `external` based C function bindings                             │
│  - Hand-written C stubs that call wgpu-native                       │
│  - Statically links against libwgpu_native.a                        │
│  - Includes webgpu.h                                                │
│  - Raw struct accessors                                             │
│  - Enum constants as OCaml ints                                     │
└─────────────────────────────────────────────────────────────────────┘
                                  │
                                  ▼
┌─────────────────────────────────────────────────────────────────────┐
│               wgpu-native (Rust compiled to C library)              │
└─────────────────────────────────────────────────────────────────────┘
```

## Key Design Decisions

1. **Sync over Async**: Using synchronous wrappers with internal callbacks for now
2. **Raw External**: Using `external` declarations with C stubs (not ctypes)
3. **Builder Pattern**: Structs created via builder functions with optional args
4. **Zero-Copy**: Bigarrays for buffer data to avoid copying
5. **PPM Output**: Simple PPM format for headless testing, convert to PNG via ImageMagick

## High level API goals

- Be safe
  - Type safety is paramount (not able to confuse values that should be
    different kinds of objects)
  - Memory safe (finalizers or explicit destructors shouldn't be able to free
    parent resources before children)
- Be ergonomic, but accurate
  - Break the API up into modules when it makes sense
  - Follow Jane Street API guidelines
    - Types are always named `t` and live inside the modules that contain their
      functionality 
    - Within a module, parameters should be either optional or named, with `t`
      values being the only positional (unnamed) arg 
  - use optional parameters when applicable
  - The generated APIs should still be 1:1 replicas of the functions found in the C library
- Be readable
  - Generate a `.mli` file for the high level bindings, not just a `.ml`
    - Include comments in the `.mli` code that are associated with the
    functions and types that are described

## Developing

The code generator should be written in Jane Street style OCaml, using `Core`.

A fast developer iteration loop is critical!  Make sure to always write code in
such a way that it's easy to validate your work!

Build test executables (see `../test/integration/`) and run them regularly.
These tests may need to be headless, but tests can write to a `.png` file that
you can read.

`dune build` from the project root will re-generate all of the generated code.
