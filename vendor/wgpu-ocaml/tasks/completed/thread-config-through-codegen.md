# Thread Config Through Codegen Functions

## Problem

The code generation functions in `gen_high.ml` and `gen_low.ml` check global state in `Config` to determine whether to skip manual methods. For example, in `gen_high.ml:804`:

```ocaml
let gen_method ... =
  (* Skip methods that are manually implemented *)
  if Config.is_manual ~object_name:obj.name ~method_name:method_.name
  then None
  else ...
```

This creates a problem for testing: when we want to test what codegen *would produce* for manually-implemented methods (see `tasks/open/hardcoded-function-regression-tests.md`), the codegen just returns `None` because the global config says "this is manual".

Additionally, `gen_low.ml` has its own duplicate `method_is_manual` function (lines 613-618) that doesn't use `Config` at all:

```ocaml
let method_is_manual (obj_name : string) (method_name : string) : bool =
  match obj_name, method_name with
  | "adapter", "get_info" -> true
  | _ -> false
;;
```

This is inconsistent and will cause issues.

## Solution

Refactor to pass a `Config.t` value through all codegen functions instead of using global state. This allows:
1. Production code to use a default config that respects manual/skipped flags
2. Test code to use a config that ignores these flags to see what would be generated

## Implementation

### Phase 1: Create Config.t type

In `codegen/config.ml`, add a record type:

```ocaml
type t = {
  method_config : (Method_key.t * method_handling) list;
  ignore_manual_for_generation : bool;  (* For testing *)
}

let default : t = {
  method_config = method_config;  (* existing list *)
  ignore_manual_for_generation = false;
}

let for_testing : t = {
  method_config = method_config;
  ignore_manual_for_generation = true;
}

(* Update is_manual to take config *)
let is_manual (config : t) ~object_name ~method_name : bool =
  if config.ignore_manual_for_generation then false
  else Set.mem (manual_implementations_of config) (object_name, method_name)
```

### Phase 2: Thread config through Gen_high

Update all generation functions to accept a `config` parameter:

```ocaml
(* Before *)
val gen_ml_method : Ir.struct_ list -> Ir.object_ -> Ir.method_ -> string option

(* After *)
val gen_ml_method : Config.t -> Ir.struct_ list -> Ir.object_ -> Ir.method_ -> string option
```

Functions that need updating in `gen_high.ml`:
- `gen_method` (line 796)
- `gen_ml_method` (line 874)
- `gen_mli_method` (line 1004)
- `gen_special_object_auto_methods` (line 1249)
- `gen_special_object_auto_methods_mli` (line 1274)
- `gen_object` (line 1072)
- `gen_ml_object` (line 1125)
- `gen_mli_object` (line 1129)
- `gen_ml` (line 1299)
- `gen_mli` (line 1349)
- `validate_method_coverage` (line 1399)
- `check_method_coverage` (line 1445)

### Phase 3: Thread config through Gen_low

Remove the local `method_is_manual` function and use `Config.is_manual`:

Functions that need updating in `gen_low.ml`:
- Remove `method_is_manual` (lines 613-618)
- `gen_c_method_stub` (line 662)
- `gen_ml_method` (line 826)
- `gen_mli_method` (line 872)
- `gen_c_object_stubs` (line 797)
- `gen_ml_object_methods` (line 857)
- `gen_mli_object_methods` (line 894)
- `gen_c_stubs` (line 924)
- `gen_ml` (line 953)
- `gen_mli` (line 970)

### Phase 4: Update gen_bindings.ml

The main entry point in `gen_bindings.ml` should pass `Config.default` to all generation calls.

### Phase 5: Update For_testing modules

Update the `For_testing` modules to either:
- Accept an optional `?config` parameter defaulting to `Config.for_testing`
- Or provide separate test-specific functions

Recommended approach:

```ocaml
module For_testing = struct
  (* Use config that ignores manual flags by default in tests *)
  let default_test_config = Config.for_testing

  let gen_ml_method ?(config = default_test_config) structs obj method_ =
    gen_ml_method config structs obj method_

  (* ... etc ... *)
end
```

### Phase 6: Update test_regression.ml

The existing `print_method_outputs` helper should work without changes since the `For_testing` functions will default to using `Config.for_testing`.

## Files to Modify

1. `codegen/config.ml` - Add `t` type and `for_testing` value
2. `codegen/config.mli` - Expose new types and functions
3. `codegen/gen_high.ml` - Thread config through all functions
4. `codegen/gen_high.mli` - Update signatures
5. `codegen/gen_low.ml` - Thread config, remove duplicate `method_is_manual`
6. `codegen/gen_low.mli` - Update signatures
7. `codegen/gen_bindings.ml` - Pass `Config.default` to generation calls

## Testing

1. `dune build` succeeds
2. `dune build @check` reports no warnings
3. `dune runtest` passes (existing tests should work with default config)
4. The regression tests for hardcoded functions (from the companion task) can now see generated output

## Validation Criteria

1. All existing functionality works unchanged (config defaults preserve current behavior)
2. `For_testing` functions default to ignoring manual flags
3. No duplicate `method_is_manual` logic exists
4. `Config.is_manual` is the single source of truth for manual method detection
5. All codegen functions can be tested with the `for_testing` config

## Dependency

This task should be completed **before** `hardcoded-function-regression-tests.md`, as that task depends on being able to generate code for manual methods.

## Implementation Plan (by Claude)

I will follow the phases outlined in the task description:

1. **Phase 1**: Add `Config.t` type with `default` and `for_testing` values
2. **Phase 2**: Thread config through all `Gen_high` functions
3. **Phase 3**: Thread config through all `Gen_low` functions, remove duplicate `method_is_manual`
4. **Phase 4**: Update `gen_bindings.ml` to pass `Config.default`
5. **Phase 5**: Update `For_testing` modules to use `Config.for_testing` by default
6. **Phase 6**: Verify tests still pass

The key insight is that `ignore_manual_for_generation` allows test code to see what would be generated for manually-implemented methods, while production code continues to respect the manual/skipped configuration.

### Validation
- `dune build` succeeds
- `dune build @check` reports no warnings
- `dune exec test/test_compute.exe` passes
- All manual/skipped methods continue to work as before
