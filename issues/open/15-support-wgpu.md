# Support wgpu

I just vendored the `wgpu-ocaml` project into `vendor/wgpu-ocaml`.  This
project adds high level bindings to the `wgpu-native` library.

The bindings work, and they've demonstrated their use by rendering out to image
files on disk, but so far we don't have a way to display anything on screen.

Your task is to connect our `winit` bindings with `wgpu-ocaml` and get a wgpu 
"hello triangle" to draw to the screen.  This will likely involve getting a raw
surface handle from winit to pass to `wgpu-ocaml`.  If the `wgpu-ocaml`
bindings aren't sufficient to implement this, please extend them.
