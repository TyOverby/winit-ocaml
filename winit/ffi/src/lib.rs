//! Winit FFI Library
//!
//! This library provides FFI bindings for winit (windowing) to be used from OCaml.

mod ffi;

// Re-export FFI types and functions
pub use ffi::*;

// ============================================================================
// Shared Types (also used by softbuffer_ffi)
// ============================================================================

/// C-compatible damage rectangle
#[repr(C)]
#[derive(Debug, Clone, Copy)]
pub struct DamageRect {
    pub x: u32,
    pub y: u32,
    pub width: u32,
    pub height: u32,
}

/// C-compatible event type
#[repr(C)]
#[derive(Debug, Clone, Copy)]
pub enum EventType {
    NoEvent = 0,
    CloseRequested = 1,
    SurfaceResized = 2,
    RedrawRequested = 3,
    KeyPressed = 4,
    KeyReleased = 5,
    PointerMoved = 6,
    PointerButtonPressed = 7,
    PointerButtonReleased = 8,
    PointerEntered = 9,
    PointerLeft = 10,
    MouseWheel = 11,
    Focused = 12,
    Unfocused = 13,
    WindowMoved = 14,
    ModifiersChanged = 15,
    Destroyed = 16,
    Occluded = 17,
    Unoccluded = 18,
    ThemeChanged = 19,
    ScaleFactorChanged = 20,
}

/// Event data structure with extended data buffer
/// Field usage is documented per-event-type below
#[repr(C)]
#[derive(Clone, Copy)]
pub struct Event {
    pub event_type: EventType,
    pub data: [i32; 16],
}

// Event field documentation:
//
// CloseRequested: (no data)
//
// SurfaceResized:
//   data[0]: width (u32 as i32)
//   data[1]: height (u32 as i32)
//
// RedrawRequested: (no data)
//
// KeyPressed/KeyReleased:
//   data[0]: physical_key_code (scancode)
//   data[1]: key_location (0=Standard, 1=Left, 2=Right, 3=Numpad)
//   data[2]: repeat (0=first press, 1=auto-repeat)
//
// ModifiersChanged:
//   data[0]: shift_key (0=up, 1=left down, 2=right down, 3=both down)
//   data[1]: control_key (same encoding)
//   data[2]: alt_key (same encoding)
//   data[3]: super_key (same encoding)
//
// PointerMoved:
//   data[0]: x position in pixels (f64 bits 0-31)
//   data[1]: x position in pixels (f64 bits 32-63)
//   data[2]: y position in pixels (f64 bits 0-31)
//   data[3]: y position in pixels (f64 bits 32-63)
//   data[4]: primary pointer (0=no, 1=yes)
//   data[5]: source (0=mouse, 1=touch, 2=tablet, 3=unknown)
//   --- For tablet source only (source=2): ---
//   data[6]: pressure (f32 bits as i32, 0.0-1.0 normalized)
//   data[7]: tilt_x (i8 degrees -90 to 90, encoded as i32)
//   data[8]: tilt_y (i8 degrees -90 to 90, encoded as i32)
//   data[9]: tablet tool kind (0=Pen, 1=Eraser, 2=Brush, 3=Pencil, 4=Airbrush, etc.)
//
// PointerEntered/PointerLeft:
//   data[0]: x position (f64 bits 0-31)
//   data[1]: x position (f64 bits 32-63)
//   data[2]: y position (f64 bits 0-31)
//   data[3]: y position (f64 bits 32-63)
//   data[4]: primary pointer (0=no, 1=yes)
//   data[5]: source (0=mouse, 1=touch, 2=tablet, 3=unknown)
//
// PointerButtonPressed/PointerButtonReleased:
//   data[0]: button id (1=Left, 2=Right, 3=Middle, 4=Back, 5=Forward, >5=Other)
//   data[1]: x position (f64 bits 0-31)
//   data[2]: x position (f64 bits 32-63)
//   data[3]: y position (f64 bits 0-31)
//   data[4]: y position (f64 bits 32-63)
//   data[5]: primary pointer (0=no, 1=yes)
//
// MouseWheel:
//   data[0]: delta type (0=line, 1=pixel)
//   data[1]: x delta (f32 bits as i32)
//   data[2]: y delta (f32 bits as i32)
//   data[3]: phase (0=Started, 1=Moved, 2=Ended, 3=Cancelled)
//
// Focused/Unfocused: (no data)
//
// WindowMoved:
//   data[0]: x position in screen coordinates (i32)
//   data[1]: y position in screen coordinates (i32)
//
// Destroyed: (no data)
//
// Occluded/Unoccluded: (no data)
//
// ThemeChanged:
//   data[0]: theme (0=Light, 1=Dark)
//
// ScaleFactorChanged:
//   data[0]: scale_factor (f64 bits 0-31)
//   data[1]: scale_factor (f64 bits 32-63)

impl Default for Event {
    fn default() -> Self {
        Event {
            event_type: EventType::NoEvent,
            data: [0; 16],
        }
    }
}

// ============================================================================
// Helper Functions
// ============================================================================

/// Helper function for encoding f64 into two i32s
pub fn encode_f64(value: f64) -> (i32, i32) {
    let bits = value.to_bits();
    let low = (bits & 0xFFFFFFFF) as i32;
    let high = ((bits >> 32) & 0xFFFFFFFF) as i32;
    (low, high)
}

/// Helper function for encoding f32 into i32
pub fn encode_f32(value: f32) -> i32 {
    value.to_bits() as i32
}

// ============================================================================
// Raw Window Handle Types (for wgpu surface creation)
// ============================================================================

/// Backend type for raw window handles
#[repr(C)]
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum RawHandleBackend {
    /// X11 (Xlib) backend
    X11 = 0,
    /// Wayland backend
    Wayland = 1,
    /// Win32 (Windows) backend
    Win32 = 2,
    /// AppKit (macOS) backend
    AppKit = 3,
    /// Unknown or unsupported backend
    Unknown = 255,
}

/// Raw window handle data for X11 (Xlib)
#[repr(C)]
#[derive(Debug, Clone, Copy)]
pub struct RawX11Handle {
    /// Pointer to X11 Display (void*)
    pub display: *const std::ffi::c_void,
    /// X11 Window ID (XID, usually u64)
    pub window: u64,
}

/// Raw window handle data for Wayland
#[repr(C)]
#[derive(Debug, Clone, Copy)]
pub struct RawWaylandHandle {
    /// Pointer to wl_display (void*)
    pub display: *const std::ffi::c_void,
    /// Pointer to wl_surface (void*)
    pub surface: *const std::ffi::c_void,
}

/// Raw window handle data for Win32
#[repr(C)]
#[derive(Debug, Clone, Copy)]
pub struct RawWin32Handle {
    /// HWND (window handle)
    pub hwnd: *const std::ffi::c_void,
    /// HINSTANCE (module instance)
    pub hinstance: *const std::ffi::c_void,
}

/// Raw window handle data for AppKit (macOS)
#[repr(C)]
#[derive(Debug, Clone, Copy)]
pub struct RawAppKitHandle {
    /// Pointer to NSView
    pub ns_view: *const std::ffi::c_void,
    /// Pointer to CAMetalLayer (created from the NSView)
    pub metal_layer: *const std::ffi::c_void,
}

/// Union of raw window handle data - use backend to determine which field is valid
#[repr(C)]
#[derive(Clone, Copy)]
pub union RawHandleData {
    pub x11: RawX11Handle,
    pub wayland: RawWaylandHandle,
    pub win32: RawWin32Handle,
    pub appkit: RawAppKitHandle,
}

/// Combined raw window handle with backend discriminant
#[repr(C)]
pub struct RawWindowHandleInfo {
    /// The backend type (determines which union field to use)
    pub backend: RawHandleBackend,
    /// The handle data (union, interpret based on backend)
    pub data: RawHandleData,
}

// ============================================================================
// Test Function
// ============================================================================

/// Test function for verifying FFI is working
#[no_mangle]
pub extern "C" fn winit_test_version() -> i32 {
    100 // Version 1.0.0
}
