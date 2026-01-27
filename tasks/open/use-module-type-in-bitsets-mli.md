# Use Module Type S in bitsets.mli

## Problem

The generated `high/bitsets.mli` defines a module type `S` at the top of the file, but it's never used. Each concrete module (Buffer_usage, Color_write_mask, Map_mode, Shader_stage, Texture_usage) redundantly repeats all the same function signatures.

### Current State

```ocaml
module type S = sig
  module Item : sig
    type t
    val all : t list
  end
  type t
  val singleton : Item.t -> t
  val of_list : Item.t list -> t
  val is_member : t -> Item.t -> bool
  val empty : t
  val all : t
  val union : t -> t -> t
  val inter : t -> t -> t
  val diff : t -> t -> t
  val to_int : t -> int
  val to_list : t -> Item.t list
end

module Buffer_usage : sig
  module Item : sig
    type t = | None | Map_read | Map_write | ...
    val all : t list
  end
  type t = int
  val singleton : Item.t -> t      (* repeated *)
  val of_list : Item.t list -> t   (* repeated *)
  val is_member : t -> Item.t -> bool  (* repeated *)
  (* ... 8 more repeated signatures ... *)
  val list_to_int : Item.t list -> t  (* only unique part *)
end

(* Same pattern repeats for Color_write_mask, Map_mode, etc. *)
```

## Solution

Use `include S with type Item.t := ...` to include the module type and only specify the unique parts:

```ocaml
module type S = sig
  module Item : sig
    type t
    val all : t list
  end
  type t
  val singleton : Item.t -> t
  val of_list : Item.t list -> t
  val is_member : t -> Item.t -> bool
  val empty : t
  val all : t
  val union : t -> t -> t
  val inter : t -> t -> t
  val diff : t -> t -> t
  val to_int : t -> int
  val to_list : t -> Item.t list
end

module Buffer_usage : sig
  module Item : sig
    type t = | None | Map_read | Map_write | Copy_src | ...
    val all : t list
  end

  include S with type Item.t := Item.t

  val list_to_int : Item.t list -> t
end
```

This reduces each module from ~20 lines to ~10 lines and ensures consistency with the module type.

## Files to Modify

- `codegen/gen_high.ml` - Update the bitset interface generation to use `include S with type Item.t := Item.t`

## Implementation Notes

The key change is in the Interface generation path for bitsets. Instead of generating each function signature individually, generate:

1. The `Item` submodule with its concrete type and `all` value
2. `include S with type Item.t := Item.t`
3. Any extra signatures not in `S` (like `list_to_int`)

## Testing

1. Run `dune build` to regenerate the bindings
2. Run `dune build @check` to ensure no warnings
3. Verify the generated `high/bitsets.mli` uses the include syntax
4. Run `dune exec test/test_compute.exe` to confirm tests pass

## Validation Criteria

1. `dune build` succeeds
2. `dune fmt > /dev/null || true` runs without error
3. `dune build @check` reports no warnings
4. Generated `high/bitsets.mli` uses `include S with type Item.t := Item.t` in each module
5. Each bitset module signature is significantly shorter (no repeated function signatures)
