//! Winit FFI module - Window creation and event handling

use std::sync::Arc;
use std::time::Duration;

use raw_window_handle::{HasDisplayHandle, HasWindowHandle, RawWindowHandle, RawDisplayHandle};
use winit::application::ApplicationHandler;
use winit::event::{ButtonSource, MouseButton, MouseScrollDelta, TouchPhase, WindowEvent};
use winit::event_loop::pump_events::{EventLoopExtPumpEvents, PumpStatus};
use winit::event_loop::{ActiveEventLoop, EventLoop};
use winit::keyboard::{ModifiersKeyState, PhysicalKey};
use winit::window::{Theme, Window, WindowAttributes, WindowId};

use crate::{encode_f32, encode_f64, Event, EventType};

#[cfg(target_os = "linux")]
use crate::{RawHandleBackend, RawHandleData, RawWaylandHandle, RawWindowHandleInfo, RawX11Handle};

#[cfg(target_os = "windows")]
use crate::{RawHandleBackend, RawHandleData, RawWin32Handle, RawWindowHandleInfo};

#[cfg(target_os = "macos")]
use crate::{RawAppKitHandle, RawHandleBackend, RawHandleData, RawWindowHandleInfo, RawX11Handle};

#[cfg(not(any(target_os = "linux", target_os = "windows", target_os = "macos")))]
use crate::{RawHandleBackend, RawHandleData, RawWindowHandleInfo, RawX11Handle};

/// Event collector for winit - handles window events
pub struct EventCollector {
    pub(crate) window: Option<Arc<Box<dyn Window>>>,
    events: Vec<Event>,
    should_exit: bool,
}

impl EventCollector {
    pub fn new() -> Self {
        Self {
            window: None,
            events: Vec::new(),
            should_exit: false,
        }
    }

    pub fn take_events(&mut self) -> Vec<Event> {
        std::mem::take(&mut self.events)
    }
}

impl Default for EventCollector {
    fn default() -> Self {
        Self::new()
    }
}

impl ApplicationHandler for EventCollector {
    fn can_create_surfaces(&mut self, event_loop: &dyn ActiveEventLoop) {
        let window_attributes = WindowAttributes::default()
            .with_title("OCaml Window")
            .with_surface_size(winit::dpi::LogicalSize::new(800, 600));

        match event_loop.create_window(window_attributes) {
            Ok(window) => {
                self.window = Some(Arc::new(window));
            }
            Err(e) => eprintln!("Failed to create window: {:?}", e),
        }
    }

    fn window_event(
        &mut self,
        event_loop: &dyn ActiveEventLoop,
        window_id: WindowId,
        event: WindowEvent,
    ) {
        let window = match self.window.as_ref() {
            Some(w) => w,
            None => return,
        };

        if window_id != window.id() {
            return;
        }

        match event {
            WindowEvent::CloseRequested => {
                self.events.push(Event {
                    event_type: EventType::CloseRequested,
                    ..Default::default()
                });
                self.should_exit = true;
                event_loop.exit();
            }

            WindowEvent::SurfaceResized(size) => {
                let mut data = [0i32; 16];
                data[0] = size.width as i32;
                data[1] = size.height as i32;
                self.events.push(Event {
                    event_type: EventType::SurfaceResized,
                    data,
                });
            }

            WindowEvent::RedrawRequested => {
                self.events.push(Event {
                    event_type: EventType::RedrawRequested,
                    ..Default::default()
                });
            }

            WindowEvent::KeyboardInput {
                event: key_event, ..
            } => {
                let event_type = if key_event.state.is_pressed() {
                    EventType::KeyPressed
                } else {
                    EventType::KeyReleased
                };

                let mut data = [0i32; 16];

                // data[0]: physical key code (scancode)
                if let PhysicalKey::Code(code) = key_event.physical_key {
                    data[0] = code as i32;
                }

                // data[1]: key location
                data[1] = key_event.location as i32;

                // data[2]: repeat
                data[2] = if key_event.repeat { 1 } else { 0 };

                self.events.push(Event { event_type, data });
            }

            WindowEvent::ModifiersChanged(modifiers) => {
                let mut data = [0i32; 16];

                // Encode modifier states: 0=unknown, 1=left, 2=right, 3=both
                data[0] = match (modifiers.lshift_state(), modifiers.rshift_state()) {
                    (ModifiersKeyState::Unknown, ModifiersKeyState::Unknown) => 0,
                    (ModifiersKeyState::Pressed, ModifiersKeyState::Unknown) => 1,
                    (ModifiersKeyState::Unknown, ModifiersKeyState::Pressed) => 2,
                    (ModifiersKeyState::Pressed, ModifiersKeyState::Pressed) => 3,
                };

                data[1] = match (modifiers.lcontrol_state(), modifiers.rcontrol_state()) {
                    (ModifiersKeyState::Unknown, ModifiersKeyState::Unknown) => 0,
                    (ModifiersKeyState::Pressed, ModifiersKeyState::Unknown) => 1,
                    (ModifiersKeyState::Unknown, ModifiersKeyState::Pressed) => 2,
                    (ModifiersKeyState::Pressed, ModifiersKeyState::Pressed) => 3,
                };

                data[2] = match (modifiers.lalt_state(), modifiers.ralt_state()) {
                    (ModifiersKeyState::Unknown, ModifiersKeyState::Unknown) => 0,
                    (ModifiersKeyState::Pressed, ModifiersKeyState::Unknown) => 1,
                    (ModifiersKeyState::Unknown, ModifiersKeyState::Pressed) => 2,
                    (ModifiersKeyState::Pressed, ModifiersKeyState::Pressed) => 3,
                };

                data[3] = match (modifiers.lsuper_state(), modifiers.rsuper_state()) {
                    (ModifiersKeyState::Unknown, ModifiersKeyState::Unknown) => 0,
                    (ModifiersKeyState::Pressed, ModifiersKeyState::Unknown) => 1,
                    (ModifiersKeyState::Unknown, ModifiersKeyState::Pressed) => 2,
                    (ModifiersKeyState::Pressed, ModifiersKeyState::Pressed) => 3,
                };

                self.events.push(Event {
                    event_type: EventType::ModifiersChanged,
                    data,
                });
            }

            WindowEvent::PointerMoved {
                position,
                primary,
                source,
                ..
            } => {
                let mut data = [0i32; 16];
                let (x_low, x_high) = encode_f64(position.x);
                let (y_low, y_high) = encode_f64(position.y);
                data[0] = x_low;
                data[1] = x_high;
                data[2] = y_low;
                data[3] = y_high;
                data[4] = if primary { 1 } else { 0 };
                data[5] = match &source {
                    winit::event::PointerSource::Mouse => 0,
                    winit::event::PointerSource::Touch { .. } => 1,
                    winit::event::PointerSource::TabletTool { .. } => 2,
                    winit::event::PointerSource::Unknown => 3,
                };

                // Extract tablet-specific data if this is a tablet event
                if let winit::event::PointerSource::TabletTool {
                    kind,
                    data: tablet_data,
                } = source
                {
                    // Encode pressure (normalized 0.0-1.0)
                    if let Some(force) = tablet_data.force {
                        let pressure = match force {
                            winit::event::Force::Normalized(p) => p as f32,
                            winit::event::Force::Calibrated {
                                force,
                                max_possible_force,
                                ..
                            } => (force / max_possible_force) as f32,
                        };
                        data[6] = encode_f32(pressure);
                    }

                    // Encode tilt
                    if let Some(tilt) = tablet_data.tilt {
                        data[7] = tilt.x as i32;
                        data[8] = tilt.y as i32;
                    }

                    // Encode tool kind
                    data[9] = match kind {
                        winit::event::TabletToolKind::Pen => 0,
                        winit::event::TabletToolKind::Eraser => 1,
                        winit::event::TabletToolKind::Brush => 2,
                        winit::event::TabletToolKind::Pencil => 3,
                        winit::event::TabletToolKind::Airbrush => 4,
                        winit::event::TabletToolKind::Finger => 5,
                        winit::event::TabletToolKind::Mouse => 6,
                        winit::event::TabletToolKind::Lens => 7,
                        _ => 0, // Default to Pen for unknown tool kinds
                    };
                }

                self.events.push(Event {
                    event_type: EventType::PointerMoved,
                    data,
                });
            }

            WindowEvent::PointerEntered {
                position,
                primary,
                kind,
                ..
            } => {
                let mut data = [0i32; 16];
                let (x_low, x_high) = encode_f64(position.x);
                let (y_low, y_high) = encode_f64(position.y);
                data[0] = x_low;
                data[1] = x_high;
                data[2] = y_low;
                data[3] = y_high;
                data[4] = if primary { 1 } else { 0 };
                data[5] = match kind {
                    winit::event::PointerKind::Mouse => 0,
                    winit::event::PointerKind::Touch(_) => 1,
                    winit::event::PointerKind::TabletTool(_) => 2,
                    winit::event::PointerKind::Unknown => 3,
                };

                self.events.push(Event {
                    event_type: EventType::PointerEntered,
                    data,
                });
            }

            WindowEvent::PointerLeft {
                position,
                primary,
                kind,
                ..
            } => {
                let mut data = [0i32; 16];
                if let Some(pos) = position {
                    let (x_low, x_high) = encode_f64(pos.x);
                    let (y_low, y_high) = encode_f64(pos.y);
                    data[0] = x_low;
                    data[1] = x_high;
                    data[2] = y_low;
                    data[3] = y_high;
                }
                data[4] = if primary { 1 } else { 0 };
                data[5] = match kind {
                    winit::event::PointerKind::Mouse => 0,
                    winit::event::PointerKind::Touch(_) => 1,
                    winit::event::PointerKind::TabletTool(_) => 2,
                    winit::event::PointerKind::Unknown => 3,
                };

                self.events.push(Event {
                    event_type: EventType::PointerLeft,
                    data,
                });
            }

            WindowEvent::PointerButton {
                button,
                state,
                position,
                primary,
                ..
            } => {
                let event_type = if state.is_pressed() {
                    EventType::PointerButtonPressed
                } else {
                    EventType::PointerButtonReleased
                };

                let button_id = match button {
                    ButtonSource::Mouse(MouseButton::Left) => 1,
                    ButtonSource::Mouse(MouseButton::Right) => 2,
                    ButtonSource::Mouse(MouseButton::Middle) => 3,
                    ButtonSource::Mouse(MouseButton::Back) => 4,
                    ButtonSource::Mouse(MouseButton::Forward) => 5,
                    ButtonSource::Mouse(MouseButton::Button6) => 6,
                    ButtonSource::Mouse(MouseButton::Button7) => 7,
                    ButtonSource::Mouse(MouseButton::Button8) => 8,
                    _ => 0,
                };

                let mut data = [0i32; 16];
                data[0] = button_id;
                let (x_low, x_high) = encode_f64(position.x);
                let (y_low, y_high) = encode_f64(position.y);
                data[1] = x_low;
                data[2] = x_high;
                data[3] = y_low;
                data[4] = y_high;
                data[5] = if primary { 1 } else { 0 };

                self.events.push(Event { event_type, data });
            }

            WindowEvent::MouseWheel { delta, phase, .. } => {
                let mut data = [0i32; 16];

                match delta {
                    MouseScrollDelta::LineDelta(x, y) => {
                        data[0] = 0; // line delta
                        data[1] = encode_f32(x);
                        data[2] = encode_f32(y);
                    }
                    MouseScrollDelta::PixelDelta(pos) => {
                        data[0] = 1; // pixel delta
                        data[1] = encode_f32(pos.x as f32);
                        data[2] = encode_f32(pos.y as f32);
                    }
                }

                data[3] = match phase {
                    TouchPhase::Started => 0,
                    TouchPhase::Moved => 1,
                    TouchPhase::Ended => 2,
                    TouchPhase::Cancelled => 3,
                };

                self.events.push(Event {
                    event_type: EventType::MouseWheel,
                    data,
                });
            }

            WindowEvent::Focused(focused) => {
                self.events.push(Event {
                    event_type: if focused {
                        EventType::Focused
                    } else {
                        EventType::Unfocused
                    },
                    ..Default::default()
                });
            }

            WindowEvent::Moved(position) => {
                let mut data = [0i32; 16];
                data[0] = position.x;
                data[1] = position.y;
                self.events.push(Event {
                    event_type: EventType::WindowMoved,
                    data,
                });
            }

            WindowEvent::Destroyed => {
                self.events.push(Event {
                    event_type: EventType::Destroyed,
                    ..Default::default()
                });
            }

            WindowEvent::Occluded(occluded) => {
                self.events.push(Event {
                    event_type: if occluded {
                        EventType::Occluded
                    } else {
                        EventType::Unoccluded
                    },
                    ..Default::default()
                });
            }

            WindowEvent::ThemeChanged(theme) => {
                let mut data = [0i32; 16];
                data[0] = match theme {
                    Theme::Light => 0,
                    Theme::Dark => 1,
                };
                self.events.push(Event {
                    event_type: EventType::ThemeChanged,
                    data,
                });
            }

            WindowEvent::ScaleFactorChanged { scale_factor, .. } => {
                let mut data = [0i32; 16];
                let (low, high) = encode_f64(scale_factor);
                data[0] = low;
                data[1] = high;
                self.events.push(Event {
                    event_type: EventType::ScaleFactorChanged,
                    data,
                });
            }

            _other => {
                // Silently ignore unhandled events
            }
        }
    }
}

/// Window handle wrapper - owns the event loop and window
pub struct WinitWindow {
    event_loop: Option<EventLoop>,
    collector: EventCollector,
}

impl WinitWindow {
    pub fn new() -> Result<Self, Box<dyn std::error::Error>> {
        let event_loop = EventLoop::new()?;
        let collector = EventCollector::new();

        Ok(Self {
            event_loop: Some(event_loop),
            collector,
        })
    }

    pub fn initialize(&mut self) -> Result<(), Box<dyn std::error::Error>> {
        let event_loop = self.event_loop.as_mut().ok_or("Event loop already taken")?;

        // Pump events until window is created
        while self.collector.window.is_none() {
            let status = event_loop.pump_app_events(Some(Duration::ZERO), &mut self.collector);
            if let PumpStatus::Exit(_) = status {
                return Err("Event loop exited before window creation".into());
            }
            std::thread::sleep(Duration::from_millis(10));
        }

        Ok(())
    }

    pub fn pump_events(&mut self, events_out: &mut [Event]) -> i32 {
        let event_loop = match self.event_loop.as_mut() {
            Some(el) => el,
            None => return -1,
        };

        // Pump events
        let status = event_loop.pump_app_events(Some(Duration::ZERO), &mut self.collector);

        if let PumpStatus::Exit(_) = status {
            return -1;
        }

        // Get events and copy to output buffer
        let events = self.collector.take_events();
        let count = events.len().min(events_out.len());
        events_out[..count].copy_from_slice(&events[..count]);

        count as i32
    }

    /// Get the window handle - returns a cloned Arc
    pub fn get_window(&self) -> Option<Arc<Box<dyn Window>>> {
        self.collector.window.clone()
    }

    /// Request a redraw on the window
    pub fn request_redraw(&self) {
        if let Some(window) = &self.collector.window {
            window.request_redraw();
        }
    }
}

// FFI functions

#[no_mangle]
pub extern "C" fn winit_window_create() -> *mut WinitWindow {
    match WinitWindow::new() {
        Ok(mut window) => match window.initialize() {
            Ok(_) => Box::into_raw(Box::new(window)),
            Err(e) => {
                eprintln!("Failed to initialize window: {:?}", e);
                std::ptr::null_mut()
            }
        },
        Err(e) => {
            eprintln!("Failed to create window: {:?}", e);
            std::ptr::null_mut()
        }
    }
}

#[no_mangle]
pub extern "C" fn winit_window_pump_events(
    window: *mut WinitWindow,
    events_out: *mut Event,
    max_events: usize,
) -> i32 {
    if window.is_null() || events_out.is_null() {
        return -1;
    }

    let window = unsafe { &mut *window };
    let events_slice = unsafe { std::slice::from_raw_parts_mut(events_out, max_events) };

    window.pump_events(events_slice)
}

/// Get the raw window handle pointer for passing to softbuffer
/// This increments the Arc reference count - caller must call winit_window_handle_release
#[no_mangle]
pub extern "C" fn winit_window_get_handle(window: *const WinitWindow) -> *const std::ffi::c_void {
    if window.is_null() {
        return std::ptr::null();
    }

    let window = unsafe { &*window };
    match window.get_window() {
        Some(arc) => {
            // Convert Arc to raw pointer, incrementing ref count
            let ptr = Arc::into_raw(arc);
            ptr as *const std::ffi::c_void
        }
        None => std::ptr::null(),
    }
}

/// Clone a window handle (increment ref count)
#[no_mangle]
pub extern "C" fn winit_window_handle_clone(
    handle: *const std::ffi::c_void,
) -> *const std::ffi::c_void {
    if handle.is_null() {
        return std::ptr::null();
    }

    unsafe {
        let arc = Arc::from_raw(handle as *const Box<dyn Window>);
        let cloned = Arc::clone(&arc);
        // Don't drop the original
        std::mem::forget(arc);
        Arc::into_raw(cloned) as *const std::ffi::c_void
    }
}

/// Release a window handle (decrement ref count)
#[no_mangle]
pub extern "C" fn winit_window_handle_release(handle: *const std::ffi::c_void) {
    if !handle.is_null() {
        unsafe {
            // This drops the Arc, decrementing the ref count
            let _ = Arc::from_raw(handle as *const Box<dyn Window>);
        }
    }
}

#[no_mangle]
pub extern "C" fn winit_window_destroy(window: *mut WinitWindow) {
    if !window.is_null() {
        unsafe {
            let _ = Box::from_raw(window);
        }
    }
}

/// Request a redraw on the window
#[no_mangle]
pub extern "C" fn winit_window_request_redraw(window: *const WinitWindow) {
    if !window.is_null() {
        let window = unsafe { &*window };
        window.request_redraw();
    }
}

/// Create a CAMetalLayer for an NSView and set it as the view's layer
/// Returns the layer pointer for use with wgpu
#[cfg(target_os = "macos")]
fn create_metal_layer_for_view(ns_view_ptr: *const std::ffi::c_void) -> *const std::ffi::c_void {
    use cocoa::base::{id, YES};
    use objc::runtime::Class;
    use objc::{msg_send, sel, sel_impl};

    unsafe {
        let ns_view = ns_view_ptr as id;

        // Create a new CAMetalLayer
        let ca_metal_layer_class = Class::get("CAMetalLayer").expect("CAMetalLayer class not found");
        let layer: id = msg_send![ca_metal_layer_class, layer];

        // Enable layer backing on the view
        let _: () = msg_send![ns_view, setWantsLayer: YES];

        // Set the metal layer as the view's layer
        let _: () = msg_send![ns_view, setLayer: layer];

        // Return the layer pointer
        layer as *const std::ffi::c_void
    }
}

/// Get the raw window handle information for creating wgpu surfaces
/// Returns a RawWindowHandleInfo struct with backend type and handle data
/// Writes the result to the provided output pointer
/// Returns 0 on success, -1 on failure
#[no_mangle]
pub extern "C" fn winit_window_get_raw_handle(
    window: *const WinitWindow,
    out: *mut RawWindowHandleInfo,
) -> i32 {
    if window.is_null() || out.is_null() {
        return -1;
    }

    let window_ref = unsafe { &*window };
    let window_arc = match window_ref.get_window() {
        Some(w) => w,
        None => return -1,
    };

    // Get raw window handle
    let raw_window_handle = match window_arc.window_handle() {
        Ok(handle) => handle.as_raw(),
        Err(_) => return -1,
    };

    // Get raw display handle
    let raw_display_handle = match window_arc.display_handle() {
        Ok(handle) => handle.as_raw(),
        Err(_) => return -1,
    };

    let result = match (raw_window_handle, raw_display_handle) {
        #[cfg(target_os = "linux")]
        (RawWindowHandle::Xlib(xlib_window), RawDisplayHandle::Xlib(xlib_display)) => {
            RawWindowHandleInfo {
                backend: RawHandleBackend::X11,
                data: RawHandleData {
                    x11: RawX11Handle {
                        display: xlib_display
                            .display
                            .map_or(std::ptr::null(), |d| d.as_ptr() as *const std::ffi::c_void),
                        window: xlib_window.window,
                    },
                },
            }
        }

        #[cfg(target_os = "linux")]
        (RawWindowHandle::Wayland(wayland_surface), RawDisplayHandle::Wayland(wayland_display)) => {
            RawWindowHandleInfo {
                backend: RawHandleBackend::Wayland,
                data: RawHandleData {
                    wayland: RawWaylandHandle {
                        display: wayland_display.display.as_ptr() as *const std::ffi::c_void,
                        surface: wayland_surface.surface.as_ptr() as *const std::ffi::c_void,
                    },
                },
            }
        }

        #[cfg(target_os = "windows")]
        (RawWindowHandle::Win32(win32_handle), _) => RawWindowHandleInfo {
            backend: RawHandleBackend::Win32,
            data: RawHandleData {
                win32: RawWin32Handle {
                    hwnd: win32_handle.hwnd.get() as *const std::ffi::c_void,
                    hinstance: win32_handle
                        .hinstance
                        .map_or(std::ptr::null(), |h| h.get() as *const std::ffi::c_void),
                },
            },
        },

        #[cfg(target_os = "macos")]
        (RawWindowHandle::AppKit(appkit_handle), _) => {
            let ns_view_ptr = appkit_handle.ns_view.as_ptr() as *const std::ffi::c_void;
            let metal_layer = create_metal_layer_for_view(ns_view_ptr);
            RawWindowHandleInfo {
                backend: RawHandleBackend::AppKit,
                data: RawHandleData {
                    appkit: RawAppKitHandle {
                        ns_view: ns_view_ptr,
                        metal_layer,
                    },
                },
            }
        }

        _ => RawWindowHandleInfo {
            backend: RawHandleBackend::Unknown,
            data: RawHandleData {
                x11: RawX11Handle {
                    display: std::ptr::null(),
                    window: 0,
                },
            },
        },
    };

    unsafe {
        *out = result;
    }

    0
}
