# Event System Documentation

This document describes the event system in winit-ocaml, including all supported event types and their fields.

## Overview

winit-ocaml provides a comprehensive event system that exposes window events from the underlying winit library to OCaml. Events are polled using the `pump_events` function and returned as a list of typed events.

## Event Types

### Window Lifecycle Events

#### `CloseRequested`
The user requested to close the window (e.g., clicked the X button).

**Fields:** None

**Example:**
```ocaml
| CloseRequested ->
    Printf.printf "Window close requested\n";
    should_exit := true
```

#### `Destroyed`
The window has been destroyed.

**Fields:** None

**Notes:** After this event, the window is no longer usable.

#### `Focused` / `Unfocused`
Window focus state changed.

**Fields:** None

**Example:**
```ocaml
| Focused -> Printf.printf "Window gained focus\n"
| Unfocused -> Printf.printf "Window lost focus\n"
```

#### `Occluded` / `Unoccluded`
Window is completely hidden from view or becomes visible again.

**Fields:** None

**Platform support:**
- **macOS/iOS:** Tracks application lifecycle states
- **Web:** Tracks visibility with respect to CSS properties
- **Android/Wayland/Windows:** Not supported

---

### Window Geometry Events

#### `SurfaceResized`
The window surface was resized.

**Fields:**
- `width: int` - New width in pixels
- `height: int` - New height in pixels

**Example:**
```ocaml
| SurfaceResized { width; height } ->
    Printf.printf "Window resized to %dx%d\n" width height
```

**Notes:** This event is not necessarily emitted on window creation. Query `get_buffer` for initial size.

#### `WindowMoved`
The window was moved to a new position.

**Fields:**
- `x: int` - New X position in screen coordinates
- `y: int` - New Y position in screen coordinates

**Platform support:**
- **iOS/Android/Web/Wayland:** Not supported

---

### Display Events

#### `RedrawRequested`
The window needs to be redrawn.

**Fields:** None

**Notes:** Triggered by the OS or explicitly via window redraw request. Use this as a signal to render a new frame.

#### `ThemeChanged`
The system theme changed.

**Fields:**
- `theme` - New theme (`Light` or `Dark`)

**Example:**
```ocaml
| ThemeChanged Light -> set_color_scheme LightMode
| ThemeChanged Dark -> set_color_scheme DarkMode
```

**Platform support:**
- **iOS/Android/X11/Wayland:** Not supported

#### `ScaleFactorChanged`
The window's DPI scale factor changed.

**Fields:**
- `float` - New scale factor (e.g., 1.0, 1.5, 2.0)

**Example:**
```ocaml
| ScaleFactorChanged scale ->
    Printf.printf "DPI scale changed to %.2fx\n" scale
```

**Notes:** This can occur when:
- Moving window between monitors with different DPIs
- Changing display resolution
- Changing system scale factor settings

---

### Keyboard Events

#### `KeyPressed` / `KeyReleased`
A keyboard key was pressed or released.

**Fields:**
- `key_code: int` - Physical key code (scancode), layout-independent
- `location: key_location` - Location of key on keyboard
  - `Standard` - Most keys
  - `Left` - Left variant (e.g., left Shift)
  - `Right` - Right variant (e.g., right Shift)
  - `Numpad` - Numeric keypad keys
- `repeat: bool` - True if this is an auto-repeat event

**Example:**
```ocaml
| KeyPressed { key_code; location = Standard; repeat = false } ->
    Printf.printf "Key %d pressed\n" key_code
| KeyPressed { repeat = true; _ } ->
    Printf.printf "Key auto-repeat\n"
```

**Notes:**
- Key codes are platform-independent physical positions (e.g., WASD always refers to the same physical keys regardless of keyboard layout)
- For text input, use IME events (future feature)
- Some platforms generate synthetic press/release events when window focus changes

#### `ModifiersChanged`
Keyboard modifier states changed.

**Fields:**
- `shift: modifier_key_state` - Shift key state
- `control: modifier_key_state` - Control key state
- `alt: modifier_key_state` - Alt key state
- `super: modifier_key_state` - Super/Windows/Command key state

Each modifier can be:
- `Unknown` - State unknown or not pressed
- `LeftPressed` - Only left variant pressed
- `RightPressed` - Only right variant pressed
- `BothPressed` - Both left and right pressed

**Example:**
```ocaml
| ModifiersChanged { shift = LeftPressed; control = Unknown; _ } ->
    Printf.printf "Left Shift pressed\n"
| ModifiersChanged { shift = BothPressed; _ } ->
    Printf.printf "Both Shift keys pressed\n"
```

---

### Pointer Events

#### `PointerMoved`
The pointer moved within the window.

**Fields:**
- `x: float` - X coordinate relative to window top-left
- `y: float` - Y coordinate relative to window top-left
- `primary: bool` - True if this is the primary pointer
- `source: pointer_source` - Source type (Mouse, Touch, Tablet, Unknown)

**Example:**
```ocaml
| PointerMoved { x; y; source = Mouse; _ } ->
    Printf.printf "Mouse at (%.1f, %.1f)\n" x y
```

**Notes:**
- Coordinates are in pixels relative to window
- Use `DeviceEvent::PointerMotion` for raw mouse input (future feature)
- Web: Doesn't account for CSS border/padding/transform

#### `PointerEntered` / `PointerLeft`
Pointer entered or left the window bounds.

**Fields:**
- `x: float` - Position when entering/leaving
- `y: float` - Position when entering/leaving
- `primary: bool` - True if primary pointer
- `source: pointer_source` - Source type

**Notes:**
- `PointerLeft` position may be outside window bounds
- **Windows/Orbital:** `PointerLeft` always reports `(0, 0)`

#### `PointerButtonPressed` / `PointerButtonReleased`
A pointer button was pressed or released.

**Fields:**
- `button: int` - Button identifier
  - `1` = Left button
  - `2` = Right button
  - `3` = Middle button
  - `4` = Back button
  - `5` = Forward button
  - `6`, `7`, `8` = Additional buttons
- `x: float` - X coordinate when button event occurred
- `y: float` - Y coordinate when button event occurred
- `primary: bool` - True if primary pointer

**Example:**
```ocaml
| PointerButtonPressed { button = 1; x; y; _ } ->
    Printf.printf "Left click at (%.1f, %.1f)\n" x y
```

#### `MouseWheel`
Mouse wheel or trackpad scroll.

**Fields:**
- `delta_type: mouse_wheel_delta_type` - Type of measurement
  - `Line` - Delta in lines (typical for mouse wheels)
  - `Pixel` - Delta in pixels (typical for trackpads)
- `x: float` - Horizontal scroll amount
- `y: float` - Vertical scroll amount
- `phase: touch_phase` - Scroll gesture phase
  - `Started` - Scroll started
  - `Moved` - Scroll continuing
  - `Ended` - Scroll ended
  - `Cancelled` - Scroll cancelled

**Example:**
```ocaml
| MouseWheel { delta_type = Line; y; _ } when y > 0.0 ->
    Printf.printf "Scroll up %f lines\n" y
| MouseWheel { delta_type = Pixel; x; y; _ } ->
    Printf.printf "Trackpad scroll (%f, %f) pixels\n" x y
```

---

## Unsupported Events

The following winit events are not yet supported in winit-ocaml:

### Input Method Editor (IME)
- `Ime` - Text composition events
- Reason: Requires string handling in FFI

### Advanced Touch/Gestures
- `PinchGesture` - Two-finger pinch (macOS, iOS, Wayland)
- `PanGesture` - Multi-finger pan (iOS, Wayland)
- `RotationGesture` - Two-finger rotation (macOS, iOS, Wayland)
- `DoubleTapGesture` - Smart magnification (macOS, iOS)
- `TouchpadPressure` - Force touch (macOS)
- Reason: Platform-specific, complex data structures

### Drag & Drop
- `DragEntered` - File drag entered window
- `DragMoved` - File drag moved over window
- `DragDropped` - Files dropped on window
- `DragLeft` - File drag left window
- Reason: Requires file path list handling in FFI

### Advanced Window Events
- `ActivationTokenDone` - Activation token delivered (for window raising)
- Reason: Complex async token handling

---

## Best Practices

### Event Loop
Always call `pump_events` regularly (e.g., once per frame) to keep the window responsive:

```ocaml
while !running do
  let events = pump_events app in
  List.iter handle_event events;
  render ();
  Unix.sleepf 0.016  (* ~60 FPS *)
done
```

### Event Processing Order
Process events in the order received. winit guarantees certain event ordering:

1. Window state changes (focus, resize) before redraw
2. Modifier changes before key events
3. Pointer position updates before button events

### Coordinate Systems
- **Window coordinates:** Relative to top-left of window content area (excludes decorations)
- **Screen coordinates:** Absolute position on screen (used by `WindowMoved`)
- **Pixels:** All sizes and positions are in physical pixels

### DPI Handling
When `ScaleFactorChanged` occurs, you may need to:
1. Resize your rendering surface
2. Scale UI elements
3. Reload assets at appropriate resolution

### Key Codes vs. Logical Keys
The current implementation provides physical key codes (scancodes). These are:
- **Layout-independent:** WASD is always the same physical keys
- **Consistent:** Same keys across different keyboard layouts
- **Suitable for:** Game controls, keyboard shortcuts

For text input, future IME support will provide composed text.

### Modifier Tracking
The `ModifiersChanged` event provides detailed left/right modifier tracking. However, for simple cases, you may only care if any variant is pressed:

```ocaml
let is_shift_pressed = function
  | LeftPressed | RightPressed | BothPressed -> true
  | Unknown -> false

match event with
| ModifiersChanged { shift; _ } when is_shift_pressed shift ->
    (* Shift is pressed *)
```

---

## Platform Differences

### Linux (X11/Wayland)
- Full support for most events
- X11 provides more complete support than Wayland for some events

### macOS
- Touch events not exposed through PointerSource
- Gesture events available (not yet bound)

### Windows
- Shift key overrides NumLock behavior
- Some pointer events have limited position info

### Web
- CSS properties affect coordinate calculations
- Limited platform integration events

### Mobile (iOS/Android)
- Keyboard events limited
- Touch is primary input method
- Lifecycle events differ from desktop

---

## Migration from Old API

If you're upgrading from the previous simple event API:

**Old:**
```ocaml
match event.event_type with
| Resized ->
    let width = event.data1 in
    let height = event.data2 in
    ...
```

**New:**
```ocaml
match event with
| SurfaceResized { width; height } ->
    ...
```

**Old:**
```ocaml
match event.event_type with
| MouseButtonPressed ->
    let button = event.data1 in
    ...
```

**New:**
```ocaml
match event with
| PointerButtonPressed { button; x; y; primary } ->
    ...
```

The new API provides:
- Type safety through pattern matching
- Named fields for clarity
- Additional data (e.g., button position, pointer source)
- Future extensibility without API breaks
