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

## Implementation Plan

### Analysis

1. **`Queue.write_buffer`**: The low-level binding `queue_write_buffer_bigarray` is already polymorphic
   `(_, _, Bigarray.c_layout)`. The high-level API just needs its type signature updated to remove the
   `int8_unsigned_elt` restriction.

2. **`get_mapped_range` and `get_const_mapped_range`**: These functions return bigarrays that wrap
   mapped GPU memory. The C stubs currently hardcode `CAML_BA_UINT8`. To make them polymorphic, we need
   the caller to provide a `kind` parameter (e.g., `Bigarray.float32`, `Bigarray.int32`) so the C code
   knows what element type to use when creating the bigarray.

### Changes Required

1. **high/wgpu.mli**:
   - Change `Queue.write_buffer` to accept `(_, _, Bigarray.c_layout) Bigarray.Array1.t`
   - Change `get_mapped_range` and `get_const_mapped_range` to take a `kind:('a, 'b) Bigarray.kind`
     parameter and return `('a, 'b, Bigarray.c_layout) Bigarray.Array1.t`

2. **high/wgpu.ml**: Update implementations to match new signatures

3. **low/wgpu_low.ml and low/wgpu_low.mli**:
   - Update `buffer_get_mapped_range_bigarray` and `buffer_get_const_mapped_range_bigarray` to take
     a kind parameter and return polymorphic bigarrays

4. **low/wgpu_low_stubs.c**:
   - Modify C stubs to accept and use the kind parameter when creating bigarrays

5. **test/integration/**: Create a test demonstrating float32 and int32 bigarrays work correctly

### Validation Criteria

1. Project builds without errors or warnings (`dune build @check`)
2. All existing tests pass (`dune runtest`)
3. New test demonstrates:
   - Writing float32 data to a buffer using `Queue.write_buffer`
   - Reading back float32 data using `get_mapped_range` with `Bigarray.float32` kind
   - Data round-trips correctly (values match)
