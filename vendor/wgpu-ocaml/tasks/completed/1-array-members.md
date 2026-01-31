# Task #2: Support Descriptors with Array Members

## Goal

Enable auto-generation of methods where descriptor structs contain arrays of other structs. Currently blocked methods include:
- `device.create_bind_group_layout` - uses `bind_group_layout_descriptor` with array of `bind_group_layout_entry`
- `device.create_bind_group` - uses `bind_group_descriptor` with array of `bind_group_entry`

Once this task is done, we'll be able to remove more hardcoded functions in the generator.

## Current State

### What's Done
- `Pointer { inner = Array _ }` is now recognized as a simple type
- `create_pipeline_layout` works with arrays of objects (`Bind_group_layout.t list`)
- Low-level struct setters accept `nativeint array` for array members

### What's Blocking

The remaining cases involve arrays of **structs with nested struct members**:

```yaml
# bind_group_layout_entry has nested structs
- name: bind_group_layout_entry
  type: base_in
  members:
    - name: binding
      type: uint32
    - name: visibility
      type: bitflag.shader_stage
    - name: buffer           # nested struct!
      type: struct.buffer_binding_layout
    - name: sampler          # nested struct!
      type: struct.sampler_binding_layout
    - name: texture          # nested struct!
      type: struct.texture_binding_layout
    - name: storage_texture  # nested struct!
      type: struct.storage_texture_binding_layout
```

## Implementation Plan

### Phase 1: Define High-Level Record Types

For each struct that can appear in an array, generate an OCaml record type:

```ocaml
module Bind_group_layout_entry = struct
  type t =
    { binding : int
    ; visibility : Shader_stage.t list
    ; buffer : Buffer_binding_layout.t option
    ; sampler : Sampler_binding_layout.t option
    ; texture : Texture_binding_layout.t option
    ; storage_texture : Storage_texture_binding_layout.t option
    }
end

module Buffer_binding_layout = struct
  type t =
    { type_ : Buffer_binding_type.t
    ; has_dynamic_offset : bool
    ; min_binding_size : int64
    }
end
(* etc. for other nested structs *)
```

**Files to modify:**
- `codegen/gen_high.ml` - add record type generation for "entry" structs

### Phase 2: Identify Array-of-Struct Members

Add logic to detect when a struct member is an array of structs:

```ocaml
let member_is_array_of_structs (member : Ir.struct_member) : string option =
  match member.type_ with
  | Pointer { inner = Array { elem = Struct name; _ }; _ } -> Some name
  | Array { elem = Struct name; _ } -> Some name
  | _ -> None
```

**Files to modify:**
- `codegen/gen_high.ml` - add detection function

### Phase 3: Generate Conversion Code

For methods with array-of-struct members, generate code that:

1. Takes an OCaml list of records as input
2. Creates a C struct for each element
3. Creates nested C structs for each element's nested struct members
4. Sets all fields
5. Collects pointers into an array
6. Calls the low-level function
7. Frees all structs in reverse order

Example generated code for `create_bind_group_layout`:

```ocaml
let create_bind_group_layout t ?(label = "") ~entries () =
  (* Create descriptor *)
  let desc = Wgpu_low.Bind_group_layout_descriptor.bind_group_layout_descriptor_create () in
  Wgpu_low.Bind_group_layout_descriptor.bind_group_layout_descriptor_set_label desc label;

  (* Convert entries list to C structs *)
  let entry_structs = List.map entries ~f:(fun entry ->
    let e = Wgpu_low.Bind_group_layout_entry.bind_group_layout_entry_create () in
    Wgpu_low.Bind_group_layout_entry.bind_group_layout_entry_set_binding e entry.binding;
    Wgpu_low.Bind_group_layout_entry.bind_group_layout_entry_set_visibility e
      (Shader_stage.list_to_int entry.visibility);

    (* Handle nested struct: buffer *)
    (match entry.buffer with
     | Some buf ->
       let b = Wgpu_low.Buffer_binding_layout.buffer_binding_layout_create () in
       Wgpu_low.Buffer_binding_layout.buffer_binding_layout_set_type b
         (Buffer_binding_type.to_int buf.type_);
       Wgpu_low.Buffer_binding_layout.buffer_binding_layout_set_has_dynamic_offset b
         buf.has_dynamic_offset;
       Wgpu_low.Buffer_binding_layout.buffer_binding_layout_set_min_binding_size b
         buf.min_binding_size;
       Wgpu_low.Bind_group_layout_entry.bind_group_layout_entry_set_buffer e b;
       Some b
     | None -> None);
    (* ... similar for sampler, texture, storage_texture ... *)
    e, nested_structs
  ) in

  let entry_handles = Array.of_list (List.map entry_structs ~f:(fun (e, _) -> e)) in
  Wgpu_low.Bind_group_layout_descriptor.bind_group_layout_descriptor_set_entries desc entry_handles;

  let layout = Wgpu_low.device_create_bind_group_layout t.handle desc in

  (* Free all structs *)
  List.iter entry_structs ~f:(fun (e, nested) ->
    List.iter nested ~f:(fun n -> (* free nested struct *));
    Wgpu_low.Bind_group_layout_entry.bind_group_layout_entry_free e);
  Wgpu_low.Bind_group_layout_descriptor.bind_group_layout_descriptor_free desc;

  { Bind_group_layout.handle = layout }
```

**Files to modify:**
- `codegen/gen_high.ml` - add array-of-struct conversion code generation

### Phase 4: Update Method Generation Logic

Modify `method_is_high_level` and related functions to recognize methods with array-of-struct arguments as auto-generatable.

**Files to modify:**
- `codegen/gen_high.ml` - update `is_simple_struct`, `method_is_high_level`

## Testing Strategy

1. Start with `create_bind_group_layout` since it's commonly used
2. Write a test that creates a bind group layout with multiple entries
3. Verify the layout works in a compute pipeline
4. Then tackle `create_bind_group`

## Complexity Estimate

This is a medium-complexity task:
- Record type generation: straightforward
- Array conversion code: moderately complex (need to track nested structs for freeing)
- Main challenge: properly handling all the nested struct combinations

## Related Files

- `codegen/gen_high.ml` - main generator file
- `codegen/ir.ml` - IR definitions
- `high/wgpu.ml` - generated high-level bindings
- `high/wgpu.mli` - generated interface
