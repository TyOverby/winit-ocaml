# YAML Overrides File for Generator Customization

## Problem
The WebGPU YAML specification doesn't always provide the ideal API for OCaml. Some parameters that would benefit from having default values aren't marked as optional, requiring users to always pass them explicitly.

## Examples
- `buffer_descriptor.mapped_at_creation` - a bool that defaults to false in practice, but YAML doesn't mark it optional
- `sampler_descriptor` - many parameters (address modes, filters, etc.) have sensible defaults but aren't optional in YAML
- Other descriptor structs may have similar issues

## Proposed Solution
Create a YAML overrides file (e.g., `ocaml_overrides.yml`) that the generator reads alongside the main `webgpu.yml`. This file would allow:

1. **Adding optional markers to parameters**:
   ```yaml
   structs:
     buffer_descriptor:
       members:
         mapped_at_creation:
           optional: true
           default: false
   ```

2. **Specifying default values for optional parameters**:
   ```yaml
   structs:
     sampler_descriptor:
       members:
         address_mode_u:
           optional: true
           default: clamp_to_edge
   ```

3. **Renaming parameters for OCaml conventions**:
   ```yaml
   structs:
     some_descriptor:
       members:
         type:
           rename: type_  # Avoid OCaml keyword
   ```

## Benefits
- Keep auto-generated APIs ergonomic without hardcoding
- Easy to update as upstream YAML changes
- Clear documentation of OCaml-specific customizations
- Reduces need for manual implementations
