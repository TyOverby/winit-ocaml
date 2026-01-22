# Wacom tablet support

On linux/x11, wacom tablet inputs appear to be getting dropped.  Even when I added println debugging in the rust code for 
unhandled input events, nothing was showing up on pen hover, pen move, or pen down/up.  Look through the winit codebase to 
see if there's anything that we're doing wrong.
