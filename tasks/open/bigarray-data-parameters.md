# Support Bigarray for Data Parameters in Codegen

## Problem

Several methods take raw data pointers (`void*` in C, `nativeint` in OCaml) plus size parameters. The current codegen produces these as separate `nativeint` + `int64` parameters, but a more ergonomic API would use bigarrays.

**Example: queue.write_buffer**

Current codegen output:
```ocaml
val write_buffer : t -> buffer:Buffer.t -> buffer_offset:int64 -> data:nativeint -> size:int64 -> unit
```

Preferred ergonomic API (currently in template):
```ocaml
val write_buffer : t -> buffer:Buffer.t -> offset:int64 ->
  data:(int, Bigarray.int8_unsigned_elt, Bigarray.c_layout) Bigarray.Array1.t -> unit
```

The bigarray version:
1. Combines data pointer and size into a single parameter
2. Is type-safe (can't pass arbitrary pointers)
3. Is more idiomatic OCaml

## Affected Methods

Methods with `void*` data + size parameters that could benefit from bigarray:

1. **queue.write_buffer** - Currently manual, uses `queue_write_buffer_bigarray` low-level function
2. **queue.write_texture** - Has `data` + `data_size` parameters

## Solution Options

### Option A: Add Bigarray Variant Generation

Teach the codegen to recognize `void*` + size parameter patterns and generate bigarray variants:

1. In `gen_high.ml`, detect when a method has:
   - A `void*` or `void const*` parameter
   - Followed by a `size_t` size parameter
2. Generate a bigarray signature instead:
   - Combine into single `data:(_, _, Bigarray.c_layout) Bigarray.Array1.t` parameter
   - Use bigarray data pointer and length internally

This requires corresponding low-level functions that accept bigarrays (like `queue_write_buffer_bigarray`).

### Option B: Keep Manual for Ergonomic Variants

Keep the raw codegen output for the standard API, and maintain manual ergonomic wrappers in templates for commonly-used methods.

### Option C: Both APIs

Generate both the raw nativeint version (for advanced use) and a bigarray version (for common use):

```ocaml
val write_buffer_raw : t -> buffer:Buffer.t -> buffer_offset:int64 -> data:nativeint -> size:int64 -> unit
val write_buffer : t -> buffer:Buffer.t -> offset:int64 -> data:bigarray -> unit
```

## Recommendation

Option B (keep manual) is simplest for now. The ergonomic bigarray wrappers are already working well in templates. This task should be lower priority than fixing actual codegen bugs.

However, documenting this pattern is valuable for future reference.

## Files to Modify (if implementing Option A)

- `codegen/gen_high.ml` - Add bigarray detection and generation
- `codegen/templates/low/convenience_functions.ml` - Ensure bigarray low-level functions exist

## Current State

- `queue.write_buffer` - Template provides bigarray version, works well
- `queue.write_texture` - Codegen provides raw version, could add bigarray wrapper

## Validation Criteria

If implementing:
1. `dune build` succeeds
2. `dune build @check` reports no warnings
3. Bigarray versions are generated automatically
4. Existing tests continue to work
