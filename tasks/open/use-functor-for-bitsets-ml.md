# Use Functor to Eliminate Repetition in bitsets.ml

## Problem

The generated `high/bitsets.ml` has significant code duplication. Each bitset module (Buffer_usage, Color_write_mask, Map_mode, Shader_stage, Texture_usage) repeats the exact same 11 function implementations:

```ocaml
module Buffer_usage = struct
  module Item = struct
    type t = Wgpu_low.Buffer_usage.t = | None | Map_read | ...
    let to_int = Wgpu_low.Buffer_usage.to_int
    let all = [ None; Map_read; ... ]
  end

  type t = int

  (* These 11 lines are identical in every bitset module *)
  let singleton item = Item.to_int item
  let of_list items = List.fold_left (fun acc item -> acc lor Item.to_int item) 0 items
  let is_member t item = t land Item.to_int item <> 0
  let empty = 0
  let all = of_list Item.all
  let union a b = a lor b
  let inter a b = a land b
  let diff a b = a land lnot b
  let to_int t = t
  let to_list t = List.filter (fun item -> is_member t item) Item.all
  let list_to_int = of_list
end
```

With 5 bitset modules, this means 55 lines of duplicated code.

## Solution

Define a functor that takes an `Item` module and produces all the bitset operations:

```ocaml
module type Item_intf = sig
  type t

  val to_int : t -> int
  val all : t list
end

module Make (Item : Item_intf) = struct
  module Item = Item

  type t = int

  let singleton item = Item.to_int item
  let of_list items = List.fold_left (fun acc item -> acc lor Item.to_int item) 0 items
  let is_member t item = t land Item.to_int item <> 0
  let empty = 0
  let all = of_list Item.all
  let union a b = a lor b
  let inter a b = a land b
  let diff a b = a land lnot b
  let to_int t = t
  let to_list t = List.filter (fun item -> is_member t item) Item.all
  let list_to_int = of_list
end

module Buffer_usage = Make (struct
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
  let all = [ None; Map_read; Map_write; Copy_src; Copy_dst; Index; Vertex; Uniform; Storage; Indirect; Query_resolve ]
end)

module Color_write_mask = Make (struct
  type t = Wgpu_low.Color_write_mask.t = | None | Red | Green | Blue | Alpha | All
  let to_int = Wgpu_low.Color_write_mask.to_int
  let all = [ None; Red; Green; Blue; Alpha; All ]
end)

(* etc. *)
```

## Benefits

1. **Less generated code** - The functor is written once (could be handwritten or generated once), and each bitset module is just a functor application
2. **Easier to maintain** - If we need to add a new operation to all bitsets, we only change the functor
3. **Consistency guaranteed** - All bitset modules have identical behavior by construction

## Implementation Options

### Option A: Handwritten Functor + Generated Applications

Put the functor in a handwritten `high/bitset_functor.ml` file, and generate only the functor applications in `high/bitsets.ml`:

```ocaml
(* high/bitsets.ml - generated *)
module Buffer_usage = Bitset_functor.Make (struct
  type t = Wgpu_low.Buffer_usage.t = | None | Map_read | ...
  let to_int = Wgpu_low.Buffer_usage.to_int
  let all = [ None; Map_read; ... ]
end)
```

### Option B: Generate Everything Including Functor

Generate the functor definition at the top of `bitsets.ml`, followed by the applications.

### Recommendation

Option A is cleaner - the functor logic doesn't change based on the YAML, so it shouldn't be generated. Only the type-specific parts need generation.

## Files to Modify

- Create `high/bitset_functor.ml` (handwritten) with `Item_intf` and `Make` functor
- Create `high/bitset_functor.mli` (handwritten) exposing the module type and functor
- Modify `codegen/gen_high.ml` to generate functor applications instead of full module definitions

## Testing

1. Run `dune build` to regenerate the bindings
2. Run `dune build @check` to ensure no warnings
3. Run `dune exec test/test_compute.exe` to confirm tests pass
4. Verify generated `high/bitsets.ml` uses functor applications

## Validation Criteria

1. `dune build` succeeds
2. `dune fmt > /dev/null || true` runs without error
3. `dune build @check` reports no warnings
4. `high/bitset_functor.ml` contains the `Make` functor
5. Generated `high/bitsets.ml` uses `Make(...)` for each bitset module
6. All existing tests pass
