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
