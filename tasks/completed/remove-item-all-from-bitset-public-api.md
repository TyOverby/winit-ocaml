# Remove Item.all from Bitset Public API

## Problem

The `Item.all` value is exposed in the public API of each bitset module in `high/bitsets.mli`:

```ocaml
module Buffer_usage : sig
  module Item : sig
    type t = | None | Map_read | ...
    val all : t list  (* Exposed but not useful to users *)
  end
  ...
end
```

This value is used internally to implement `all` and `to_list`, but users don't need access to it. They can use the bitset-level `all : t` value or `to_list : t -> Item.t list` function instead.

Exposing `Item.all` clutters the API and suggests a use pattern (manually iterating over items) that's better served by the bitset operations.

## Solution

Remove `val all : t list` from the `Item` submodule signature in the `.mli` file while keeping it in the `.ml` implementation for internal use.

### Before (bitsets.mli)

```ocaml
module Buffer_usage : sig
  module Item : sig
    type t = | None | Map_read | ...
    val all : t list
  end
  ...
end
```

### After (bitsets.mli)

```ocaml
module Buffer_usage : sig
  module Item : sig
    type t = | None | Map_read | ...
  end
  ...
end
```

The module type `S` at the top should also be updated:

```ocaml
module type S = sig
  module Item : sig
    type t
    (* val all : t list  -- removed *)
  end
  ...
end
```

## Files to Modify

- `codegen/gen_high.ml` - Update the bitset interface generation to not include `Item.all`

## Note on Functor Task

If the functor task (`use-functor-for-bitsets-ml.md`) is implemented first, the functor's input module type will still need `all : t list` internally. The change here only affects what's *exposed* to users in the `.mli`, not what the functor requires in the `.ml`.

## Testing

1. Run `dune build` to regenerate the bindings
2. Run `dune build @check` to ensure no warnings
3. Verify `high/bitsets.mli` no longer has `val all : t list` in Item modules
4. Run `dune exec test/test_compute.exe` to confirm tests pass

## Validation Criteria

1. `dune build` succeeds
2. `dune fmt > /dev/null || true` runs without error
3. `dune build @check` reports no warnings
4. Generated `high/bitsets.mli` has no `val all : t list` in any `Item` submodule
5. The `module type S` no longer includes `Item.all`
6. All existing tests pass (internal usage of `Item.all` still works)

## Implementation Plan

The code generator function `gen_bitset_with_helpers` in `codegen/gen_high.ml` generates
both the `.ml` and `.mli` for bitsets. The function distinguishes between `Implementation`
and `Interface` mode via the `output_mode` parameter.

The plan is:
1. In `gen_bitset_with_helpers`, remove `val all : t list` from the Item module signature
   when generating the interface (`.mli` file) - but keep it in the implementation (`.ml` file).
2. In `gen_bitsets_mli`, update the `module type S` definition to not include `val all : t list`
   in the Item submodule.

The `.ml` will continue to have `Item.all` since:
- The `Bitset_functor.Make` functor requires it via its `Item_intf` input module type
- The functor uses `Item.all` internally to implement `all` and `to_list`

Validation criteria:
1. Run `dune build` - must succeed
2. Run `dune fmt > /dev/null || true` - must not error
3. Run `dune build @check` - no warnings
4. Verify `high/bitsets.mli` has no `val all : t list` in any Item submodule
5. Verify `module type S` in `.mli` does not have `Item.all`
6. Run `dune exec test/test_compute.exe` - tests must pass
