# Task #4: Add Chained Struct Support (nextInChain Pattern)

## Goal

Support the webgpu "chained struct" pattern where base structs can be extended with additional functionality via a linked list of extension structs.

## Background

WebGPU uses a struct chaining pattern for extensibility:

```c
// Base struct has a nextInChain pointer
typedef struct WGPUShaderModuleDescriptor {
    WGPUChainedStruct const * nextInChain;
    WGPUStringView label;
} WGPUShaderModuleDescriptor;

// Extension struct has a chain header
typedef struct WGPUShaderSourceWGSL {
    WGPUChainedStruct chain;  // Contains sType field
    WGPUStringView code;
} WGPUShaderSourceWGSL;

// Usage: chain extension to base
WGPUShaderSourceWGSL wgsl = {
    .chain = { .sType = WGPUSType_ShaderSourceWGSL },
    .code = { ... }
};
WGPUShaderModuleDescriptor desc = {
    .nextInChain = (WGPUChainedStruct*)&wgsl,
    .label = { ... }
};
```

## Current State

### What's Done
- `nextInChain` is initialized to NULL in struct creation
- Hardcoded support for WGSL shader modules via `device_create_shader_module_wgsl`
- `nextInChain` is skipped in high-level struct parameter collection

### What's Missing
- No IR representation of extension relationships
- No auto-generation of extension struct support
- No way to chain multiple extensions

## YAML Specification

Extension structs in webgpu.yml have:
```yaml
- name: shader_source_WGSL
  type: extension_in        # <-- marks as extension
  extends:                  # <-- what it extends
    - shader_module_descriptor
  members:
    - name: code
      type: string_with_default_empty
```

The `s_type` enum maps extension names to integer values:
```yaml
- name: s_type
  entries:
    - null
    - name: shader_source_SPIRV
    - name: shader_source_WGSL
    - name: render_pass_max_draw_count
    # etc.
```

## Implementation Plan

### Phase 1: Extend the IR

Add extension information to the struct type:

```ocaml
(* In codegen/ir.ml *)
type struct_type =
  | Base_in
  | Base_out
  | Base_in_out
  | Standalone
  | Extension_in of { extends : string list }  (* NEW *)
  | Extension_out of { extends : string list } (* NEW *)
```

**Files to modify:**
- `codegen/ir.ml` - add extension variants
- `codegen/parse_yml.ml` - parse `extends` field from YAML

### Phase 2: Generate SType Enum Values

The `s_type` enum needs to map extension struct names to integer values. This is already parsed as a regular enum, but we need to:

1. Ensure `S_type` module is generated
2. Provide a way to get the sType for a given extension struct name

```ocaml
(* Generated *)
module S_type = struct
  type t =
    | Shader_source_SPIRV
    | Shader_source_WGSL
    | Render_pass_max_draw_count
    (* etc. *)

  let to_int = function
    | Shader_source_SPIRV -> 1
    | Shader_source_WGSL -> 2
    (* etc. *)
end
```

**Files to modify:**
- `codegen/gen_high.ml` - ensure S_type is exported properly

### Phase 3: Generate Extension Struct Support

For each extension struct, generate:

1. A struct module with create/free/setters (already done for regular structs)
2. A way to set the sType in the chain header
3. A way to get a pointer suitable for nextInChain

```ocaml
(* In low-level bindings *)
module Shader_source_WGSL = struct
  type t = nativeint

  external create : unit -> t = "caml_wgpu_shader_source_WGSL_create"
  external free : t -> unit = "caml_wgpu_shader_source_WGSL_free"
  external set_code : t -> string -> unit = "..."

  (* NEW: set the sType in the chain header *)
  external set_chain_stype : t -> int -> unit = "..."

  (* NEW: get as chained struct pointer for nextInChain *)
  external as_chained : t -> nativeint = "..."
end
```

**Files to modify:**
- `codegen/gen_low.ml` - add chain header functions for extension structs

### Phase 4: High-Level Chaining API

Design decision: How should the high-level API handle chaining?

**Option A: Explicit chaining parameter**
```ocaml
let create_shader_module t ?(label = "") ~source () =
  match source with
  | `WGSL code -> (* use WGSL extension *)
  | `SPIRV data -> (* use SPIRV extension *)
```

**Option B: Builder pattern with extension methods**
```ocaml
let desc = Shader_module_descriptor.create ~label () in
let desc = Shader_module_descriptor.with_wgsl desc ~code in
let module_ = Device.create_shader_module device desc
```

**Option C: Separate convenience functions (current approach)**
```ocaml
let create_shader_module_wgsl t ~label ~code () = ...
let create_shader_module_spirv t ~label ~data () = ...
```

Recommendation: Option A or C for simplicity. Option B is more flexible but more complex.

**Files to modify:**
- `codegen/gen_high.ml` - add high-level extension support

### Phase 5: C Stub Generation for Chain Header

Generate C code to handle the chain header:

```c
// Set sType in chain header
CAMLprim value caml_wgpu_shader_source_WGSL_set_chain_stype(value handle, value stype) {
    CAMLparam2(handle, stype);
    WGPUShaderSourceWGSL *s = (WGPUShaderSourceWGSL*)Nativeint_val(handle);
    s->chain.sType = Int_val(stype);
    CAMLreturn(Val_unit);
}

// Get as chained struct pointer
CAMLprim value caml_wgpu_shader_source_WGSL_as_chained(value handle) {
    CAMLparam1(handle);
    WGPUShaderSourceWGSL *s = (WGPUShaderSourceWGSL*)Nativeint_val(handle);
    CAMLreturn(caml_copy_nativeint((intnat)&s->chain));
}
```

**Files to modify:**
- `codegen/gen_low.ml` - add C stub generation for extension structs

## Extension Structs in webgpu.yml

Current extension structs that need support:

| Extension | Extends | Purpose |
|-----------|---------|---------|
| `shader_source_SPIRV` | `shader_module_descriptor` | SPIR-V shader source |
| `shader_source_WGSL` | `shader_module_descriptor` | WGSL shader source |
| `render_pass_max_draw_count` | `render_pass_descriptor` | Limit draw calls |
| `surface_source_metal_layer` | `surface_descriptor` | macOS Metal surface |
| `surface_source_windows_HWND` | `surface_descriptor` | Windows surface |
| `surface_source_xlib_window` | `surface_descriptor` | X11 surface |
| `surface_source_wayland_surface` | `surface_descriptor` | Wayland surface |
| `surface_source_android_native_window` | `surface_descriptor` | Android surface |
| `surface_source_XCB_window` | `surface_descriptor` | XCB surface |

## Testing Strategy

1. Start with `shader_source_WGSL` since it's already working via hardcoded helper
2. Replace hardcoded `device_create_shader_module_wgsl` with auto-generated version
3. Verify existing shader tests still pass
4. Add tests for other extension structs as they're implemented

## Complexity Estimate

This is a medium-to-high complexity task:
- IR changes: straightforward
- C stub generation: moderate (need to handle chain header specially)
- High-level API design: needs careful thought about ergonomics
- Main challenge: deciding on the right abstraction level

## Open Questions

1. Should extension chaining be exposed in the high-level API, or only via convenience functions?
2. How to handle multiple extensions on the same base struct?
3. Should we generate all extension variants or only commonly used ones?

## Related Files

- `codegen/ir.ml` - IR definitions
- `codegen/parse_yml.ml` - YAML parser
- `codegen/gen_low.ml` - low-level generator (C stubs, OCaml externals)
- `codegen/gen_high.ml` - high-level generator
- `vendor/wgpu-native/ffi/webgpu-headers/webgpu.yml` - API specification
- `vendor/wgpu-native/ffi/webgpu-headers/webgpu.h` - C header for reference
