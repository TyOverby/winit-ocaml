# Hardcoded Templates Should Be Externalized

## Problem

Both `gen_low.ml` and `gen_high.ml` contain large blocks of hardcoded OCaml and C code
embedded as string literals. In `gen_high.ml`, this includes:

- `adapter_module_prefix` (~130 lines of hand-written OCaml)
- `adapter_module_suffix` (~15 lines)
- `instance_module` (~75 lines)
- Hand-written mli signatures for the same modules

In `gen_low.ml`:
- `gen_c_sync_helpers()` returns ~475 lines of C code as a string literal

These embedded strings:
1. Make the files much longer and harder to navigate
2. Are difficult to edit (no syntax highlighting, indentation is tricky)
3. Obscure what is "generated" vs "handwritten"
4. Make it hard to find where specific outputs come from

## Examples

```ocaml
let adapter_module_prefix =
  {|module Adapter_info = struct
  type t =
    { vendor : string
    ; architecture : string
    ...
|}
```

A newcomer looking for "where does Adapter_info come from?" would not expect to
find it inside a string literal in gen_high.ml.

## Proposed Fix

Move hardcoded templates to separate files that are read at generation time:

```
codegen/
  templates/
    high/
      adapter_info.ml.template
      queue.ml.template
      device_prefix.ml.template
      device_suffix.ml.template
      instance.ml.template
      convenience_functions.ml.template
    low/
      sync_helpers.c.template
      header.c.template
```

Then read these at generation time:
```ocaml
let adapter_info_template =
  In_channel.read_all "templates/high/adapter_info.ml.template"
```

## Benefits

1. Templates can be edited with proper syntax highlighting
2. Clear separation between generated and hand-written code
3. Easier to find where specific output comes from
4. Templates could potentially be validated independently
5. Reduces gen_high.ml by ~300+ lines

## Estimated Impact

- High value: Makes the codebase significantly more navigable
- Medium effort: Mostly mechanical extraction of existing strings
