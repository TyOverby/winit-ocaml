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
    names.ml          # Name transformations (to_pascal_case, ocaml_module_name, etc.)
    types.ml          # Type mapping (IR -> OCaml type strings, IR -> C type strings)
    predicates.ml     # is_simple_struct, method_is_async, is_simple_arg_type, etc.

    low/
      enums.ml        # gen_c_enum_constants, gen_ml_enum, gen_mli_enum
      bitflags.ml     # gen_c_bitflag_constants, gen_ml_bitflag, gen_mli_bitflag
      structs.ml      # gen_c_struct_*, gen_ml_struct, gen_mli_struct
      objects.ml      # gen_c_object_stubs, gen_ml_object, gen_mli_object
      functions.ml    # gen_c_function_stubs

    high/
      enums.ml        # gen_ml_enum, gen_mli_enum (re-exports)
      bitflags.ml     # gen_ml_bitflag, gen_mli_bitflag
      objects.ml      # gen_ml_object, gen_mli_object, method generation
      entry_structs.ml # Entry struct module generation
      special_modules.ml # Instance, Adapter, Device, Queue
      convenience.ml  # Convenience functions

  gen_low.ml          # Entry point for low-level generation
  gen_high.ml         # Entry point for high-level generation
  gen_bindings.ml     # CLI entry point (already small)
```

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
