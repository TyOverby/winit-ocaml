# Remove Duplicate Comments from .ml Files

## Problem

Now that `.mli` interface files have been created with comprehensive documentation, the `.ml` implementation files contain duplicate comments. This creates maintenance burden:

1. **Duplication** - Same documentation exists in both .ml and .mli files
2. **Sync risk** - If docs are updated in one place, they may get out of sync with the other
3. **Noise** - Implementation files are harder to read with all the doc comments
4. **Wrong location** - Documentation belongs in the interface, not the implementation

## Current State

Many functions in codegen/*.ml files have documentation comments like:

```ocaml
(** Convert snake_case to PascalCase. Handles numeric prefixes and double underscores.

    Examples:
    - "texture_format" -> "TextureFormat"
    - "1d" -> "N1d" (numeric prefix)
    - "some__value" -> "Some_Value" (double underscore preserved) *)
let to_pascal_case (s : string) : string =
  ...
```

This same documentation now exists in the corresponding .mli file.

## Proposed Fix

### Remove from .ml Files

1. **Function-level documentation comments** - Remove `(** ... *)` comments that document what a function does, its parameters, return values, and examples. These belong in the .mli file.

2. **Module-level documentation comments** - Remove top-of-file `(** ... *)` comments that describe the module's purpose. These belong in the .mli file.

### Keep in .ml Files

1. **Implementation comments** - Keep `(* ... *)` comments that explain HOW something works, not WHAT it does:
   ```ocaml
   (* Use a hashtable for O(1) lookup instead of List.find *)
   let cache = Hashtbl.create 100 in
   ```

2. **Inline explanations** - Keep comments that explain tricky code or non-obvious algorithms:
   ```ocaml
   (* Remove trailing 's' to get singular form *)
   let singular = String.chop_suffix_exn camel ~suffix:"s" in
   ```

3. **TODO/FIXME comments** - Keep comments about future work or known issues:
   ```ocaml
   (* TODO: Handle Unicode properly *)
   ```

## Example Transformation

**Before (.ml file):**
```ocaml
(** Convert snake_case to PascalCase.

    Handles numeric prefixes by adding 'N' prefix.
    Handles double underscores by preserving them. *)
let to_pascal_case (s : string) : string =
  (* Split on underscores *)
  let parts = String.split s ~on:'_' in
  ...
```

**After (.ml file):**
```ocaml
let to_pascal_case (s : string) : string =
  (* Split on underscores *)
  let parts = String.split s ~on:'_' in
  ...
```

The `(** ... *)` documentation comment is removed because it's in the .mli file, but the `(* Split on underscores *)` implementation comment is kept.

## What to Process

Files to clean up:
- `codegen/ir.ml` - Type definitions may have doc comments
- `codegen/names.ml` - Name transformation utilities
- `codegen/predicates.ml` - Predicate functions
- `codegen/config.ml` - Configuration functions
- `codegen/parse_yml.ml` - YAML parsing
- `codegen/type_mapping.ml` - Type mapping functions
- `codegen/gen_low.ml` - Low-level generator
- `codegen/gen_high.ml` - High-level generator

## Benefits

1. **Single source of truth** - Documentation exists only in .mli files
2. **Cleaner implementation** - .ml files focus on HOW, not WHAT
3. **Easier maintenance** - Update docs in one place
4. **Follow OCaml conventions** - Interface files are for documentation, implementation files are for code
5. **Reduced file sizes** - Less duplicate text

## Implementation Strategy

For each file:
1. Open both .ml and .mli side by side
2. Find function-level `(** ... *)` comments in .ml
3. Verify the same content exists in .mli
4. Remove from .ml (keep implementation comments)
5. Remove module-level documentation from .ml
6. Run `dune build @check` to ensure no issues

## Estimated Impact

- Medium value: Improves maintainability and follows best practices
- Low effort: Mostly mechanical deletion, low risk
