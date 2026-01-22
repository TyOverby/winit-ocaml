# Implementation Findings and Recommendations

## Summary

I've explored the vendored `winit` and `softbuffer` libraries and validated the feasibility of creating OCaml bindings. The `pump_events` approach is confirmed to work for giving OCaml explicit control over the event loop, which is essential for this integration.

## Key Technical Findings

### 1. pump_events Pattern Works

The `pump_events` API in winit allows us to:
- Poll for events non-blockingly with `EventLoop::pump_app_events(timeout, &mut app)`
- Get explicit control over when events are processed
- Draw outside of the `RedrawRequested` callback (critical for OCaml integration)
- Return a `PumpStatus` to indicate if the loop should continue

This is exactly what we need for OCaml integration where OCaml code needs to control the main loop.

### 2. Window Handle Management

Key insight: `create_window()` returns `Box<dyn Window>`, which cannot be cloned. This creates challenges for sharing between softbuffer's Context and Surface.

**Solutions discovered:**
- softbuffer's `Context` and `Surface` can accept `OwnedDisplayHandle` and `OwnedWindowHandle`
- These owned handles can be obtained via `window.display_handle()?.to_owned()` and `window.window_handle()?.to_owned()`
- The owned handles allow softbuffer to work without needing a clone-able window

### 3. Lifetime and Ownership Challenges

The interaction between winit, softbuffer, and Rust's borrow checker revealed:
- Owned handles from `raw-window-handle` still carry lifetimes
- Context and Surface need to be stored together to avoid borrow conflicts
- Type erasure (Box<dyn Any>) is tricky with generic types that have lifetime parameters

**Recommended approach for FFI:**
- Store all related objects (Window, Context, Surface) together in a single Rust struct
- Pass opaque handles to OCaml rather than trying to expose individual components
- Use the builder pattern to ensure correct initialization order

### 4. Event Types

Winit has a rich event system with many event variants:
- `WindowEvent`: CloseRequested, RedrawRequested, SurfaceResized, KeyboardInput, PointerMoved, PointerButton, etc.
- `DeviceEvent`: Raw input events
- Many events carry complex nested data

**Recommendation:** Start with a subset of essential events and expand incrementally.

## Recommended Architecture for OCaml Bindings

### Rust Side Structure

```rust
// Single opaque handle that owns everything
pub struct WinitSoftbufferApp {
    event_loop: EventLoop<()>,
    handler: AppHandler,
}

struct AppHandler {
    window: Option<Box<dyn Window>>,
    context: Option<Context<OwnedDisplayHandle>>,
    surface: Option<Surface<OwnedDisplayHandle, OwnedWindowHandle>>,
}

// Simple C-compatible event type
#[repr(C)]
pub enum SimpleEvent {
    CloseRequested,
    Resized { width: u32, height: u32 },
    KeyPress { code: u32 },
    MouseMove { x: i32, y: i32 },
    MouseButton { button: u8, pressed: bool },
}

// FFI functions
#[no_mangle]
pub extern "C" fn winit_create() -> *mut WinitSoftbufferApp;

#[no_mangle]
pub extern "C" fn winit_pump_events(
    app: *mut WinitSoftbufferApp,
    events_out: *mut SimpleEvent,
    max_events: usize,
) -> i32; // Returns: event count, or -1 for exit

#[no_mangle]
pub extern "C" fn winit_get_buffer(
    app: *mut WinitSoftbufferApp,
    width_out: *mut u32,
    height_out: *mut u32,
) -> *mut u32; // Returns pointer to pixel buffer

#[no_mangle]
pub extern "C" fn winit_present(app: *mut WinitSoftbufferApp);

#[no_mangle]
pub extern "C" fn winit_destroy(app: *mut WinitSoftbufferApp);
```

### OCaml Side Structure

```ocaml
type app

type event =
  | CloseRequested
  | Resized of { width: int; height: int }
  | KeyPress of { code: int }
  | MouseMove of { x: int; y: int }
  | MouseButton of { button: int; pressed: bool }

external create : unit -> app = "winit_create"
external pump_events : app -> event list = "winit_pump_events"
external get_buffer : app -> (int * int * Bigarray.Array1.t) = "winit_get_buffer"
external present : app -> unit = "winit_present"
external destroy : app -> unit = "winit_destroy"

(* High-level API *)
let run ~init ~update ~render =
  let app = create () in
  let state = ref (init app) in
  try
    while true do
      let events = pump_events app in
      state := update !state events;
      let (width, height, buffer) = get_buffer app in
      render !state width height buffer;
      present app;
      Unix.sleepf 0.016; (* ~60 FPS *)
    done
  with Exit ->
    destroy app
```

## Simplified Prototype Approach

Given the complexity encountered, I recommend:

1. **Start with C FFI** instead of ocaml-rs for the initial prototype
   - Simpler, more predictable
   - Easier to debug
   - Can switch to ocaml-rs later for safety improvements

2. **Single opaque handle** that owns everything
   - Avoids lifetime issues
   - Simpler memory management
   - Clear ownership model

3. **Fixed-size event buffer** passed from OCaml
   - OCaml allocates array for events
   - Rust fills it up to max_events
   - Returns count of events written

4. **Direct buffer access** via Bigarray
   - Zero-copy pixel manipulation
   - Natural OCaml API
   - Good performance

## Next Steps

1. **Create minimal C FFI bindings**
   - Just window creation, event polling, and buffer access
   - Test with simple OCaml program

2. **Validate the approach**
   - Ensure no memory leaks
   - Check performance
   - Test on real hardware (need X11/Wayland)

3. **Expand incrementally**
   - Add more event types
   - Add window configuration options
   - Add damage regions for efficient updates

4. **Add safety layer**
   - Consider switching to ocaml-rs
   - Add resource cleanup tracking
   - Implement proper error handling

## Potential Issues and Mitigations

### Issue: Raw Pointers in FFI
- **Mitigation**: Use phantom types in OCaml to prevent misuse
- **Mitigation**: Implement finalizers for automatic cleanup
- **Mitigation**: Document ownership rules clearly

### Issue: Event Loop on Main Thread
- **Mitigation**: Document that winit must run on main thread
- **Mitigation**: Provide clear examples
- **Mitigation**: Consider thread validation in debug builds

### Issue: Platform Differences
- **Mitigation**: Focus on Linux (X11/Wayland) first
- **Mitigation**: Use conditional compilation
- **Mitigation**: Document platform-specific behavior

### Issue: Window Resize Handling
- **Mitigation**: Automatically resize surface in Rust layer
- **Mitigation**: Emit Resized event to OCaml
- **Mitigation**: Provide resize callback option

## Performance Considerations

- **Event Polling**: Non-blocking, should be fast
- **Buffer Access**: Zero-copy via Bigarray, optimal
- **Present**: Platform-dependent, may block on vsync
- **Frame Rate**: OCaml controls timing, easy to tune

## Safety Considerations

- **Memory Safety**: Rust code is safe, FFI boundary needs care
- **Thread Safety**: Document main-thread requirement
- **Resource Cleanup**: Implement finalizers in OCaml
- **Error Handling**: Convert Rust Results to OCaml exceptions

## Conclusion

The approach is sound and feasible. The key insights are:
1. Use pump_events for OCaml control
2. Keep Window/Context/Surface together in Rust
3. Use owned handles to avoid cloning issues
4. Start simple with C FFI before adding complexity
5. Test incrementally

The plan in `IMPLEMENTATION_PLAN.md` is still valid, but the FFI layer should be simpler than originally envisioned. Focus on a minimal, correct implementation first, then expand.
