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

---

## Implementation Plan

### Approach

Modify the `gen_bitset_with_helpers` function in `codegen/gen_high.ml` to generate the simplified code:

1. For the `Item` module's type definition, use the type equality syntax:
   `type t = Wgpu_low.Module_name.t = | Variant1 | Variant2 ...`

2. For `Item.to_int`, use direct delegation:
   `let to_int = Wgpu_low.Module_name.to_int`

### Changes

- Update `gen_bitset_with_helpers` Implementation case:
  - Change the type definition to use `type t = Wgpu_low.X.t = ...`
  - Replace the match-based `to_int` function with direct delegation

- The Interface case already looks correct (just declares `type t` with variants)

### Validation Criteria

1. `dune build` succeeds
2. `dune fmt > /dev/null || true` runs without error
3. `dune build @check` reports no warnings
4. `dune exec test/test_compute.exe` passes all tests
5. Generated `high/bitsets.ml` uses the simplified syntax:
   - `type t = Wgpu_low.X.t = ...` for Item types
   - `let to_int = Wgpu_low.X.to_int` for Item.to_int
