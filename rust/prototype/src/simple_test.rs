// Simplest possible test of pump_events + softbuffer
// Key insight: keep window, context, and surface together to avoid borrow checker issues

use std::num::NonZeroU32;
use std::thread::sleep;
use std::time::Duration;

use raw_window_handle::{HasDisplayHandle, HasWindowHandle};
use winit::application::ApplicationHandler;
use winit::event::WindowEvent;
use winit::event_loop::pump_events::{EventLoopExtPumpEvents, PumpStatus};
use winit::event_loop::{ActiveEventLoop, EventLoop};
use winit::window::{Window, WindowAttributes, WindowId};

// Store everything together
struct State<D, W> {
    context: softbuffer::Context<D>,
    surface: softbuffer::Surface<D, W>,
}

struct App {
    window: Option<Box<dyn Window>>,
    frame_count: u32,
    // Store context and surface in a type-erased way to avoid complex type signatures
    context: Option<Box<dyn std::any::Any>>,
    surface: Option<Box<dyn std::any::Any>>,
}

impl App {
    fn new() -> Self {
        Self {
            window: None,
            context: None,
            surface: None,
            frame_count: 0,
        }
    }

    fn initialize_graphics(&mut self) -> Result<(), Box<dyn std::error::Error>> {
        let window = self.window.as_ref().ok_or("No window")?;

        let owned_display = window.display_handle()?.to_owned();
        let owned_window = window.window_handle()?.to_owned();

        let context = softbuffer::Context::new(owned_display)?;
        let mut surface = softbuffer::Surface::new(&context, owned_window)?;

        // Set initial size
        let size = window.surface_size();
        if let (Some(width), Some(height)) =
            (NonZeroU32::new(size.width), NonZeroU32::new(size.height))
        {
            surface.resize(width, height)?;
            println!("Surface initialized: {}x{}", width, height);
        }

        // Store in type-erased boxes
        self.surface = Some(Box::new(surface));
        self.context = Some(Box::new(context));
        Ok(())
    }

    fn draw_frame(&mut self) -> Result<(), Box<dyn std::error::Error>> {
        // Get surface with proper type
        let surface_any = self.surface.as_mut().ok_or("No surface")?;
        let surface: &mut softbuffer::Surface<_, _> = surface_any
            .downcast_mut()
            .ok_or("Wrong surface type")?;

        let mut buffer = surface.buffer_mut()?;
        let width = buffer.width().get() as usize;
        let height = buffer.height().get() as usize;

        // Draw a gradient that animates
        let offset = (self.frame_count % 256) as u32;
        for y in 0..height {
            for x in 0..width {
                let index = y * width + x;
                let red = ((x + offset as usize) % 256) as u32;
                let green = ((y + offset as usize) % 256) as u32;
                let blue = offset;
                buffer.pixels()[index] = blue | (green << 8) | (red << 16);
            }
        }

        buffer.present()?;
        self.frame_count += 1;

        Ok(())
    }

    fn resize_surface(&mut self, width: u32, height: u32) -> Result<(), Box<dyn std::error::Error>> {
        let surface_any = self.surface.as_mut().ok_or("No surface")?;
        let surface: &mut softbuffer::Surface<_, _> = surface_any
            .downcast_mut()
            .ok_or("Wrong surface type")?;

        if let (Some(w), Some(h)) = (NonZeroU32::new(width), NonZeroU32::new(height)) {
            surface.resize(w, h)?;
        }
        Ok(())
    }
}

impl ApplicationHandler for App {
    fn can_create_surfaces(&mut self, event_loop: &dyn ActiveEventLoop) {
        let window_attributes = WindowAttributes::default()
            .with_title("Simple Softbuffer Test")
            .with_surface_size(winit::dpi::LogicalSize::new(640, 480));

        match event_loop.create_window(window_attributes) {
            Ok(window) => {
                println!("Window created");
                self.window = Some(window);

                // Initialize graphics immediately
                if let Err(e) = self.initialize_graphics() {
                    eprintln!("Failed to initialize graphics: {}", e);
                }
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
        if let Some(window) = &self.window {
            if window_id != window.id() {
                return;
            }

            match event {
                WindowEvent::CloseRequested => {
                    println!("Close requested");
                    event_loop.exit();
                }
                WindowEvent::SurfaceResized(size) => {
                    println!("Resized to {}x{}", size.width, size.height);
                    if let Err(e) = self.resize_surface(size.width, size.height) {
                        eprintln!("Failed to resize surface: {:?}", e);
                    }
                }
                WindowEvent::RedrawRequested => {
                    // Event received, but we draw explicitly in main loop
                }
                WindowEvent::KeyboardInput { event, .. } => {
                    println!("Key: {:?}", event.logical_key);
                }
                _ => {}
            }
        }
    }
}

fn main() {
    tracing_subscriber::fmt::init();

    println!("=== Simple Pump Events + Softbuffer Test ===");
    println!("This demonstrates:");
    println!("  1. Using pump_events for explicit event loop control");
    println!("  2. Drawing outside of RedrawRequested callback");
    println!("  3. The pattern we'll use for OCaml integration\n");

    let mut event_loop = EventLoop::new().unwrap();
    let mut app = App::new();

    // Wait for window and graphics initialization
    loop {
        let status = event_loop.pump_app_events(Some(Duration::ZERO), &mut app);
        if let PumpStatus::Exit(_) = status {
            eprintln!("Event loop exited before initialization");
            return;
        }
        if app.surface.is_some() {
            break;
        }
        sleep(Duration::from_millis(10));
    }

    println!("\nInitialization complete, starting main loop\n");

    // Main loop - this is what OCaml will do
    loop {
        // 1. Pump events (non-blocking)
        let status = event_loop.pump_app_events(Some(Duration::ZERO), &mut app);

        if let PumpStatus::Exit(code) = status {
            println!("\nExiting with code {}", code);
            break;
        }

        // 2. Draw frame explicitly (not in a callback!)
        if let Err(e) = app.draw_frame() {
            eprintln!("Failed to draw frame: {}", e);
            break;
        }

        // 3. Request redraw for next frame
        if let Some(window) = &app.window {
            window.request_redraw();
        }

        // Print progress
        if app.frame_count % 60 == 0 {
            println!("Frame {}", app.frame_count);
        }

        // Limit frame rate
        sleep(Duration::from_millis(16)); // ~60 FPS

        // Auto-exit after 180 frames (~3 seconds)
        if app.frame_count >= 180 {
            println!("\nReached frame limit, exiting");
            break;
        }
    }

    println!("Drew {} total frames", app.frame_count);
}
