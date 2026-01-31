# Add .mli Interface Files to Codegen Modules

## Problem

Most modules in the `codegen/` directory lack `.mli` interface files. Only `type_mapping.mli` currently exists. Without interface files:

1. **No explicit public API** - Everything in the module is exposed by default
2. **No documentation at module boundaries** - Users must read implementation to understand usage
3. **No encapsulation** - Internal helpers are publicly visible
4. **Harder to understand** - No clear contract for what a module provides
5. **Missed optimization opportunities** - Compiler can't optimize based on interface constraints

## Current State

Files in `codegen/` directory:
- ✅ `type_mapping.ml` / `type_mapping.mli` - Has interface file
- ❌ `config.ml` - Missing .mli
- ❌ `gen_bindings.ml` - Missing .mli (entry point, may not need one)
- ❌ `gen_high.ml` - Missing .mli
- ❌ `gen_low.ml` - Missing .mli
- ❌ `ir.ml` - Missing .mli
- ❌ `names.ml` - Missing .mli
- ❌ `parse_yml.ml` - Missing .mli
- ❌ `predicates.ml` - Missing .mli

## Proposed Fix

Create `.mli` interface files for all modules (except `gen_bindings.ml` which is an entry point):

### Priority Order

1. **High Priority** - Library modules used by other modules:
   - `ir.mli` - Type definitions for the intermediate representation
   - `names.mli` - Name transformation utilities
   - `predicates.mli` - Type checking predicates
   - `config.mli` - Configuration and method handling
   - `parse_yml.mli` - YAML parsing functions

2. **Medium Priority** - Generator modules:
   - `gen_low.mli` - Low-level code generation
   - `gen_high.mli` - High-level code generation

3. **Low Priority** - Entry point:
   - `gen_bindings.ml` - CLI entry point (may not need .mli)

### What to Include in Each .mli

For each module, the `.mli` file should:

1. **Document the module purpose** with a header comment
2. **Expose public types** with documentation
3. **Expose public functions** with:
   - Type signatures
   - Documentation explaining purpose
   - Examples where helpful
4. **Hide internal helpers** by not including them in the interface
5. **Follow Jane Street conventions** with clear, concise documentation

### Example Pattern

```ocaml
(** Names - Name transformation utilities for code generation.

    This module provides functions for converting between different naming conventions
    used in the WebGPU API and OCaml code. *)

(** Convert snake_case to PascalCase. Handles numeric prefixes and double underscores.

    Examples:
    - "texture_format" -> "TextureFormat"
    - "1d" -> "N1d" (numeric prefix)
    - "some__value" -> "Some_Value" (double underscore preserved) *)
val to_pascal_case : string -> string

(** Convert snake_case to camelCase.

    Examples:
    - "bind_group_layout" -> "bindGroupLayout"
    - "entry_count" -> "entryCount" *)
val to_camel_case : string -> string

...
```

## Benefits

1. **Clear module contracts** - Easy to see what each module provides
2. **Better encapsulation** - Internal helpers are hidden from users
3. **Documentation** - Module-level and function-level docs in one place
4. **IDE support** - Better autocomplete and hover documentation
5. **Faster compilation** - Compiler can check against interface without reading implementation
6. **Easier refactoring** - Can change implementation without affecting users if interface is stable

## Implementation Notes

- Start with library modules (ir, names, predicates, config) as they're used by others
- Use `ocamlformat` to format the .mli files
- Run `dune build @check` to ensure no warnings
- Consider what should be private vs public for each module
- Add documentation as you create the interfaces

## Estimated Impact

- High value: Significantly improves code documentation and encapsulation
- Low effort: Mostly extracting existing function signatures and adding docs

## Implementation Plan

### Approach

Create .mli interface files for each module in priority order. For each file:
1. Add a module-level doc comment explaining the module's purpose
2. Expose only public types and functions used by other modules or gen_bindings.ml
3. Hide internal helper functions not needed externally
4. Add documentation to exposed types and functions
5. Follow Jane Street conventions for naming and documentation

### Priority Order

1. **ir.mli** - Core type definitions (all types are public, just need doc comments)
2. **names.mli** - Public name transformation utilities
3. **predicates.mli** - Public predicates for code generation
4. **config.mli** - Method handling configuration (expose Method_key, method_handling, and lookup functions)
5. **parse_yml.mli** - Only expose load_file (main entry point)
6. **gen_low.mli** - Expose output_mode and gen_* functions
7. **gen_high.mli** - Expose output_mode, record types, and gen_* functions

### Validation Criteria

1. All .mli files created and formatted
2. `dune build @check` passes with no warnings
3. `dune exec test/test_compute.exe` tests pass
4. Internal helpers are hidden from public API
5. Each module has clear documentation
