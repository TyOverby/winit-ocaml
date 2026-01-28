# Simplify render_uniform_buffer test

## Summary

The `test/integration/render_uniform_buffer/render_uniform_buffer.ml` test was written
before bigarray polymorphism was added to the wgpu bindings. It currently uses a manual
`set_float32` helper function to pack IEEE 754 floats into `int8_unsigned` bigarrays.

Now that `Queue.write_buffer` accepts any bigarray type and `get_mapped_range`/
`get_const_mapped_range` take a `~kind` parameter, the test can be simplified to use
`float32` bigarrays directly.

## Plan

1. Replace the `int8_unsigned` bigarray creation for `uniform_data` with a `float32` bigarray
2. Remove the `set_float32` helper function entirely
3. Set the RGBA color values directly using `Bigarray.Array1.set` with float values
4. Update the uniform buffer size constant to reflect the number of floats (4) rather than bytes (16)
5. Verify the test still passes

## Validation Criteria

- The test compiles without errors
- The test passes (produces the same magenta output image)
- The `set_float32` helper function is completely removed
- The uniform data is created as a `Bigarray.float32` array
- The code is simpler and more readable
