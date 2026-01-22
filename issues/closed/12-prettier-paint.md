# Prettier paint

In the paint demo, circles are drawn at the pen position, which looks fine
until the pen moves fast, and then it becomes obvious that the circles aren't
connected.

Make this change to the drawing logic:
- On the first pendown, keep drawing a circle
- On pen _moves_ draw a circle, but also draw a rhombus that connects the previous circle with the new circle.

take care to handle the case where the circle radii differ between frames.

feel free to use the union of both circle's bounding box for the dirty rect.

## Currently

The paint demo (`ocaml/examples/paint.ml`) currently:
- Draws circles at pen positions using `draw_stroke` function
- Tracks dirty regions for optimized rendering
- Supports pressure-sensitive brush size (2-20 pixels radius)
- Uses a canvas buffer that's blitted to the screen buffer

The gap problem occurs because when the pen moves quickly, circles are drawn at discrete positions
without interpolation, leaving visible gaps between them.

## Notes

To implement smooth stroke interpolation:

1. **Track previous position and radius**: Add fields to `paint_state` to store the last pen position
   and radius when drawing.

2. **Draw interpolating rhombus**: When pen moves (not first pen down), draw a filled quadrilateral
   connecting the previous circle to the current circle. The rhombus has four corners:
   - Two tangent points on the previous circle
   - Two tangent points on the current circle

3. **Handle different radii**: The rhombus becomes a trapezoid when radii differ. The perpendicular
   offsets from the line connecting centers should be scaled by each circle's radius.

4. **Damage rect**: Return the union of both circles' bounding boxes (easier than computing exact
   rhombus bounds).

## Addressing

Modified `ocaml/examples/paint.ml` with the following changes:

1. **Added stroke state tracking**: Added `last_x`, `last_y`, and `last_radius` optional fields to
   `paint_state` to track the previous pen position and brush radius.

2. **Implemented quadrilateral interpolation**: Created `draw_quad_to_canvas` function that draws
   a filled quadrilateral (rhombus/trapezoid) connecting two circles:
   - Calculates perpendicular vectors to the line connecting circle centers
   - Scales perpendiculars by each circle's radius to handle different sizes
   - Uses a point-in-quad test based on cross products for accurate filling
   - Returns damage rect covering the union of both circles' bounding boxes

3. **Updated stroke drawing logic**: Modified `draw_stroke` function to:
   - On first stroke (no previous position): draw circle and save position/radius
   - On subsequent strokes: draw connecting quad first, then circle at current position
   - Accumulates damage rects from both drawing operations

4. **Reset on pen lift**: Reset `last_x`, `last_y`, and `last_radius` to `None` when
   `PointerButtonReleased` event occurs, ensuring each new stroke starts fresh without
   connecting to the previous stroke.

The implementation properly handles varying brush sizes due to pressure changes, creating smooth
trapezoid connections between circles of different radii. The damage tracking system correctly
reports the union of both circles' bounding boxes for optimized rendering.
