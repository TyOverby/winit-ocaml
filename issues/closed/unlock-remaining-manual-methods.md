# Unlock Remaining Manual Methods After Codegen Improvements

subproject: `wgpu` code generator

## Problem

After the `create_render_pipeline` codegen work, several other methods that were previously marked as `Manual` should now be auto-generatable. The codegen now supports:
- Optional pointer-to-struct members
- Inline structs with array members
- Arrays of structs with nested inline structs
- Deep recursive nesting

## Methods to Unlock

These methods should be changed from `Manual` to `Auto` in `wgpu/codegen/config.ml`:

1. **`device.create_compute_pipeline`** - `compute_pipeline_descriptor`
   - Simple inline struct (`programmable_stage_descriptor`) with array of flat structs

2. **`device.create_render_bundle_encoder`** - `render_bundle_encoder_descriptor`
   - Only primitives, enums, and array of enums

3. **`device.create_query_set`** - `query_set_descriptor`
   - Trivial - just string, enum, and uint32

4. **`command_encoder.begin_render_pass`** - `render_pass_descriptor`
   - Optional pointer-to-struct members (same pattern as create_render_pipeline)
   - Array of structs with inline nested struct (`color`)

5. **`command_encoder.begin_compute_pass`** - `compute_pass_descriptor`
   - Simple optional pointer-to-struct with primitives and objects

6. **`surface.configure`** - `surface_configuration`
   - Flat descriptor with primitives, enums, bitflags, and enum array

## Task

1. Remove each method from the `Manual` list in `config.ml`
2. Run the codegen to regenerate `wgpu.ml` and `wgpu.mli`
3. Fix any test files that use these methods to match the new API signatures
4. Verify build passes with no warnings
5. Verify tests pass

## Task Completion

This task is complete when all 6 methods are auto-generated and all tests pass.

## Currently

After exploring the codebase, here is the current status:

1. **`device.create_compute_pipeline`**: NOT in the Manual list in config.ml - already auto-generated
2. **`device.create_render_bundle_encoder`**: NOT in the Manual list - already auto-generated
3. **`device.create_query_set`**: NOT in the Manual list - already auto-generated
4. **`surface.configure`**: NOT in the Manual list - already auto-generated
5. **`command_encoder.begin_render_pass`**: IS in the Manual list (line 34-35 in config.ml)
6. **`command_encoder.begin_compute_pass`**: IS in the Manual list (line 32-33 in config.ml)

The template file `wgpu/codegen/templates/high/adapter_module_prefix.ml` contains manual implementations of `begin_render_pass` and `begin_compute_pass` with different, simplified signatures:
- Manual `begin_render_pass` takes `~color_view`, `~clear_color` (tuple), etc. - a convenience API
- Manual `begin_compute_pass` only takes `?label` and `unit -> unit`

The codegen produces more complete versions with full parameter support.

There are also convenience functions at the module level in `instance_module.ml` that call the Command_encoder versions.

## Notes

- Only 2 methods need to be removed from the Manual list: `begin_render_pass` and `begin_compute_pass`
- The other 4 methods mentioned in the issue are already auto-generated
- The manual implementations in templates use a different convenience API that will need to be preserved for backwards compatibility
- The test file `test_regression.ml` already has expect tests showing what the codegen would produce for these methods
- The generated wgpu.ml already contains implementations for `create_compute_pipeline`, `create_query_set`, `create_render_bundle_encoder`, and `configure` (auto-generated)
- Looking at generated wgpu.ml lines 727-753 and 2269-2302, the manual begin_render_pass and configure are being used

## Addressing

Plan:
1. Remove `begin_render_pass` and `begin_compute_pass` from the Manual list in config.ml
2. Keep the convenience implementations in the templates but rename them (e.g., `begin_render_pass_simple`)
3. Regenerate the code by running `dune build`
4. Update any test files that use the old API signatures
5. Ensure the build passes with no warnings
6. Ensure tests pass

Validation criteria:
- `dune build` succeeds with no warnings
- `./test.sh` passes
- The 2 methods are now auto-generated in wgpu.ml with full parameter support
- The convenience functions are still available for simple use cases

## Completed

All tasks completed successfully:

1. **Removed from Manual list**: Removed `begin_render_pass` and `begin_compute_pass` from config.ml
2. **Renamed convenience functions**: Renamed to `begin_render_pass_simple` and `begin_compute_pass_simple` in:
   - `wgpu/codegen/templates/high/adapter_module_prefix.ml`
   - `wgpu/codegen/templates/high/adapter_module_prefix.mli`
   - `wgpu/codegen/templates/high/instance_module.ml`
   - `wgpu/codegen/templates/high/instance_module.mli`
3. **Updated test files**: Updated 38 test files to use the `_simple` variants:
   - 36 files using `Wgpu.begin_render_pass` -> `Wgpu.begin_render_pass_simple`
   - 2 files using `Wgpu.Command_encoder.begin_render_pass` -> `Wgpu.Command_encoder.begin_render_pass_simple`
   - 2 files using `Wgpu.Command_encoder.begin_compute_pass` -> `Wgpu.Command_encoder.begin_compute_pass_simple`
4. **Build passes**: `dune build` succeeds
5. **Tests pass**: `./test.sh` passes

The auto-generated methods now provide full API coverage:
- `Command_encoder.begin_compute_pass` with `?timestamp_writes` parameter
- `Command_encoder.begin_render_pass` with `?color_attachments`, `?depth_stencil_attachment`, `?occlusion_query_set`, `?timestamp_writes` parameters

The convenience functions (`_simple` variants) are still available for simple use cases.
