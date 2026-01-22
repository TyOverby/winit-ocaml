# Prettier paint

In the paint demo, circles are drawn at the pen position, which looks fine
until the pen moves fast, and then it becomes obvious that the circles aren't
connected.  

Make this change to the drawing logic: 
- On the first pendown, keep drawing a circle
- On pen _moves_ draw a circle, but also draw a rhombus that connects the previous circle with the new circle.

take care to handle the case where the circle radii differ between frames.
 
feel free to use the union of both circle's bounding box for the dirty rect.
