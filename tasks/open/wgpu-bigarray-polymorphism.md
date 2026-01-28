# Wgpu bigarray functions should be polymorphic

## Problem

Several functions in `high/wgpu.mli` have bigarray types specialized to
`int8_unsigned_elt`:

```ocaml
(* Queue.write_buffer *)
val write_buffer
  :  t
  -> buffer:Buffer.t
  -> offset:int64
  -> data:(int, Bigarray.int8_unsigned_elt, Bigarray.c_layout) Bigarray.Array1.t
  -> unit

(* get_mapped_range *)
val get_mapped_range
  :  Buffer.t
  -> offset:int64
  -> size:int64
  -> (int, Bigarray.int8_unsigned_elt, Bigarray.c_layout) Bigarray.Array1.t

(* get_const_mapped_range *)
val get_const_mapped_range
  :  Buffer.t
  -> offset:int64
  -> size:int64
  -> (int, Bigarray.int8_unsigned_elt, Bigarray.c_layout) Bigarray.Array1.t
```

This forces users to work with raw bytes even when they have structured data
like float32 arrays (for vertex data, uniforms) or int32 arrays (for indices).

## Suggested Fix

Make the element type polymorphic: `(_, _, Bigarray.c_layout) Bigarray.Array1.t`

The underlying C API just wants a pointer and size, so there's no reason to
restrict the OCaml type.

## Benefits

- Users can directly pass `float32` bigarrays for vertex/uniform data
- Users can pass `int32` bigarrays for index buffers
- No need to manually pack/unpack bytes

## Files Affected

- `high/wgpu.mli`
- `high/wgpu.ml`

## Demonstrating a fix

Make a new test executable under `test/integration/` demonstrating that the
issue has been fixed.
