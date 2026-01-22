// This prototype tests the key pattern for OCaml integration:
// 1. Pump events to get a list of events
// 2. Process events in user code
// 3. Draw explicitly when ready
// 4. Repeat
//
// This is different from the typical winit pattern where drawing
// happens inside the RedrawRequested callback.

use std::num::NonZeroU32;
use std::sync::Arc;
use std::thread::sleep;
use std::time::Duration;

use winit::application::ApplicationHandler;
use winit::event::WindowEvent;
use winit::event_loop::pump_events::{EventLoopExtPumpEvents, PumpStatus};
use winit::event_loop::{ActiveEventLoop, EventLoop};
use winit::window::{Window, WindowAttributes, WindowId};

// Simple event type that we'll collect
#[derive(Debug, Clone)]
enum SimpleEvent {
    CloseRequested,
    Resized { width: u32, height: u32 },
    RedrawRequested,
    KeyPressed,
    MouseMoved { x: f64, y: f64 },
}

struct EventCollector {
    window: Option<Arc<Box<dyn Window>>>,
    events: Vec<SimpleEvent>,
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

    fn take_events(&mut self) -> Vec<SimpleEvent> {
        std::mem::take(&mut self.events)
    }
}

impl ApplicationHandler for EventCollector {
    fn can_create_surfaces(&mut self, event_loop: &dyn ActiveEventLoop) {
        let window_attributes = WindowAttributes::default()
            .with_title("Manual Draw Test")
            .with_surface_size(winit::dpi::LogicalSize::new(640, 480));

        match event_loop.create_window(window_attributes) {
            Ok(window) => {
                println!("Window created");
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

        // Convert winit events to our simple event type
        match event {
            WindowEvent::CloseRequested => {
                self.events.push(SimpleEvent::CloseRequested);
                self.should_exit = true;
                event_loop.exit();
            }
            WindowEvent::SurfaceResized(size) => {
                self.events.push(SimpleEvent::Resized {
                    width: size.width,
                    height: size.height,
                });
            }
            WindowEvent::RedrawRequested => {
                self.events.push(SimpleEvent::RedrawRequested);
            }
            WindowEvent::KeyboardInput { .. } => {
                self.events.push(SimpleEvent::KeyPressed);
            }
            WindowEvent::PointerMoved { position, .. } => {
                self.events.push(SimpleEvent::MouseMoved {
                    x: position.x,
                    y: position.y,
                });
            }
            _ => {}
        }
    }
}

struct GraphicsState {
    // Context must be kept alive for the surface to remain valid
    #[allow(dead_code)]
    context: softbuffer::Context<Arc<Box<dyn Window>>>,
    surface: softbuffer::Surface<Arc<Box<dyn Window>>, Arc<Box<dyn Window>>>,
    color_offset: u32,
}

impl GraphicsState {
    fn new(window: Arc<Box<dyn Window>>) -> Result<Self, softbuffer::SoftBufferError> {
        let context = softbuffer::Context::new(window.clone())?;
        let mut surface = softbuffer::Surface::new(&context, window.clone())?;

        // Set initial size
        let size = window.surface_size();
        if let (Some(width), Some(height)) =
            (NonZeroU32::new(size.width), NonZeroU32::new(size.height))
        {
            surface.resize(width, height)?;
        }

        Ok(Self {
            context,
            surface,
            color_offset: 0,
        })
    }

    fn resize(&mut self, width: u32, height: u32) -> Result<(), softbuffer::SoftBufferError> {
        if let (Some(width), Some(height)) = (NonZeroU32::new(width), NonZeroU32::new(height)) {
            self.surface.resize(width, height)?;
        }
        Ok(())
    }

    fn draw(&mut self) -> Result<(), softbuffer::SoftBufferError> {
        let mut buffer = self.surface.buffer_mut()?;

        let width = buffer.width().get() as usize;
        let height = buffer.height().get() as usize;

        // Draw a gradient that changes over time
        for y in 0..height {
            for x in 0..width {
                let index = y * width + x;
                let red = ((x + self.color_offset as usize) % 256) as u32;
                let green = ((y + self.color_offset as usize / 2) % 256) as u32;
                let blue = ((self.color_offset as usize) % 256) as u32;
                buffer.pixels()[index] = blue | (green << 8) | (red << 16);
            }
        }

        buffer.present()?;

        self.color_offset = (self.color_offset + 1) % 256;
        Ok(())
    }
}

fn main() {
    tracing_subscriber::fmt::init();

    println!("=== Manual Draw Test ===");
    println!("This demonstrates the pattern we'll use for OCaml:");
    println!("  1. Pump events");
    println!("  2. Process events");
    println!("  3. Draw explicitly");
    println!("  4. Repeat");
    println!();

    let mut event_loop = EventLoop::new().unwrap();
    let mut collector = EventCollector::new();

    // Initialize - pump events until window is created
    loop {
        let status = event_loop.pump_app_events(Some(Duration::ZERO), &mut collector);
        if let PumpStatus::Exit(_) = status {
            eprintln!("Event loop exited before window creation");
            return;
        }
        if collector.window.is_some() {
            break;
        }
        sleep(Duration::from_millis(10));
    }

    // Now create graphics state
    let window = collector.window.take().unwrap();
    let mut graphics = match GraphicsState::new(window.clone()) {
        Ok(g) => g,
        Err(e) => {
            eprintln!("Failed to create graphics state: {:?}", e);
            return;
        }
    };
    collector.window = Some(window);

    println!("Window and graphics initialized\n");

    let mut frame = 0;
    let mut last_mouse_pos: Option<(f64, f64)> = None;

    // Main loop - this is what OCaml will do
    loop {
        // 1. Pump events (non-blocking)
        let status = event_loop.pump_app_events(Some(Duration::ZERO), &mut collector);

        if let PumpStatus::Exit(code) = status {
            println!("Exiting with code {}", code);
            break;
        }

        // 2. Process events (this is what OCaml user code will do)
        let events = collector.take_events();
        for event in events {
            match event {
                SimpleEvent::CloseRequested => {
                    println!("Frame {}: Close requested", frame);
                }
                SimpleEvent::Resized { width, height } => {
                    println!("Frame {}: Resized to {}x{}", frame, width, height);
                    if let Err(e) = graphics.resize(width, height) {
                        eprintln!("Failed to resize: {:?}", e);
                    }
                }
                SimpleEvent::RedrawRequested => {
                    println!("Frame {}: Redraw requested", frame);
                }
                SimpleEvent::KeyPressed => {
                    println!("Frame {}: Key pressed", frame);
                }
                SimpleEvent::MouseMoved { x, y } => {
                    // Only print if position changed significantly
                    if last_mouse_pos.map_or(true, |(lx, ly)| {
                        (x - lx).abs() > 10.0 || (y - ly).abs() > 10.0
                    }) {
                        println!("Frame {}: Mouse at ({:.0}, {:.0})", frame, x, y);
                        last_mouse_pos = Some((x, y));
                    }
                }
            }
        }

        // 3. Draw explicitly (outside of any callback)
        if let Err(e) = graphics.draw() {
            eprintln!("Frame {}: Failed to draw: {:?}", frame, e);
        }

        // Request redraw for next frame
        if let Some(window) = &collector.window {
            window.request_redraw();
        }

        frame += 1;

        // Limit to 60 FPS
        sleep(Duration::from_millis(16));

        // Exit after 180 frames (~3 seconds) if not closed by user
        if frame >= 180 && !collector.should_exit {
            println!("\nReached frame limit, exiting");
            break;
        }
    }

    println!("\nDrew {} frames total", frame);
}
