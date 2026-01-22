use std::num::NonZeroU32;
use std::rc::Rc;
use std::thread::sleep;
use std::time::Duration;

use winit::application::ApplicationHandler;
use winit::event::WindowEvent;
use winit::event_loop::pump_events::{EventLoopExtPumpEvents, PumpStatus};
use winit::event_loop::{ActiveEventLoop, EventLoop};
use winit::window::{Window, WindowAttributes, WindowId};

struct App {
    window: Option<Rc<dyn Window>>,
    context: Option<softbuffer::Context<Rc<dyn Window>>>,
    surface: Option<softbuffer::Surface<Rc<dyn Window>, Rc<dyn Window>>>,
    frame_count: u32,
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

    fn draw_frame(&mut self) {
        if let Some(surface) = &mut self.surface {
            // Get buffer and draw to it
            let mut buffer = match surface.buffer_mut() {
                Ok(b) => b,
                Err(e) => {
                    eprintln!("Failed to get buffer: {:?}", e);
                    return;
                }
            };

            let width = buffer.width().get() as usize;
            let height = buffer.height().get() as usize;

            // Draw a simple animated pattern
            let offset = (self.frame_count % 255) as u32;
            for y in 0..height {
                for x in 0..width {
                    let index = y * width + x;
                    let red = ((x + offset as usize) % 255) as u32;
                    let green = ((y + offset as usize) % 255) as u32;
                    let blue = (((x + y) + offset as usize) % 255) as u32;
                    buffer.pixels()[index] = blue | (green << 8) | (red << 16);
                }
            }

            // Present the buffer
            if let Err(e) = buffer.present() {
                eprintln!("Failed to present buffer: {:?}", e);
            }

            self.frame_count += 1;
        }
    }
}

impl ApplicationHandler for App {
    fn can_create_surfaces(&mut self, event_loop: &dyn ActiveEventLoop) {
        let window_attributes = WindowAttributes::default()
            .with_title("Pump Events Test")
            .with_surface_size(winit::dpi::LogicalSize::new(800, 600));

        match event_loop.create_window(window_attributes) {
            Ok(window) => {
                let window = Rc::new(window);
                println!("Window created successfully");

                // Create softbuffer context
                match softbuffer::Context::new(window.clone()) {
                    Ok(context) => {
                        println!("Context created successfully");

                        // Create surface
                        match softbuffer::Surface::new(&context, window.clone()) {
                            Ok(mut surface) => {
                                println!("Surface created successfully");

                                // Set initial size
                                let size = window.surface_size();
                                if let (Some(width), Some(height)) =
                                    (NonZeroU32::new(size.width), NonZeroU32::new(size.height))
                                {
                                    if let Err(e) = surface.resize(width, height) {
                                        eprintln!("Failed to resize surface: {:?}", e);
                                    } else {
                                        println!("Surface resized to {}x{}", width, height);
                                    }
                                }

                                self.surface = Some(surface);
                                self.context = Some(context);
                                self.window = Some(window);
                            }
                            Err(e) => eprintln!("Failed to create surface: {:?}", e),
                        }
                    }
                    Err(e) => eprintln!("Failed to create context: {:?}", e),
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
        let window = match self.window.as_ref() {
            Some(w) => w,
            None => return,
        };

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
                if let Some(surface) = &mut self.surface {
                    if let (Some(width), Some(height)) =
                        (NonZeroU32::new(size.width), NonZeroU32::new(size.height))
                    {
                        if let Err(e) = surface.resize(width, height) {
                            eprintln!("Failed to resize surface: {:?}", e);
                        }
                    }
                }
            }
            WindowEvent::RedrawRequested => {
                println!("Redraw requested (frame {})", self.frame_count);
            }
            WindowEvent::KeyboardInput { event, .. } => {
                println!("Keyboard input: {:?}", event);
            }
            _ => {}
        }
    }
}

fn main() {
    tracing_subscriber::fmt::init();

    println!("Starting pump events test");

    let mut event_loop = EventLoop::new().unwrap();
    let mut app = App::new();

    let mut should_draw = true;
    let mut last_draw_time = std::time::Instant::now();
    let target_frame_time = Duration::from_millis(16); // ~60 FPS

    loop {
        // Pump events with zero timeout (non-blocking)
        let timeout = Some(Duration::ZERO);
        let status = event_loop.pump_app_events(timeout, &mut app);

        if let PumpStatus::Exit(exit_code) = status {
            println!("Exiting with code {}", exit_code);
            break;
        }

        // Draw frame if enough time has passed
        let now = std::time::Instant::now();
        if should_draw && now.duration_since(last_draw_time) >= target_frame_time {
            // Request a redraw (this will trigger RedrawRequested event)
            if let Some(window) = &app.window {
                window.request_redraw();
            }

            // Draw the frame (outside of RedrawRequested callback!)
            app.draw_frame();

            last_draw_time = now;
        }

        // Sleep a bit to avoid busy-waiting
        sleep(Duration::from_millis(1));
    }

    println!("Drew {} frames total", app.frame_count);
}
