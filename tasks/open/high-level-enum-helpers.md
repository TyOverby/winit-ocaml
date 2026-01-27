# Add High-Level Enum/Bitflag Helper Functions

## Problem

The high-level enum and bitflag modules are currently just aliases to the low-level modules:

```ocaml
(* high/wgpu.ml *)
module Adapter_type = Wgpu_low.Adapter_type
module Buffer_usage = Wgpu_low.Buffer_usage
```

This provides no additional value over the low-level API. Users would benefit from higher-level helper functions for common operations.

## Proposed Solution

Change the high-level `.ml` to use `include` and add ergonomic helper functions, while keeping the `.mli` interface clean and documenting the full API.

### For Enums

```ocaml
(* high/wgpu.ml *)
module Adapter_type = struct
  include Wgpu_low.Adapter_type

  let to_string = function
    | Discrete_gpu -> "discrete_gpu"
    | Integrated_gpu -> "integrated_gpu"
    | Cpu -> "cpu"
    | Unknown -> "unknown"

  let all = [ Discrete_gpu; Integrated_gpu; Cpu; Unknown ]
end
```

### For Bitflags

```ocaml
(* high/wgpu.ml *)
module Buffer_usage = struct
  include Wgpu_low.Buffer_usage

  let to_string = function
    | None -> "none"
    | Map_read -> "map_read"
    | Map_write -> "map_write"
    (* ... *)

  let all = [ None; Map_read; Map_write; Copy_src; Copy_dst; Index; Vertex; Uniform; Storage; Indirect; Query_resolve ]

  (** Check if a flag is set in a combined int value *)
  let is_set flag combined = (combined land to_int flag) <> 0

  (** Convert combined int back to list of flags *)
  let of_int combined =
    List.filter (fun f -> is_set f combined) all

  (** Pretty-print a list of flags *)
  let list_to_string flags =
    flags |> List.map to_string |> String.concat " | "
end
```

### High-Level MLI

The `.mli` should document all functions including both the inherited low-level ones and the new helpers:

```ocaml
(* high/wgpu.mli *)
module Adapter_type : sig
  (** GPU adapter type *)

  type t =
    | Discrete_gpu
    | Integrated_gpu
    | Cpu
    | Unknown

  val to_int : t -> int
  val of_int : int -> t
  val to_string : t -> string
  val all : t list
end

module Buffer_usage : sig
  (** Buffer usage flags *)

  type t =
    | None
    | Map_read
    | Map_write
    (* ... *)

  val to_int : t -> int
  val list_to_int : t list -> int
  val to_string : t -> string
  val all : t list
  val is_set : t -> int -> bool
  val of_int : int -> t list
  val list_to_string : t list -> string
end
```

## Implementation

Modify `codegen/gen_high.ml`:

1. **Enum ML generation**: Use `include Wgpu_low.<Name>` then add `to_string` and `all`
2. **Bitflag ML generation**: Use `include Wgpu_low.<Name>` then add `to_string`, `all`, `is_set`, `of_int`, `list_to_string`
3. **Enum MLI generation**: Already lists the type and low-level functions; add signatures for new helpers
4. **Bitflag MLI generation**: Same as enums, plus bitflag-specific helpers

## Helper Functions Summary

| Function | Enums | Bitflags | Description |
|----------|-------|----------|-------------|
| `to_string` | Yes | Yes | Convert variant to snake_case string |
| `all` | Yes | Yes | List of all variants |
| `is_set` | No | Yes | Check if flag is set in combined int |
| `of_int` | (exists) | Yes | Convert int back to flag list |
| `list_to_string` | No | Yes | Pretty-print flag list |

## Validation

- All existing tests pass
- `dune build @check` passes with no warnings
- New helper functions are generated and usable
- `.mli` documents all functions with doc comments
