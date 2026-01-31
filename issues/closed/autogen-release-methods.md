# Auto-generate release methods for all object types

## Problem

Currently, `release` methods are hardcoded in template files for each object type (Queue, Device, Adapter, etc.). The `config.ml` marks these as `Manual { reason = "Custom release logic" }`, but there's actually no custom logic - they all follow the same pattern:

```ocaml
let release t = Wgpu_low.<object_name>_release t.handle
```

The reason these couldn't be auto-generated before is that `release` methods are not defined in `webgpu.yml` - they're implicit memory management functions that exist in the C header but not in the machine-readable spec.

## Solution

Modify the high-level code generator (`gen_high.ml`) to automatically generate a `release` method for every object type, since:

1. Every object type has a corresponding `Wgpu_low.*_release` function (verified: 22 objects, 22 release functions)
2. They all follow the identical pattern: `let release t = Wgpu_low.<object>_release t.handle`

## Implementation Steps

1. In `gen_high.ml`, when generating methods for an object module, automatically add a `release` method that calls the corresponding low-level release function.

2. Remove the `release` entries from `config.ml` since they'll be auto-generated:
   - `("queue", "release")`
   - `("device", "release")`
   - `("adapter", "release")`

3. Remove the hardcoded `let release t = ...` lines from template files:
   - `codegen/templates/high/adapter_module_prefix.ml` (Queue, Device, Command_encoder modules)
   - `codegen/templates/high/adapter_module_suffix.ml` (Adapter, Surface modules)
   - `codegen/templates/high/instance_module.ml` (Instance module)

4. Also generate a `release` function in the `.mli` file: `val release : t -> unit`

5. Run `dune build` to regenerate and verify the output is correct.

6. Run `dune build @check` to ensure no warnings.

## Notes

- The release method should be generated for ALL object types, not just the ones currently in templates
- This will add `release` methods to object types that previously didn't have them exposed in the high-level API (like Buffer, Texture, etc.)

---

## Implementation Plan (by Claude)

### Analysis

After reviewing the codebase, I found that `gen_high.ml` already auto-generates `release` methods
for "regular" objects via the `gen_object` function (lines 1144-1173). The issue is that the
"special" objects (Queue, Device, Adapter, Surface, Instance, Command_encoder) have manual
`release` implementations in template files, plus entries in `config.ml` marking them as manual.

### Steps

1. **Remove manual release entries from `config.ml`**:
   - Remove `("queue", "release"), Manual { reason = "Custom release logic" }`
   - Remove `("device", "release"), Manual { reason = "Custom release logic" }`
   - Remove `("adapter", "release"), Manual { reason = "Custom release logic" }`

2. **Remove hardcoded release methods from templates**:
   - `codegen/templates/high/adapter_module_prefix.ml`: Remove `let release t = ...` from
     Command_encoder, Queue, and Device modules
   - `codegen/templates/high/adapter_module_prefix.mli`: Remove `val release : t -> unit` from
     Command_encoder, Queue, and Device modules
   - `codegen/templates/high/adapter_module_suffix.ml`: Remove `let release t = ...` from
     Adapter and Surface modules
   - `codegen/templates/high/adapter_module_suffix.mli`: Remove `val release : t -> unit` from
     Adapter and Surface modules
   - `codegen/templates/high/instance_module.ml`: Remove `let release t = ...` from Instance
   - `codegen/templates/high/instance_module.mli`: Remove `val release : t -> unit` from Instance

3. **Verify the auto-generation works**: Run `dune build` and inspect the generated
   `high/wgpu.ml` and `high/wgpu.mli` to verify all special objects now have their release
   methods auto-generated through the injection mechanism.

### Validation Criteria

1. `dune build` succeeds
2. `dune build @check` has no warnings
3. `dune exec test/test_compute.exe` passes
4. The generated `high/wgpu.ml` still contains `let release t = Wgpu_low.*_release t.handle`
   for all object modules (Queue, Device, Adapter, Surface, Instance, Command_encoder)
5. The generated `high/wgpu.mli` still contains `val release : t -> unit` for all object modules
