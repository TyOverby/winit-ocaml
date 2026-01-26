# wgpu-native-ocaml Implementation Plan

## Overview

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
