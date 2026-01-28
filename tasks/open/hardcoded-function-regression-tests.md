# Add Regression Tests for Hardcoded Functions

## Problem

The code generator has many hardcoded function implementations that bypass the normal generate-from-yaml codegen path. These are tracked in `codegen/config.ml` in the `method_config` list and marked as `Manual` or `Skipped`.

Currently, there's no visibility into what the codegen *would have* produced for these methods. Adding regression tests for these cases helps us:
1. Understand why certain methods needed manual implementation
2. Detect when codegen improvements make a previously-manual method auto-generatable
3. Document the expected failures or limitations of the current codegen

## Task

1. **Find all hardcoded functions**: Review `codegen/config.ml` to get the complete list of methods marked as `Manual` in `method_config`.

2. **Add regression tests**: For each manual method, add an expect test in `codegen/test/test_regression.ml` that:
   - Looks up the object and method from the real `webgpu.yml`
   - Attempts to generate code using the normal codegen path (e.g., `Gen_high.For_testing.gen_ml_method`, `Gen_high.For_testing.gen_mli_method`, etc.)
   - Prints the generated code (or `(none)` if generation returns `None`)

3. **Handle exceptions**: If calling the generation function raises an exception (rather than returning `None`), wrap the test body in `Expect_test_helpers_core.require_does_raise` to capture the exception as part of the expected output.

## Implementation Details

### Location of manual methods

The list is in `codegen/config.ml`:

```ocaml
let method_config : (Method_key.t * method_handling) list =
  [ ("instance", "release"), Manual { reason = "..." }
  ; ("instance", "create_surface"), Manual { reason = "..." }
  ; (* ... many more ... *)
  ]
```

### Existing test pattern

See the existing regression tests in `codegen/test/test_regression.ml` for the pattern.  You can see tests of the regression testing infrastructure in `codegen/test/test_regression_tests.ml`

### Test structure for methods that might raise

For methods where codegen might raise an exception:

```ocaml
let%expect_test "manual: instance.create_surface" =
  let obj = lookup_object "instance" in
  let method_ = lookup_method obj "create_surface" in
  Expect_test_helpers_core.require_does_raise [%here] (fun () ->
    print_method_outputs obj method_);
  [%expect {|
    (* expected exception output *)
  |}]
;;
```

For methods where codegen returns `None` or succeeds but we want to document what it produces:

```ocaml
let%expect_test "manual: device.get_queue" =
  let obj = lookup_object "device" in
  let method_ = lookup_method obj "get_queue" in
  print_method_outputs obj method_;
  [%expect {|
    (* expected output *)
  |}]
;;
```

### Suggested test naming

Use a consistent naming pattern like:
- `"manual: <object>.<method>"` for tests of manually-implemented methods

## Manual Methods to Test

From `config.ml`, the manual methods are:

**Instance:**
- `instance.release`
- `instance.create_surface`
- `instance.process_events`
- `instance.request_adapter`
- `instance.get_WGSL_language_features`
- `instance.wait_any`

**Adapter:**
- `adapter.release`
- `adapter.has_feature`
- `adapter.get_info`
- `adapter.request_device`
- `adapter.get_features`

**Device:**
- `device.release`
- `device.poll`
- `device.get_features`
- `device.create_shader_module`
- `device.create_texture`
- `device.create_compute_pipeline`
- `device.create_render_pipeline`
- `device.create_bind_group_layout_for_storage_buffer`
- `device.pop_error_scope`
- `device.get_queue`
- `device.get_lost_future`
- `device.get_adapter_info`

**Queue:**
- `queue.release`
- `queue.set_label`
- `queue.submit`
- `queue.write_buffer`
- `queue.write_texture`
- `queue.on_submitted_work_done`

**Command Encoder:**
- `command_encoder.begin_compute_pass`
- `command_encoder.begin_render_pass`

**Render Pass Encoder:**
- `render_pass_encoder.set_vertex_buffer`
- `render_pass_encoder.set_index_buffer`

**Render Bundle Encoder:**
- `render_bundle_encoder.set_vertex_buffer`
- `render_bundle_encoder.set_index_buffer`

**Buffer:**
- `buffer.map_async`
- `buffer.get_mapped_range`
- `buffer.get_const_mapped_range`

**Shader Module:**
- `shader_module.get_compilation_info`

**Surface:**
- `surface.configure`
- `surface.get_capabilities`

## Dependency

This task depends on `thread-config-through-codegen.md` being completed first. Without that change, the codegen functions check `Config.is_manual` and return `None` for manual methods, which defeats the purpose of these regression tests.

## Files to Modify

- `codegen/test/test_regression.ml` - Add expect tests for each manual method

## Testing

1. Run `dune build` to ensure compilation succeeds
2. Run `dune runtest` to generate the expect test output
3. Run `dune promote` to accept the generated output as the expected baseline
4. Run `dune fmt > /dev/null || true` to format the code
5. Run `dune build @check` to ensure no warnings

## Validation Criteria

1. `dune build` succeeds
2. `dune build @check` reports no warnings
3. Each manual method from `config.ml` has a corresponding expect test
4. Tests that raise exceptions use `require_does_raise`
5. Tests that succeed document what the current codegen produces (even if it returns `(none)`)
