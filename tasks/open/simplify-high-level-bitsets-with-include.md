# Simplify High-Level Bitsets Using Include

The generated high-level bitset code in `high/bitsets.ml` redundantly redefines the `Item` module types and `to_int` functions that are identical to the low-level versions.

## Problem

### Redundant delegation in `Item.to_int`

```ocaml
module Buffer_usage = struct
  module Item = struct
    type t =
      | None
      | Map_read
      | Map_write
      ...

    let to_int = function
      | None -> Wgpu_low.Buffer_usage.to_int None
      | Map_read -> Wgpu_low.Buffer_usage.to_int Map_read
      | Map_write -> Wgpu_low.Buffer_usage.to_int Map_write
      ...
  end
  ...
end
```

The `Item.t` type is identical to `Wgpu_low.Buffer_usage.t`, and `Item.to_int` just reconstructs variants to pass to the low-level function.

## Solution

Use the low-level type directly for `Item`:

```ocaml
module Buffer_usage = struct
  module Item = struct
    type t = Wgpu_low.Buffer_usage.t =
      | None
      | Map_read
      | Map_write
      | Copy_src
      | Copy_dst
      | Index
      | Vertex
      | Uniform
      | Storage
      | Indirect
      | Query_resolve

    let to_int = Wgpu_low.Buffer_usage.to_int
  end

  type t = int

  let singleton item = Item.to_int item
  let of_list items = List.fold_left (fun acc item -> acc lor Item.to_int item) 0 items
  let is_member t item = t land Item.to_int item <> 0
end
```

The `type t = Wgpu_low.Buffer_usage.t = ...` syntax re-exports the type with its constructors visible, while `let to_int = Wgpu_low.Buffer_usage.to_int` directly delegates without reconstruction.

## Files to Modify

- `codegen/gen_high.ml` - Update the bitset generation logic

## Testing

1. Run `dune build` to regenerate the high-level bindings
2. Run `dune build @check` to ensure no warnings
3. Run existing tests to verify correctness
