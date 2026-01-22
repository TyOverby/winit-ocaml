# Wacom tablet support

On linux/x11, wacom tablet inputs appear to be getting dropped.  Even when I added println debugging in the rust code for
unhandled input events, nothing was showing up on pen hover, pen move, or pen down/up.  Look through the winit codebase to
see if there's anything that we're doing wrong.

## links
- [commit that added tablet support to winit](https://github.com/rust-windowing/winit/commit/f046e778aa0d2621fdedf03eab53e88120317192#diff-f7d292f3547150aa761570c5bd5407ebfbeece35f03c4420d4de9e8bc3bf26f9)

## Currently

The current codebase (as of January 2026) already has some tablet event handling in rust/src/lib.rs:

1. **PointerMoved** events (line 279) detect `PointerSource::TabletTool` and encode it as source type 2
2. **PointerEntered** events (line 306) detect `PointerKind::TabletTool` and encode it as kind 2
3. **PointerLeft** events (line 333) detect `PointerKind::TabletTool` and encode it as kind 2
4. **PointerButton** events should also work for tablet pen buttons

The code appears to be set up to receive and handle tablet events, but the issue reports that no events are coming through at all.

The vendored winit is located at `rust/vendor/winit/` and we're using it via path dependency in Cargo.toml.

## Notes

After investigating the winit X11 backend, I found several key points:

### Event Registration
In `winit-x11/src/window.rs:819-828`, the XIEventMask registered for windows includes:
- MOTION
- BUTTON_PRESS / BUTTON_RELEASE
- ENTER / LEAVE
- FOCUS_IN / FOCUS_OUT
- TOUCH_BEGIN / TOUCH_UPDATE / TOUCH_END

According to [x11rb XIEventMask documentation](https://docs.rs/x11rb/0.6.0/x11rb/protocol/xinput/enum.XIEventMask.html), there are no tablet-specific event masks. X11 XInput2 treats tablets, mice, and touch devices uniformly as pointer devices. Tablets should generate the same MOTION and BUTTON events as mice.

### Event Source Detection
In `winit-x11/src/event_processor.rs`, all PointerMoved events are hardcoded to `PointerSource::Mouse` or `PointerSource::Touch`. The code does NOT query device properties to determine if the source is a tablet. This is the core issue.

For tablets to work properly, the event processor needs to:
1. Query the device properties when receiving XI_Motion/XI_ButtonPress events
2. Determine if the device is a tablet tool (pen, eraser, etc.)
3. Extract tablet-specific valuator data (pressure, tilt, twist, etc.)
4. Create events with `PointerSource::TabletTool` instead of `PointerSource::Mouse`

### Root Cause Found!

After digging through the code, I found the exact problem:

**Device Detection Works:** In `winit-x11/src/event_loop.rs:1053-1067`, devices are correctly classified as `DeviceType::Pen` or `DeviceType::Eraser` based on their valuators (ABS_PRESSURE, ABS_TILT_X, ABS_TILT_Y).

**Events Are Filtered Out:** In `winit-x11/src/event_processor.rs`:
- `xinput2_mouse_motion` (line 1064-1071) only processes `DeviceType::Mouse` and returns early for all other types
- `xinput2_button_input` (line 979-986) has the same filter

This means tablet events ARE being received by X11, but winit's event processor is silently dropping them!

### References
- [Wacom X Events Overview](https://developer-docs.wacom.com/docs/icbt/linux/x-events/x-events-overview/)
- [XISelectEvents Manual](https://www.x.org/archive/X11R7.5/doc/man/man3/XISelectEvents.3.html)
- [x11rb XIEventMask](https://docs.rs/x11rb/0.6.0/x11rb/protocol/xinput/enum.XIEventMask.html)

## Addressing

I've implemented tablet support by modifying the vendored winit X11 backend. Here's what was done:

### Changes to winit (vendored fork)

**Branch:** fix/x11-tablet-event-support
**Commit:** 6416ea11

1. **Extended Device struct** (`winit-x11/src/event_loop.rs`)
   - Added `tablet_axes: Option<TabletAxes>` field to track valuator indices
   - Created `TabletAxes` struct to store which valuator index corresponds to pressure, tilt_x, and tilt_y

2. **Updated device initialization** (`winit-x11/src/event_loop.rs`)
   - Modified `Device::new()` to record tablet axis indices during device enumeration
   - Properly populates `tablet_axes` for Pen and Eraser devices

3. **Modified event processor** (`winit-x11/src/event_processor.rs`)
   - Added `extract_tablet_data()` helper to extract pressure and tilt from XI event valuators
   - Modified `xinput2_mouse_motion()` to handle Pen and Eraser devices in addition to Mouse
   - Modified `xinput2_button_input()` to handle Pen and Eraser devices
   - Tablet events now generate `PointerSource::TabletTool` with proper `TabletToolData`
   - Added PartialEq derive to DeviceType for device type comparisons

### How it works

Previously, tablet devices were correctly detected (as DeviceType::Pen or DeviceType::Eraser), but the event handlers only processed DeviceType::Mouse events, causing all tablet events to be silently dropped.

Now:
1. When a tablet device is detected, we record which valuator index corresponds to pressure and tilt axes
2. When motion or button events arrive from a tablet, we extract the valuator data
3. We construct TabletToolData with pressure (as Force) and tilt (as TabletToolTilt)
4. We emit PointerMoved events with PointerSource::TabletTool instead of PointerSource::Mouse

The OCaml bindings already support tablet events (they check for source type 2 = tablet in the existing code), so they should work immediately once winit provides the correct events.
