# Minimize .mli Exports with For_testing Submodule

## Problem

The recently created `.mli` interface files expose too much functionality. They currently export many internal helper functions that are only needed for:
1. Testing (unit tests need access to internal functions)
2. Cross-module usage (but not truly public API)

This makes the public API larger than necessary and harder to understand.

## Current State

Many `.mli` files expose internal helpers that aren't part of the core public API:

**Example: `names.mli`**
```ocaml
val to_pascal_case : string -> string
val to_camel_case : string -> string
val normalize_enum_entry_name : string -> string
val escape_keyword : string -> string
val ocaml_keywords : string list
val indent_lines : string -> int -> string
val read_template : string -> string
val useful_doc : string option -> string option
```

Of these, `indent_lines`, `read_template`, and `useful_doc` are likely only used by tests or internally by other modules.

**Example: `gen_high.mli`**
Many helper functions are exposed that are only used for testing, like:
- `is_flat_member_type`
- `is_directly_convertible_arg`
- `get_inline_struct_name`
- `member_is_array_of_structs`

These clutter the public API.

## Proposed Solution

### Use For_testing Submodule Pattern

Following Jane Street conventions, organize each `.mli` file as:

```ocaml
(** Primary public API - only what users/other modules truly need *)
val main_function : api -> string
val another_public_function : string -> string

(** Functions needed for testing but not part of the public API *)
module For_testing : sig
  val internal_helper : string -> string
  val predicate_for_tests : type_ref -> bool
end
```

### For Each Module

**ir.mli** - Already minimal, likely needs no For_testing module (just type definitions)

**names.mli** - Core API should be name transformations:
```ocaml
val to_pascal_case : string -> string
val to_camel_case : string -> string
val normalize_enum_entry_name : string -> string
val escape_keyword : string -> string

module For_testing : sig
  val ocaml_keywords : string list
  val indent_lines : string -> int -> string
  val read_template : string -> string
  val useful_doc : string option -> string option
end
```

**predicates.mli** - Already minimal (just `method_is_async`)

**config.mli** - Public API should be:
```ocaml
module Method_key : sig ... end
type method_handling = ...
val get_handling : object_name:string -> method_name:string -> method_handling
val is_accounted_for : object_name:string -> method_name:string -> bool

module For_testing : sig
  val is_manual : object_name:string -> method_name:string -> bool
  val is_skipped : object_name:string -> method_name:string -> bool
  val manual_methods : Method_key.t list
  val skipped_methods : Method_key.t list
  val validate_config : Ir.api -> unit
end
```

**parse_yml.mli** - Already minimal (just `load_file`)

**type_mapping.mli** - Core API:
```ocaml
type context = ...
val type_string : context:context -> Ir.type_ref -> string
val convert_arg_to_low : var_name:string -> Ir.type_ref -> string
val convert_return_to_high : expr:string -> Ir.type_ref -> string
val convert_member_to_low : var_name:string -> member_name:string -> Ir.type_ref -> string

module For_testing : sig
  val ocaml_module_name : string -> string
  val c_type_name : string -> string
end
```

**gen_low.mli** - Core API:
```ocaml
val gen_c_stubs : Ir.api -> string
val gen_ml : Ir.api -> string
val gen_mli : Ir.api -> string

module For_testing : sig
  (* Individual generators for testing *)
  val gen_ml_enum : Ir.enum -> string
  val gen_mli_enum : Ir.enum -> string
  (* ... other individual generators ... *)
end
```

**gen_high.mli** - Core API:
```ocaml
val gen_ml : Ir.api -> string
val gen_mli : Ir.api -> string
val check_method_coverage : Ir.api -> unit

module For_testing : sig
  (* Predicates *)
  val is_flat_member_type : Ir.type_ref -> bool
  val is_directly_convertible_arg : Ir.type_ref -> bool
  (* ... other testing utilities ... *)
end
```

## Implementation Strategy

For each .mli file:
1. Identify the core public API (what other modules/users truly need)
2. Identify functions only used by tests (grep through test files)
3. Identify internal helpers that could be private
4. Restructure: core functions at top level, testing functions in For_testing
5. Update test files to use `Module.For_testing.function_name`
6. Verify everything builds and tests pass

## Benefits

1. **Clearer API** - Easy to see what the core functionality is
2. **Better encapsulation** - Internal helpers are clearly marked
3. **Follows Jane Street conventions** - Standard pattern in Core/Base libraries
4. **Maintains testability** - Tests can still access internals via For_testing
5. **Documentation** - Clear separation between public and testing APIs

## Estimated Impact

- High value: Significantly improves API clarity and organization
- Medium effort: Requires analysis of what's truly public vs for testing
