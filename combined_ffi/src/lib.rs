// Combined FFI library that bundles both softbuffer_ffi and wgpu-native
// into a single staticlib, avoiding duplicate Rust stdlib symbols.
#[allow(unused_extern_crates)]
extern crate softbuffer_ffi;
#[allow(unused_extern_crates)]
extern crate wgpu_native;
