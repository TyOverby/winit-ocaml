# Add Touch Gesture Events Support

## Background

winit provides several touch gesture events for trackpads and touchscreens. These enable natural multi-touch interactions on supported platforms.

## What's Missing

winit provides the following gesture events:

1. **PinchGesture** - Two-finger pinch (zoom)
   - `delta: f64` - Positive = magnify, negative = shrink
   - `phase: TouchPhase` - Started/Moved/Ended/Cancelled
   - Platforms: **macOS, iOS, Wayland** ✓

2. **PanGesture** - Multi-finger pan
   - `delta: PhysicalPosition<f32>` - Pixel movement since last update
   - `phase: TouchPhase`
   - Platforms: **iOS, Wayland** ✓

3. **RotationGesture** - Two-finger rotation
   - `delta: f32` - Rotation in degrees (positive = counterclockwise)
   - `phase: TouchPhase`
   - Platforms: **macOS, iOS, Wayland** ✓

4. **DoubleTapGesture** - Smart magnification
   - No data, just the event
   - Platforms: **macOS, iOS** ✓

5. **TouchpadPressure** - Force touch
   - `pressure: f32` - Pressure value 0.0 to 1.0
   - `stage: i64` - Click level
   - Platforms: **macOS** ✓ (forcetouch-capable trackpads only)

## Implementation

These events are straightforward to add since they have simple data types (floats, enums already supported).

### Rust FFI

```rust
WindowEvent::PinchGesture { delta, phase, .. } => {
    let mut data = [0i32; 16];
    data[0] = encode_f32(delta as f32);
    data[1] = match phase {
        TouchPhase::Started => 0,
        TouchPhase::Moved => 1,
        TouchPhase::Ended => 2,
        TouchPhase::Cancelled => 3,
    };
    // ...
}
```

### OCaml API

```ocaml
type event =
  | (* existing events *)
  | PinchGesture of { delta: float; phase: touch_phase }
  | PanGesture of { dx: float; dy: float; phase: touch_phase }
  | RotationGesture of { delta: float; phase: touch_phase }
  | DoubleTapGesture
  | TouchpadPressure of { pressure: float; stage: int }
```

## Usage Examples

```ocaml
(* Pinch to zoom *)
| PinchGesture { delta; phase = Moved } ->
    zoom_level := !zoom_level *. (1.0 +. delta)

(* Two-finger pan *)
| PanGesture { dx; dy; phase = Moved } ->
    pan_x := !pan_x +. dx;
    pan_y := !pan_y +. dy

(* Rotation *)
| RotationGesture { delta; phase = Moved } ->
    rotation := !rotation +. delta

(* Smart zoom toggle *)
| DoubleTapGesture ->
    zoom_to_fit := not !zoom_to_fit

(* Force touch *)
| TouchpadPressure { pressure; stage } ->
    if stage > 1 then
      (* Deep press action *)
```

## Platform Support

| Event | macOS | iOS | Wayland | Windows | X11 | Android | Web |
|-------|-------|-----|---------|---------|-----|---------|-----|
| PinchGesture | ✓ | ✓ | ✓ | ✗ | ✗ | ✗ | ✗ |
| PanGesture | ✗ | ✓ | ✓ | ✗ | ✗ | ✗ | ✗ |
| RotationGesture | ✓ | ✓ | ✓ | ✗ | ✗ | ✗ | ✗ |
| DoubleTapGesture | ✓ | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ |
| TouchpadPressure | ✓* | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |

*Requires force-touch capable trackpad

## Implementation Complexity

**Low** - These events have simple data types that fit easily in the existing 16-field event buffer. The main challenge is platform testing since not all platforms support these gestures.

## Testing Considerations

- Requires hardware with gesture support (trackpad or touchscreen)
- Platform-specific behavior may vary
- iOS gestures require explicit enablement via window attributes

## Notes

- Some gestures may conflict with OS-level gestures
- Gesture recognition varies by platform
- Consider providing gesture configuration options
- Document platform availability clearly in API docs

## References

- [winit gesture docs](https://docs.rs/winit/latest/winit/event/enum.WindowEvent.html#variant.PinchGesture)
- [macOS gesture guide](https://developer.apple.com/design/human-interface-guidelines/gestures)
- [Wayland input docs](https://wayland.freedesktop.org/docs/html/)
