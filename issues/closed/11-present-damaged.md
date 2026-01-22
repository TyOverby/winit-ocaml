# `present_with_damage`

In addition to `present`, `softbuffer` provides a `present_with_damage`
function, that allows you to specify which regions of the image need to be
re-displayed.

It also exposes an `age` function that can be used to see how old the
currently-displayed surface is. (read the docs for this one)

implement and expose these functions, and then take advantage of it in the `paint` demo
by only blitting the parts of the image that are necessary, and then reporting them via
`present_with_damage`.

## Currently

The project currently has a `present()` function that presents the entire buffer to screen.
Looking at the code:

- Rust layer (`rust/src/lib.rs`): Has `winit_present()` FFI function that calls `buffer.present()`
- C stubs layer (`ocaml/winit_stubs.c`): Has `caml_winit_present()` wrapper
- OCaml layer (`ocaml/winit_softbuffer.ml`): Has `present()` API function

The paint example (`ocaml/examples/paint.ml`) currently blits the entire canvas buffer to the
screen buffer every frame (line 149), even though only a small region changes when drawing strokes.

## Notes

From examining softbuffer's source (`rust/vendor/softbuffer/src/lib.rs`):

1. **`Buffer::age() -> u8`** (line 263): Returns the number of frames ago this buffer was last
   presented. If the value is 0, it's a new buffer with unspecified contents. If it's 1, it's
   the same as the last frame. This is used for backends with buffer rotation (double/triple
   buffering).

2. **`Buffer::present_with_damage(damage: &[Rect]) -> Result<(), SoftBufferError>`** (line 294):
   Presents the buffer but only updates the specified damaged regions. The `Rect` type has:
   - `x: u32` - x coordinate of top left corner
   - `y: u32` - y coordinate of top left corner
   - `width: NonZeroU32` - width
   - `height: NonZeroU32` - height

   Platform support:
   - Supported on Wayland, X11 (when XShm is available), Win32, Web
   - On unsupported platforms, falls back to full present

The paint app optimization strategy:
1. Track dirty regions when drawing (the bounding box of each stroke)
2. Check buffer age - if 0, redraw everything; if >0, only redraw dirty regions
3. Only blit the dirty regions from canvas to screen buffer
4. Present with the accumulated damage rects

## Addressing

Implemented the feature in three layers:

1. **Rust layer** (`rust/src/lib.rs`):
   - Added `DamageRect` C-compatible struct
   - Added `get_buffer_age()` method to WinitOcamlApp
   - Added `present_with_damage(damage_rects)` method to WinitOcamlApp
   - Added FFI functions: `winit_get_buffer_age()` and `winit_present_with_damage()`

2. **C stubs layer** (`ocaml/winit_stubs.c`):
   - Added `DamageRect` C struct
   - Added `caml_winit_get_buffer_age()` wrapper
   - Added `caml_winit_present_with_damage()` wrapper that converts OCaml tuples to C structs

3. **OCaml layer** (`ocaml/winit_softbuffer.ml{i}`):
   - Added `damage_rect` record type
   - Added `get_buffer_age : app -> int` function
   - Added `present_with_damage : app -> damage_rect array -> unit` function

Now updating the paint example to use these new features for optimization.

Updated the paint example (`ocaml/examples/paint.ml`) to demonstrate damage tracking:
- Modified `paint_state` to track `dirty_regions` list
- Updated `draw_circle_to_canvas` to return damage rect (bounding box of drawn circle)
- Added `blit_damaged_regions` to blit only changed regions
- Modified `draw_stroke` to append damage rects to dirty list
- Updated `clear_canvas` to mark entire canvas as dirty
- Modified main loop to:
  1. Check buffer age with `get_buffer_age()`
  2. If age=0 or no dirty regions, blit everything
  3. Otherwise, only blit dirty regions
  4. Use `present_with_damage` with accumulated damage rects
  5. Clear dirty regions after presenting

The optimization significantly reduces CPU usage when only small regions change per frame.

All code builds without warnings. Documentation updated in `developer.md` with new section
about Damage Tracking and Optimized Presentation.

