# macOS wgpu Surface Support

## Summary

The `winit_wgpu` library currently supports creating wgpu surfaces on Linux (X11, Wayland) and Windows, but macOS (AppKit) is not yet implemented.

## Background

When issue #15 added wgpu integration, the surface creation code was implemented for:
- X11: Uses `Surface_source_xlib_window`
- Wayland: Uses `Surface_source_wayland_surface`
- Win32: Uses `Surface_source_windows_hwnd`

For macOS, the raw handle types exist in winit (`AppKit` backend), but:
1. The wgpu surface source type for macOS (`Surface_source_metal_layer`) needs to be used
2. The winit raw handle extraction may need additional fields (CAMetalLayer)

## Implementation Notes

The wgpu-native API for macOS uses:
- `WGPUSurfaceSourceMetalLayer` with a `layer` field pointing to a CAMetalLayer

This may require:
1. Adding metal layer extraction to `winit_window_get_raw_handle` in Rust FFI
2. Adding the metal layer field to `raw_handle` in OCaml
3. Adding the AppKit case in `winit_wgpu.ml`

## Priority

Low - Linux and Windows cover most use cases.
