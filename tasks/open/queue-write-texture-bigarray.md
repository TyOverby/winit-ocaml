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
