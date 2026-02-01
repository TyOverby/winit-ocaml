# Remove _simple Convenience Variants

subproject: `wgpu` code generator

## Problem

The `begin_render_pass_simple` and `begin_compute_pass_simple` convenience functions were kept for backwards compatibility, but we don't want to maintain two versions of these APIs.

## Task

1. Remove the `_simple` variants from the template files:
   - `wgpu/codegen/templates/high/adapter_module_prefix.ml`
   - `wgpu/codegen/templates/high/adapter_module_prefix.mli`
   - `wgpu/codegen/templates/high/instance_module.ml`
   - `wgpu/codegen/templates/high/instance_module.mli`

2. Update all callsites to use the full auto-generated versions:
   - `Wgpu.begin_render_pass_simple` -> use `Wgpu.Command_encoder.begin_render_pass` with proper parameters
   - `Wgpu.begin_compute_pass_simple` -> use `Wgpu.Command_encoder.begin_compute_pass` with proper parameters
   - `Wgpu.Command_encoder.begin_render_pass_simple` -> `Wgpu.Command_encoder.begin_render_pass`
   - `Wgpu.Command_encoder.begin_compute_pass_simple` -> `Wgpu.Command_encoder.begin_compute_pass`

3. The auto-generated `begin_render_pass` takes structured parameters like `?color_attachments` (array of `Render_pass_color_attachment.t`). Each callsite will need to construct the appropriate records.

4. Regenerate code and verify build/tests pass.

## Task Completion

This task is complete when all `_simple` variants are removed and all tests pass using the full API.

## Currently

The `_simple` variants exist in four template files:
- `wgpu/codegen/templates/high/adapter_module_prefix.ml` - Contains `Command_encoder.begin_compute_pass_simple` and `Command_encoder.begin_render_pass_simple`
- `wgpu/codegen/templates/high/adapter_module_prefix.mli` - Contains signatures for the above
- `wgpu/codegen/templates/high/instance_module.ml` - Contains top-level `begin_compute_pass_simple` and `begin_render_pass_simple` convenience functions
- `wgpu/codegen/templates/high/instance_module.mli` - Contains signatures for the above

There are 47 files using these functions, including examples and tests.

## Notes

### API Signatures for Replacement

**begin_compute_pass** (auto-generated):
```ocaml
val begin_compute_pass
  :  t
  -> ?label:string
  -> ?timestamp_writes:Compute_pass_timestamp_writes.t
  -> unit
  -> Compute_pass_encoder.t
```
This is essentially identical to `begin_compute_pass_simple` - just drop the `_simple` suffix.

**begin_render_pass** (auto-generated):
```ocaml
val begin_render_pass
  :  t
  -> ?label:string
  -> ?color_attachments:Render_pass_color_attachment.t list
  -> ?depth_stencil_attachment:Render_pass_depth_stencil_attachment.t
  -> ?occlusion_query_set:Query_set.t
  -> ?timestamp_writes:Render_pass_timestamp_writes.t
  -> unit
  -> Render_pass_encoder.t
```

### Record Types

**Render_pass_color_attachment.t**:
```ocaml
type t =
  { view : Texture_view.t option
  ; depth_slice : int
  ; resolve_target : Texture_view.t option
  ; load_op : Load_op.t
  ; store_op : Store_op.t
  ; clear_value : Color.t option
  }
```

**Render_pass_color_attachment.Color.t**:
```ocaml
type t = { r : float; g : float; b : float; a : float }
```

**Render_pass_depth_stencil_attachment.t**:
```ocaml
type t =
  { view : Texture_view.t
  ; depth_load_op : Load_op.t
  ; depth_store_op : Store_op.t
  ; depth_clear_value : float
  ; depth_read_only : bool
  ; stencil_load_op : Load_op.t
  ; stencil_store_op : Store_op.t
  ; stencil_clear_value : int
  ; stencil_read_only : bool
  }
```

### Callsite Migration Patterns

**Simple render pass (color only)**:
```ocaml
(* Before *)
Wgpu.begin_render_pass_simple encoder ~label:"pass" ~color_view:view ~clear_color:(1.0, 0.0, 0.0, 1.0) ()

(* After *)
Wgpu.Command_encoder.begin_render_pass encoder ~label:"pass"
  ~color_attachments:[
    { view = Some view
    ; depth_slice = 0xFFFFFFFF  (* WGPU_DEPTH_SLICE_UNDEFINED for non-3D textures *)
    ; resolve_target = None
    ; load_op = Clear
    ; store_op = Store
    ; clear_value = Some { r = 1.0; g = 0.0; b = 0.0; a = 1.0 }
    }
  ] ()
```

**Render pass with depth**:
```ocaml
(* Before *)
Wgpu.begin_render_pass_simple encoder ~color_view ~clear_color:(0.2, 0.2, 0.2, 1.0)
  ~depth_view ~depth_load_op:Clear ~depth_store_op:Discard ~depth_clear_value:1.0 ()

(* After *)
Wgpu.Command_encoder.begin_render_pass encoder
  ~color_attachments:[
    { view = Some color_view; depth_slice = 0xFFFFFFFF; resolve_target = None
    ; load_op = Clear; store_op = Store
    ; clear_value = Some { r = 0.2; g = 0.2; b = 0.2; a = 1.0 } }
  ]
  ~depth_stencil_attachment:{
    view = depth_view
  ; depth_load_op = Clear; depth_store_op = Discard; depth_clear_value = 1.0
  ; depth_read_only = false
  ; stencil_load_op = Clear; stencil_store_op = Store; stencil_clear_value = 0
  ; stencil_read_only = false
  }
  ()
```

**Render pass with MSAA resolve**:
```ocaml
(* Before *)
Wgpu.begin_render_pass_simple encoder ~color_view:msaa_view ~clear_color:(0.1, 0.1, 0.2, 1.0)
  ~load_op:Clear ~store_op:Discard ~resolve_target:resolve_view ()

(* After *)
Wgpu.Command_encoder.begin_render_pass encoder
  ~color_attachments:[
    { view = Some msaa_view; depth_slice = 0xFFFFFFFF; resolve_target = Some resolve_view
    ; load_op = Clear; store_op = Discard
    ; clear_value = Some { r = 0.1; g = 0.1; b = 0.2; a = 1.0 } }
  ] ()
```

### Validation Criteria

1. All `_simple` variants removed from template files
2. Generated wgpu.ml and wgpu.mli no longer contain `_simple` variants
3. All 47 callsites updated to use the new API
4. `./build.sh` passes with no errors
5. `./test.sh` passes
6. `dune fmt` applied

## Addressing

Will follow this plan:
1. Remove `_simple` functions from templates
2. Regenerate code with `dune build`
3. Fix each callsite by converting to the new record-based API
4. Run tests to verify correctness
