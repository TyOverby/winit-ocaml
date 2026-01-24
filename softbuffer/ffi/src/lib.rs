//! Softbuffer FFI Library
//!
//! This library provides FFI bindings for softbuffer (rendering) to be used from OCaml.

use std::num::NonZeroU32;
use std::sync::Arc;

use winit::window::Window;
use winit_ffi::DamageRect;

/// Graphics state - holds softbuffer context and surface
struct GraphicsState {
    // Context must be kept alive for the surface to remain valid
    #[allow(dead_code)]
    context: softbuffer::Context<Arc<Box<dyn Window>>>,
    surface: softbuffer::Surface<Arc<Box<dyn Window>>, Arc<Box<dyn Window>>>,
    width: u32,
    height: u32,
}

impl GraphicsState {
    fn new(window: Arc<Box<dyn Window>>) -> Result<Self, softbuffer::SoftBufferError> {
        let context = softbuffer::Context::new(window.clone())?;
        let mut surface = softbuffer::Surface::new(&context, window.clone())?;

        let size = window.surface_size();
        let (width, height) = (size.width, size.height);

        if let (Some(w), Some(h)) = (NonZeroU32::new(width), NonZeroU32::new(height)) {
            surface.resize(w, h)?;
        }

        Ok(Self {
            context,
            surface,
            width,
            height,
        })
    }

    fn resize(&mut self, width: u32, height: u32) -> Result<(), softbuffer::SoftBufferError> {
        if let (Some(w), Some(h)) = (NonZeroU32::new(width), NonZeroU32::new(height)) {
            self.surface.resize(w, h)?;
            self.width = width;
            self.height = height;
        }
        Ok(())
    }
}

/// Softbuffer surface - owns the rendering surface and buffer
pub struct SoftbufferSurface {
    // Keep a reference to the window to ensure it lives long enough
    #[allow(dead_code)]
    window_ref: Arc<Box<dyn Window>>,
    graphics: GraphicsState,
    buffer: Option<softbuffer::Buffer<'static>>,
}

impl SoftbufferSurface {
    pub fn new(window: Arc<Box<dyn Window>>) -> Result<Self, Box<dyn std::error::Error>> {
        let graphics = GraphicsState::new(window.clone())?;

        Ok(Self {
            window_ref: window,
            graphics,
            buffer: None,
        })
    }

    pub fn resize(&mut self, width: u32, height: u32) -> Result<(), Box<dyn std::error::Error>> {
        self.graphics.resize(width, height)?;
        Ok(())
    }

    pub fn get_buffer(&mut self) -> (*mut u32, u32, u32) {
        // Get a mutable buffer
        match self.graphics.surface.buffer_mut() {
            Ok(mut buffer) => {
                let width = buffer.width().get();
                let height = buffer.height().get();
                let ptr = buffer.pixels().as_mut_ptr();

                // SAFETY: We're extending the lifetime of the buffer to 'static
                // This is unsafe but necessary for FFI. The caller must ensure
                // they don't use this pointer after calling present or after
                // the surface is destroyed.
                let buffer: softbuffer::Buffer<'static> = unsafe { std::mem::transmute(buffer) };
                self.buffer = Some(buffer);

                (ptr, width, height)
            }
            Err(e) => {
                eprintln!("Failed to get buffer: {:?}", e);
                (std::ptr::null_mut(), 0, 0)
            }
        }
    }

    pub fn get_buffer_age(&self) -> u8 {
        match &self.buffer {
            Some(buffer) => buffer.age(),
            None => 0,
        }
    }

    pub fn present(&mut self) -> i32 {
        // Take the buffer and present it
        if let Some(buffer) = self.buffer.take() {
            match buffer.present() {
                Ok(_) => {
                    // Request redraw for next frame
                    self.window_ref.request_redraw();
                    0
                }
                Err(e) => {
                    eprintln!("Failed to present: {:?}", e);
                    -1
                }
            }
        } else {
            -1
        }
    }

    pub fn present_with_damage(&mut self, damage_rects: &[DamageRect]) -> i32 {
        // Take the buffer and present it with damage regions
        if let Some(buffer) = self.buffer.take() {
            // Convert DamageRect to softbuffer::Rect
            let rects: Vec<softbuffer::Rect> = damage_rects
                .iter()
                .filter_map(|r| {
                    // softbuffer::Rect requires NonZeroU32 for width and height
                    match (NonZeroU32::new(r.width), NonZeroU32::new(r.height)) {
                        (Some(w), Some(h)) => Some(softbuffer::Rect {
                            x: r.x,
                            y: r.y,
                            width: w,
                            height: h,
                        }),
                        _ => None, // Skip invalid rects
                    }
                })
                .collect();

            match buffer.present_with_damage(&rects) {
                Ok(_) => {
                    // Request redraw for next frame
                    self.window_ref.request_redraw();
                    0
                }
                Err(e) => {
                    eprintln!("Failed to present with damage: {:?}", e);
                    -1
                }
            }
        } else {
            -1
        }
    }
}

// FFI functions

/// Create a softbuffer surface from a window handle
/// The handle should be obtained from winit_window_get_handle
/// This takes ownership of the handle (does not need to release it separately)
#[no_mangle]
pub extern "C" fn softbuffer_surface_create(
    window_handle: *const std::ffi::c_void,
) -> *mut SoftbufferSurface {
    if window_handle.is_null() {
        return std::ptr::null_mut();
    }

    // Reconstruct the Arc from the raw pointer
    // Note: winit_window_get_handle already incremented the ref count,
    // so we take ownership of that reference here
    let window_arc = unsafe { Arc::from_raw(window_handle as *const Box<dyn Window>) };

    match SoftbufferSurface::new(window_arc) {
        Ok(surface) => Box::into_raw(Box::new(surface)),
        Err(e) => {
            eprintln!("Failed to create softbuffer surface: {:?}", e);
            std::ptr::null_mut()
        }
    }
}

/// Resize the surface to match window size
#[no_mangle]
pub extern "C" fn softbuffer_surface_resize(
    surface: *mut SoftbufferSurface,
    width: u32,
    height: u32,
) -> i32 {
    if surface.is_null() {
        return -1;
    }

    let surface = unsafe { &mut *surface };
    match surface.resize(width, height) {
        Ok(_) => 0,
        Err(e) => {
            eprintln!("Failed to resize surface: {:?}", e);
            -1
        }
    }
}

/// Get the pixel buffer
#[no_mangle]
pub extern "C" fn softbuffer_surface_get_buffer(
    surface: *mut SoftbufferSurface,
    width_out: *mut u32,
    height_out: *mut u32,
) -> *mut u32 {
    if surface.is_null() || width_out.is_null() || height_out.is_null() {
        return std::ptr::null_mut();
    }

    let surface = unsafe { &mut *surface };
    let (ptr, width, height) = surface.get_buffer();

    unsafe {
        *width_out = width;
        *height_out = height;
    }

    ptr
}

/// Get the buffer age
#[no_mangle]
pub extern "C" fn softbuffer_surface_get_buffer_age(surface: *const SoftbufferSurface) -> i32 {
    if surface.is_null() {
        return -1;
    }

    let surface = unsafe { &*surface };
    surface.get_buffer_age() as i32
}

/// Present the buffer to the screen
#[no_mangle]
pub extern "C" fn softbuffer_surface_present(surface: *mut SoftbufferSurface) -> i32 {
    if surface.is_null() {
        return -1;
    }

    let surface = unsafe { &mut *surface };
    surface.present()
}

/// Present the buffer with damage regions
#[no_mangle]
pub extern "C" fn softbuffer_surface_present_with_damage(
    surface: *mut SoftbufferSurface,
    damage_rects: *const DamageRect,
    damage_count: usize,
) -> i32 {
    if surface.is_null() || damage_rects.is_null() {
        return -1;
    }

    let surface = unsafe { &mut *surface };
    let rects = unsafe { std::slice::from_raw_parts(damage_rects, damage_count) };

    surface.present_with_damage(rects)
}

/// Destroy the surface
#[no_mangle]
pub extern "C" fn softbuffer_surface_destroy(surface: *mut SoftbufferSurface) {
    if !surface.is_null() {
        unsafe {
            let _ = Box::from_raw(surface);
        }
    }
}
