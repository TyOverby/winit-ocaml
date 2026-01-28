# Fix Surface Module Ordering for Auto-generation

## Problem

The `surface.configure` and `surface.get_capabilities` methods are marked as Manual with reason "Module ordering issue". The codegen produces correct high-level code for these methods:

**surface.configure:**
```ocaml
val configure : t -> device:Device.t -> format:Texture_format.t -> usage:Texture_usage.Item.t list ->
  width:int -> height:int -> ?view_formats:Texture_format.t list ->
  alpha_mode:Composite_alpha_mode.t -> present_mode:Present_mode.t -> unit -> unit
```

**surface.get_capabilities:**
```ocaml
val get_capabilities : t -> adapter:Adapter.t -> surface_capabilities
```

The problem is that:
1. Surface module is generated at line ~462 in wgpu.ml
2. Device and Adapter modules are defined later at line ~951+
3. The generated methods reference `Device.t` and `Adapter.t` which don't exist yet

## Solution

Restructure the module generation order so that Surface comes after Device and Adapter. This requires:

1. Changing how modules are ordered in `gen_high.ml`
2. Possibly adding Surface to a later template section (like after the adapter module)
3. Adding an injection point to Surface for auto-generated methods

### Implementation Approach

**Option A: Move Surface to template section**

Add Surface module definition to `adapter_module_suffix.ml` (after Device and Adapter):

```ocaml
module Surface = struct
  type t = { handle : Wgpu_low.surface }

  type surface_capabilities = { ... }
  type surface_texture = { ... }

  (* Manual methods *)
  let release t = ...
  let get_current_texture t = ...
  let present t = ...
  let unconfigure t = ...

  (* AUTO-GENERATED SURFACE METHODS INJECTED HERE *)
end
```

**Option B: Reorder auto-generated modules**

Modify `gen_high.ml` to emit Surface module after Device/Adapter instead of in alphabetical order.

Option A is simpler and consistent with the current template pattern.

## Files to Modify

- `codegen/gen_high.ml` - Skip auto-generating Surface module in the main loop
- `codegen/templates/high/adapter_module_suffix.ml` - Add Surface module with injection point
- `codegen/templates/high/adapter_module_suffix.mli` - Add Surface module signature
- `codegen/config.ml` - Remove `surface.configure` and `surface.get_capabilities` from Manual list

## Testing

1. Run `dune build` to regenerate code
2. Verify Surface module appears after Device/Adapter in wgpu.ml
3. Verify `configure` and `get_capabilities` are auto-generated
4. Run `dune exec test/test_compute.exe` - should still pass
5. Run `dune build @check` - no warnings

## Validation Criteria

1. `dune build` succeeds
2. `dune build @check` reports no warnings
3. Surface.configure and Surface.get_capabilities are auto-generated in wgpu.ml
4. All tests pass
