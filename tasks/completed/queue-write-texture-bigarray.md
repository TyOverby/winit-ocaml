# Queue.write_texture should accept bigarrays like write_buffer does

## Problem

`Queue.write_texture` currently requires a raw `nativeint` pointer for the data
parameter, which is not easily obtainable from OCaml bigarrays. This forces
users to use a workaround with staging buffers:

```ocaml
(* Current workaround - create staging buffer and copy *)
let staging_buffer = Wgpu.Device.create_buffer device ~usage:[Copy_src] ... in
Wgpu.Queue.write_buffer queue ~buffer:staging_buffer ~data:bigarray_data;
Wgpu.Command_encoder.copy_buffer_to_texture encoder ~source:staging_buffer ...;
```

This is verbose and requires managing an extra buffer.

## Expected Behavior

`Queue.write_texture` should accept bigarrays directly, similar to how
`Queue.write_buffer` works after the polymorphism fix:

```ocaml
(* Desired API *)
Wgpu.Queue.write_texture
  queue
  ~destination_texture:texture
  ~data:rgba_bigarray  (* accepts any bigarray type *)
  ...
```

## Current Signature

Looking at the low-level bindings, `write_texture` likely takes a raw pointer.
The high-level wrapper should handle the bigarray-to-pointer conversion
internally, similar to how `write_buffer` was updated.

## Affected Code

- `test/fundamentals/textures/` - all three examples use the staging buffer
  workaround.  After implementing the new API, update `test/fundamentals/textures`
  to take advantage of it.

## Implementation Notes

The fix should mirror what was done for `Queue.write_buffer` with polymorphic
bigarrays - extract the data pointer from the bigarray and pass it to the
underlying C function.

## Plan

1. Add a new C stub `caml_wgpu_queue_write_texture_bigarray` in
   `codegen/templates/low/sync_helpers.c` that:
   - Accepts a bigarray instead of a raw pointer for the data
   - Extracts the data pointer and size from the bigarray using
     `Caml_ba_data_val` and `caml_ba_byte_size`
   - Calls `wgpuQueueWriteTexture` with the extracted data

2. Add the OCaml external declaration in
   `codegen/templates/low/convenience_functions.ml` and
   `codegen/templates/low/convenience_functions.mli`

3. Update the high-level `Queue.write_texture` in `high/wgpu.ml` and
   `high/wgpu.mli` to accept `(_, _, Bigarray.c_layout) Bigarray.Array1.t`
   instead of `nativeint` and `int64` for data/data_size

4. Update the texture tests in `test/fundamentals/textures/` to use the new
   simpler API directly instead of the staging buffer workaround

## Validation Criteria

- `dune build` succeeds
- `dune build @check` has no warnings
- `dune runtest` passes
- The three texture tests in `test/fundamentals/textures/` use
  `Queue.write_texture` directly with bigarray data instead of the staging
  buffer workaround
- The generated PNG files are unchanged (visual regression check)
