# Remove Unused Functions from Codegen

## Problem

While adding `.mli` interface files, several functions were discovered to be unused and were prefixed with `_` to suppress warnings. These functions are dead code that should be removed entirely.

Additionally, there may be other unused functions that weren't caught in the initial pass.

## Known Unused Functions

From the recent .mli creation work, these functions were marked as unused (prefixed with `_`):

### Likely Candidates (need verification):
- Functions prefixed with `_` in any codegen module
- Helper functions that were used before refactoring but are now obsolete
- Functions that were copied during module extraction but aren't actually called
- Legacy functions from earlier implementations

## Investigation Strategy

1. **Use OCaml compiler warnings** - Run `dune build @check` and look for unused value warnings
2. **Search for underscore-prefixed functions** - `grep -n "^let _" codegen/*.ml`
3. **Use dead code detection tools** - If available, use tools like `dead_code_analyzer`
4. **Manual inspection** - Check each module for functions that aren't referenced

## What to Remove

For each unused function:
1. Verify it's truly unused (not called from anywhere)
2. Check if it's exposed in a .mli file (if so, it's part of the public API)
3. Remove the function entirely from the .ml file
4. Remove any associated helper functions that become unused

## What NOT to Remove

- Functions exposed in .mli files (even if not currently used, they're part of the API)
- Functions used in tests
- Functions that are clearly placeholders for future work (consider moving to a separate module or documenting why they exist)

## Verification

After removing functions:
1. Run `dune build @check` - should succeed with no warnings
2. Run `dune runtest` - all tests should pass
3. Run `dune exec test/test_compute.exe` - integration tests should pass
4. Check that generated output is identical: `dune build && diff` the generated files

## Benefits

1. **Cleaner codebase** - No dead code to confuse readers
2. **Faster compilation** - Less code to compile
3. **Reduced maintenance burden** - Don't have to maintain unused code
4. **Clearer intent** - What's in the code is what's actually used

## Estimated Impact

- Medium value: Cleans up technical debt
- Low effort: Mostly mechanical deletion once unused functions are identified

---

## Implementation Plan

### Functions to Remove

After investigation, the following 10 underscore-prefixed functions were identified as unused:

**codegen/names.ml (1 function):**
1. `_to_pascal_case_simple` - A simpler version of `to_pascal_case` that doesn't handle double underscores

**codegen/gen_low.ml (1 function):**
1. `_array_elem_c_type` - Gets the element type of an array type_ref

**codegen/gen_high.ml (8 functions):**
1. `_get_array_element_structs` - Gets all entry structs that appear in arrays within a struct
2. `_collect_inline_structs_recursive` - Collects all nested struct members recursively
3. `_high_level_member_type_of_type` - Gets high-level OCaml type for a type_ref
4. `_gen_inline_struct_conversion` - Generates code to convert a nested struct record field
5. `_gen_ml_method_with_structs` - Backward compatibility wrapper for method with structs
6. `_struct_has_array_of_structs` - Checks if a struct contains array-of-struct members
7. `_gen_nested_struct_module_mli` - Backward compatibility wrapper for nested struct module
8. `_gen_mli_method_with_structs` - Backward compatibility wrapper for method with structs

### Verification

- None of these functions are exposed in .mli files
- None are called from anywhere in the codebase (verified with grep)

### Validation Criteria

1. `dune build` succeeds
2. `dune build @check` succeeds with no warnings
3. `dune runtest` passes
4. `dune exec test/test_compute.exe` passes
5. Generated output files are identical to before the changes
