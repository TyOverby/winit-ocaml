# Improve Naming Clarity

## Problem

Some names in the codebase are vague or potentially confusing:

### Vague Names

1. **`entry_struct`**: Used for structs that appear as elements in arrays. "Entry"
   is generic - "array element struct" or "nested array member struct" would be clearer.

2. **`nested_struct`**: Used for structs that are direct members of other structs
   (not in arrays). Conflicts somewhat with "entry_struct" concept.

3. **`is_simple_member_type`** vs **`is_simple_member_type_with_nested`**: The
   difference isn't clear from the names.

4. **`struct_args`**: In method generation, refers to arguments that are structs.
   Could be confused with "struct members" or "struct fields".

5. **`other_args`**: Very vague - "other" relative to what?

### Overloaded Concepts

The word "simple" is used to mean different things:
- `is_simple_member_type`: No nested structs
- `is_simple_struct`: All members are simple AND it's an input struct
- `is_simple_arg_type`: Can be easily converted
- `is_simple_return_type`: Primitive, enum, bitflag, or object
- `is_simple_output_struct`: Output struct with only simple readable members

## Proposed Fixes

### More Descriptive Names

```ocaml
(* Before *)
entry_struct
nested_struct
struct_args
other_args

(* After *)
array_element_struct    (* Struct that appears as array element *)
inline_struct           (* Struct that is a direct member of another *)
struct_parameters       (* Method parameters that are struct types *)
non_struct_parameters   (* Method parameters that aren't structs *)
```

### Clarify "Simple" Meanings

```ocaml
(* Before - multiple meanings of "simple" *)
is_simple_member_type
is_simple_struct
is_simple_arg_type

(* After - explicit about what makes it "simple" *)
is_flat_member_type     (* Contains no nested structs *)
is_auto_generable_struct (* Can be auto-generated: flat + input type *)
is_directly_convertible_arg (* Arg can be converted without struct handling *)
```

### Use Module Qualification

When the same concept exists at different levels:

```ocaml
(* Instead of *)
is_simple_member_type
is_simple_member_type_with_nested

(* Use modules *)
module Member_type = struct
  let is_flat ... = ...                (* No structs at all *)
  let is_flat_recursive structs ... = (* Allows nested simple structs *)
end
```

### Document with Types

```ocaml
(** A struct that appears as an element in array fields of other structs.
    These structs need special handling because they're passed as lists
    of records in the high-level API. *)
type array_element_struct = {
  struct_def : Ir.struct_;
  inline_structs : Ir.struct_ list; (* Structs inlined in this one *)
}
```

## Function Renaming Suggestions

| Current Name | Proposed Name |
|-------------|---------------|
| `get_simple_struct_args` | `get_auto_generable_struct_params` |
| `method_has_simple_struct_args` | `method_has_auto_generable_struct_params` |
| `method_has_output_struct_arg` | `get_output_struct_param` |
| `collect_nested_structs` | `collect_inline_structs_recursive` |
| `member_is_nested_struct` | `get_inline_struct_name` |
| `member_is_array_of_structs` | `get_array_element_struct_name` |

## Estimated Impact

- Medium value: Reduces confusion when reading/modifying code
- Low effort: Mostly renaming with search/replace
