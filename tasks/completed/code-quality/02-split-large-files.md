# Split Large Files Into Focused Modules

## Problem

The two main generator files are very large:
- `gen_high.ml`: 2295 lines
- `gen_low.ml`: 1882 lines

Each file contains multiple distinct concerns mixed together:
- Type mapping (IR types to OCaml/C types)
- Name transformations (snake_case to PascalCase, etc.)
- Code generation for different constructs (enums, structs, objects, methods)
- Special case handling
- Entry point logic

## Proposed File Structure

```
codegen/
  lib/
    dune
    names.ml          # Name transformations (to_pascal_case, ocaml_module_name, etc.)
    types.ml          # Type mapping (IR -> OCaml type strings, IR -> C type strings)
    predicates.ml     # is_simple_struct, method_is_async, is_simple_arg_type, etc.

    low/
      dune
      enums.ml        # gen_c_enum_constants, gen_ml_enum, gen_mli_enum
      bitflags.ml     # gen_c_bitflag_constants, gen_ml_bitflag, gen_mli_bitflag
      structs.ml      # gen_c_struct_*, gen_ml_struct, gen_mli_struct
      objects.ml      # gen_c_object_stubs, gen_ml_object, gen_mli_object
      functions.ml    # gen_c_function_stubs

    high/
      dune
      enums.ml        # gen_ml_enum, gen_mli_enum (re-exports)
      bitflags.ml     # gen_ml_bitflag, gen_mli_bitflag
      objects.ml      # gen_ml_object, gen_mli_object, method generation
      entry_structs.ml # Entry struct module generation
      special_modules.ml # Instance, Adapter, Device, Queue
  dune
  gen_low.ml          # Entry point for low-level generation
  gen_high.ml         # Entry point for high-level generation
  gen_bindings.ml     # CLI entry point (already small)
```

More files, for containing utilities that are used from multiple files may also be necessary

## Specific Extractions

### From gen_low.ml

1. **Name utilities** (lines 6-48): `to_pascal_case`, `to_camel_case`, `c_type_name`, etc.
   These are also duplicated in gen_high.ml.
2. **Type mapping** (lines 56-78): `c_type_of_type_ref`
3. **Enum generation** (lines 80-170): `gen_c_enum_constants`, `gen_ml_enum`, `gen_mli_enum`
4. **Bitflag generation** (lines 172-252): Similar pattern
5. **Struct generation** (lines 254-757): This is a large block that could be its own module
6. **Object/method generation** (lines 759-1176): Another distinct concern

### From gen_high.ml

1. **Method accounting** (lines 14-102): `manual_implementations`, `intentionally_skipped`,
   `method_is_accounted_for` - this is configuration, not generation
2. **Type predicates** (lines 197-461): `is_simple_member_type`, `is_simple_struct`,
   `method_is_high_level`, etc.
3. **Parameter collection** (lines 609-691): `collect_struct_params`, `generate_struct_creates`
4. **Method generation** (lines 911-1163): Multiple functions for different method types

## Benefits

1. Each file has a single, clear responsibility
2. Easier to find relevant code
3. Easier to modify one aspect without touching others
4. Better testability (can test name transformations independently)
5. Reduced cognitive load when working on one area

## Estimated Impact

- High value: Dramatically improves navigability
- High effort: Requires careful refactoring and testing

## Status Update (2026-01-27)

**Completion: ~40% - Partially Complete**

### What Has Been Done ✅

1. **Extracted utility modules:**
   - `codegen/names.ml` (90 lines) - Name transformations (to_pascal_case, to_camel_case, etc.)
   - `codegen/type_mapping.ml` (117 lines) - Type mapping with context system
   - `codegen/config.ml` (174 lines) - Method configuration system

2. **File size reductions:**
   - `gen_high.ml`: 2295 → 1783 lines (512 lines removed, ~22% reduction)
   - `gen_low.ml`: 1882 → 1191 lines (691 lines removed, ~37% reduction)

3. **Tests created:**
   - `codegen/test/test_names.ml` - Tests for name transformations
   - `codegen/test/test_types.ml` - Tests for type mapping

### What Remains ❌

1. **Directory structure not created:** The proposed `lib/low/` and `lib/high/` subdirectories don't exist yet

2. **Extract from gen_low.ml:**
   - Predicates (method_is_async, array_elem_c_type, etc.)
   - Enums module (gen_c_enum_constants, gen_ml_enum, gen_mli_enum)
   - Bitflags module (gen_c_bitflag_constants, gen_ml_bitflag, gen_mli_bitflag)
   - Structs module (gen_c_struct_*, gen_ml_struct, gen_mli_struct)
   - Objects module (gen_c_object_stubs, gen_ml_object, gen_mli_object)
   - Functions module (gen_c_function_stubs)

3. **Extract from gen_high.ml:**
   - Predicates (is_flat_member_type, is_auto_generable_struct, etc.)
   - Type conversion utilities (high_level_arg_type, arg_to_low_level, etc.)
   - Parameter/struct utilities (build_param_list, gen_cleanup_code, etc.)
   - High-level generation modules (enums, bitflags, objects, methods)

4. **Remove duplicated code:**
   - `to_pascal_case` and `to_camel_case` are still duplicated in gen_low.ml (lines 12-28)
   - These should be removed and use the Names module instead

5. **Update imports and ensure everything builds**

## Implementation Plan (2026-01-27)

### Goal
Complete the extraction of duplicated code and major generator modules from gen_low.ml
to further improve code organization and eliminate duplication.

### Tasks

1. **Remove duplicated name transformation functions from gen_low.ml**
   - Remove `to_pascal_case` (lines 16-26) and `to_camel_case` (lines 28-33)
   - Update all usages to call `Names.to_pascal_case` and `Names.to_camel_case`
   - Note: The Names.to_pascal_case handles the simple case, but gen_low.ml has special
     handling for double underscores. Need to handle this appropriately.

2. **Extract helper predicates to a shared module**
   - `method_is_async` is defined in both gen_low.ml and gen_high.ml
   - Create `codegen/predicates.ml` for shared predicates

3. **Extract low-level generator modules (optional, if time permits)**
   - Enums module
   - Bitflags module
   - Structs module
   - Objects module

### Validation Criteria

1. `dune build` succeeds with no errors
2. `dune fmt > /dev/null || true` produces no new errors
3. `dune build @check` produces no warnings
4. `dune exec test/test_compute.exe` passes all tests
5. No duplicated `to_pascal_case` or `to_camel_case` functions remain in gen_low.ml
6. The generated output (wgpu_low.ml, wgpu_low.mli, wgpu_low_stubs.c, wgpu.ml, wgpu.mli)
   should be identical before and after the refactoring

## Completion Status (2026-01-27)

**Status: COMPLETE**

### What Was Done

1. **Removed duplicated name transformation functions from gen_low.ml:**
   - Updated `Names.to_pascal_case` to handle double underscores (matching gen_low.ml behavior)
   - Added `Names.to_pascal_case_simple` for cases not needing double underscore handling
   - Replaced local `to_pascal_case` and `to_camel_case` in gen_low.ml with aliases to Names module

2. **Extracted helper predicates to shared module:**
   - Created `codegen/predicates.ml` with `method_is_async` predicate
   - Updated both gen_low.ml and gen_high.ml to use `Predicates.method_is_async`

3. **Extracted additional shared utilities to Names module:**
   - `normalize_enum_entry_name` - already existed, now used consistently
   - `indent_lines` - helper for code indentation
   - `read_template` - template file reading
   - `useful_doc` - doc string filtering

4. **Updated dune configuration:**
   - Added `predicates` module to codegen_lib

### Final File Sizes

| File | Original | Previous | Final | Reduction |
|------|----------|----------|-------|-----------|
| gen_low.ml | 1882 | 1191 | 1027 | 45% |
| gen_high.ml | 2295 | 1783 | 1689 | 26% |
| names.ml | N/A | 90 | 125 | N/A |
| type_mapping.ml | N/A | 117 | 213 | N/A |
| config.ml | N/A | 174 | 173 | N/A |
| predicates.ml | N/A | N/A | 7 | N/A |

### Validation Results

All validation criteria met:
- `dune build` - SUCCESS
- `dune build @check` - SUCCESS (no warnings)
- `dune test` - SUCCESS (all tests pass)
- `dune exec test/test_compute.exe` - SUCCESS (all runtime tests pass)
- Generated files unchanged (verified via SHA256 checksums)

### Future Improvements (Not Done)

The following items were considered but not implemented as they would require more
extensive restructuring without clear immediate benefit:

1. Directory structure (`lib/low/`, `lib/high/`) - not created
2. Extracting generator modules (Enums, Bitflags, Structs, Objects) - not done
3. Further extraction of type predicates from gen_high.ml - not done

These could be addressed in a future iteration if the files continue to grow.
