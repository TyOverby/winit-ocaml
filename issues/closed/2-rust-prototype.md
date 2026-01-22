# Rust prototype status

The rust project in `./prototype` doesn't currently build.  It might be useful
to have these working so that it will be easier in the future to diagnose if
a problem is caused by the ocaml bindings or if it's endemic to the approach
that we're taking.

## Currently

The prototype directory contains three binaries:
1. `simple_test.rs` - Uses type-erased `Box<dyn Any>` pattern (FAILING TO BUILD)
2. `pump_events_test.rs` - Uses `Rc<dyn Window>` directly (appears correct)
3. `manual_draw.rs` - Uses `Rc<dyn Window>` with separated event collection (appears correct)

Build errors in `simple_test.rs`:
- Lines 67 and 95: `downcast_mut()` calls lack type annotations
- Compiler cannot infer the type parameter `T` for `Surface<D, W>`

## Notes

The `simple_test.rs` file attempts to use type erasure (`Box<dyn Any>`) to avoid complex generic type signatures, but this requires explicit type annotations when downcasting. The error occurs because the compiler needs to know the exact `D` and `W` type parameters for `Surface<D, W>`.

Looking at the other two prototypes, they successfully use `Rc<dyn Window>` for both the display and window handle parameters. This is the pattern used in the main FFI implementation at `rust/src/lib.rs`, specifically with `Arc<Box<dyn Window>>`.

The fix is to either:
1. Add explicit type annotations to the `downcast_mut()` calls
2. Refactor to use the pattern from the other prototypes (recommended)

## Addressing

Fixed all three prototype binaries to build successfully:

### Root Cause
The winit API has evolved, and `create_window()` now returns `Box<dyn Window>` instead of a concrete window type. The prototypes were using outdated type patterns (`Rc<dyn Window>` or type erasure with owned handles) that no longer match the current API.

### Changes Made

1. **`simple_test.rs`**:
   - Replaced type erasure pattern (`Box<dyn Any>`) with direct types
   - Changed from `OwnedDisplayHandle`/`OwnedWindowHandle` to `Arc<Box<dyn Window>>`
   - Removed complex downcast logic
   - Simplified to match the pattern used in the main FFI code

2. **`pump_events_test.rs`**:
   - Changed from `Rc<dyn Window>` to `Arc<Box<dyn Window>>`
   - Updated all type signatures for `context` and `surface`
   - Fixed warning: removed unnecessary `mut` from `should_draw`

3. **`manual_draw.rs`**:
   - Changed from `Rc<dyn Window>` to `Arc<Box<dyn Window>>`
   - Updated `EventCollector` and `GraphicsState` structs
   - Added `#[allow(dead_code)]` for `context` field (kept alive for safety)
   - Fixed warning: removed ineffective `drop(window)` call

### Result
All three prototypes now build successfully with **zero warnings**. The pattern used (`Arc<Box<dyn Window>>`) matches exactly what the main FFI implementation uses in `rust/src/lib.rs`.
