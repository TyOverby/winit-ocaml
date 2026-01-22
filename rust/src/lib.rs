use std::num::NonZeroU32;
use std::slice;
use std::sync::Arc;
use std::time::Duration;

use winit::application::ApplicationHandler;
use winit::event::{ButtonSource, MouseButton, WindowEvent};
use winit::event_loop::pump_events::{EventLoopExtPumpEvents, PumpStatus};
use winit::event_loop::{ActiveEventLoop, EventLoop};
use winit::window::{Window, WindowAttributes, WindowId};

// Simple C-compatible event type
#[repr(C)]
#[derive(Debug, Clone, Copy)]
pub enum EventType {
    NoEvent = 0,
    CloseRequested = 1,
    Resized = 2,
    RedrawRequested = 3,
    KeyPressed = 4,
    KeyReleased = 5,
    MouseMoved = 6,
    MouseButtonPressed = 7,
    MouseButtonReleased = 8,
}

// Event data structure
#[repr(C)]
#[derive(Clone, Copy)]
pub struct Event {
    pub event_type: EventType,
    pub data1: i32, // For width, x, key_code, etc.
    pub data2: i32, // For height, y, button, etc.
}

impl Default for Event {
    fn default() -> Self {
        Event {
            event_type: EventType::NoEvent,
            data1: 0,
            data2: 0,
        }
    }
}

// Event collector for winit
struct EventCollector {
    window: Option<Arc<Box<dyn Window>>>,
    events: Vec<Event>,
    should_exit: bool,
}

impl EventCollector {
    fn new() -> Self {
        Self {
            window: None,
            events: Vec::new(),
            should_exit: false,
        }
    }

    fn take_events(&mut self) -> Vec<Event> {
        std::mem::take(&mut self.events)
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
                    data1: 0,
                    data2: 0,
                });
                self.should_exit = true;
                event_loop.exit();
            }
            WindowEvent::SurfaceResized(size) => {
                self.events.push(Event {
                    event_type: EventType::Resized,
                    data1: size.width as i32,
                    data2: size.height as i32,
                });
            }
            WindowEvent::RedrawRequested => {
                self.events.push(Event {
                    event_type: EventType::RedrawRequested,
                    data1: 0,
                    data2: 0,
                });
            }
            WindowEvent::KeyboardInput { event, .. } => {
                let event_type = if event.state.is_pressed() {
                    EventType::KeyPressed
                } else {
                    EventType::KeyReleased
                };
                self.events.push(Event {
                    event_type,
                    data1: 0, // Could add key code here
                    data2: 0,
                });
            }
            WindowEvent::PointerMoved { position, .. } => {
                self.events.push(Event {
                    event_type: EventType::MouseMoved,
                    data1: position.x as i32,
                    data2: position.y as i32,
                });
            }
            WindowEvent::PointerButton { button, state, .. } => {
                let event_type = if state.is_pressed() {
                    EventType::MouseButtonPressed
                } else {
                    EventType::MouseButtonReleased
                };
                let button_id = match button {
                    ButtonSource::Mouse(MouseButton::Left) => 1,
                    ButtonSource::Mouse(MouseButton::Right) => 2,
                    ButtonSource::Mouse(MouseButton::Middle) => 3,
                    ButtonSource::Mouse(MouseButton::Back) => 4,
                    ButtonSource::Mouse(MouseButton::Forward) => 5,
                    _ => 0,
                };
                self.events.push(Event {
                    event_type,
                    data1: button_id,
                    data2: 0,
                });
            }
            other => {
                println!("{:?}", other)
            }
        }
    }
}

// Graphics state
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

// Main application structure
pub struct WinitOcamlApp {
    event_loop: Option<EventLoop>,
    collector: EventCollector,
    graphics: Option<GraphicsState>,
    buffer: Option<softbuffer::Buffer<'static>>,
}

impl WinitOcamlApp {
    fn new() -> Result<Self, Box<dyn std::error::Error>> {
        let event_loop = EventLoop::new()?;
        let collector = EventCollector::new();

        Ok(Self {
            event_loop: Some(event_loop),
            collector,
            graphics: None,
            buffer: None,
        })
    }

    fn initialize(&mut self) -> Result<(), Box<dyn std::error::Error>> {
        let event_loop = self.event_loop.as_mut().ok_or("Event loop already taken")?;

        // Pump events until window is created
        while self.collector.window.is_none() {
            let status = event_loop.pump_app_events(Some(Duration::ZERO), &mut self.collector);
            if let PumpStatus::Exit(_) = status {
                return Err("Event loop exited before window creation".into());
            }
            std::thread::sleep(Duration::from_millis(10));
        }

        // Create graphics state
        let window = self.collector.window.take().ok_or("Window not created")?;
        self.graphics = Some(GraphicsState::new(window.clone())?);
        self.collector.window = Some(window);

        Ok(())
    }

    fn pump_events(&mut self, events_out: &mut [Event]) -> i32 {
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

        // Handle resize events
        for event in &events[..count] {
            if let EventType::Resized = event.event_type {
                if let Some(graphics) = &mut self.graphics {
                    let _ = graphics.resize(event.data1 as u32, event.data2 as u32);
                }
            }
        }

        count as i32
    }

    fn get_buffer(&mut self) -> (*mut u32, u32, u32) {
        let graphics = match self.graphics.as_mut() {
            Some(g) => g,
            None => return (std::ptr::null_mut(), 0, 0),
        };

        // Get a mutable buffer
        match graphics.surface.buffer_mut() {
            Ok(mut buffer) => {
                let width = buffer.width().get();
                let height = buffer.height().get();
                let ptr = buffer.pixels().as_mut_ptr();

                // SAFETY: We're extending the lifetime of the buffer to 'static
                // This is unsafe but necessary for FFI. The caller must ensure
                // they don't use this pointer after calling present or after
                // the app is destroyed.
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

    fn present(&mut self) -> i32 {
        // Take the buffer and present it
        if let Some(buffer) = self.buffer.take() {
            match buffer.present() {
                Ok(_) => {
                    // Request redraw for next frame
                    if let Some(window) = &self.collector.window {
                        window.request_redraw();
                    }
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
}

// FFI functions
#[no_mangle]
pub extern "C" fn winit_create() -> *mut WinitOcamlApp {
    match WinitOcamlApp::new() {
        Ok(mut app) => match app.initialize() {
            Ok(_) => Box::into_raw(Box::new(app)),
            Err(e) => {
                eprintln!("Failed to initialize app: {:?}", e);
                std::ptr::null_mut()
            }
        },
        Err(e) => {
            eprintln!("Failed to create app: {:?}", e);
            std::ptr::null_mut()
        }
    }
}

#[no_mangle]
pub extern "C" fn winit_pump_events(
    app: *mut WinitOcamlApp,
    events_out: *mut Event,
    max_events: usize,
) -> i32 {
    if app.is_null() || events_out.is_null() {
        return -1;
    }

    let app = unsafe { &mut *app };
    let events_slice = unsafe { slice::from_raw_parts_mut(events_out, max_events) };

    app.pump_events(events_slice)
}

#[no_mangle]
pub extern "C" fn winit_get_buffer(
    app: *mut WinitOcamlApp,
    width_out: *mut u32,
    height_out: *mut u32,
) -> *mut u32 {
    if app.is_null() || width_out.is_null() || height_out.is_null() {
        return std::ptr::null_mut();
    }

    let app = unsafe { &mut *app };
    let (ptr, width, height) = app.get_buffer();

    unsafe {
        *width_out = width;
        *height_out = height;
    }

    ptr
}

#[no_mangle]
pub extern "C" fn winit_present(app: *mut WinitOcamlApp) -> i32 {
    if app.is_null() {
        return -1;
    }

    let app = unsafe { &mut *app };
    app.present()
}

#[no_mangle]
pub extern "C" fn winit_destroy(app: *mut WinitOcamlApp) {
    if !app.is_null() {
        unsafe {
            let _ = Box::from_raw(app);
        }
    }
}

// Test function
#[no_mangle]
pub extern "C" fn winit_test_version() -> i32 {
    100 // Version 1.0.0
}
