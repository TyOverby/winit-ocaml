Your goal is to build an easy to use OCaml wrapper around the `softbuffer` rust crate.  For your convenience, I've vendored `softbuffer` and `winit` under `./vendor`, and have created an opam switch in the current directory.  To interact with opam, use the opam binary in the current directory: `./opam`.

The kind of OCaml API that I'd like to see is something like this:

```ocaml

module Event : sig 
  type t = | Variant_containing_all_the_winit_events_and_their_data
end

module Surface : sig 
  type t

  module Buffer : sig 
    type t 

    val age: t -> int
    val present: t -> unit
    val present_with_damage: t -> (* rectangle *) list -> unit
  end
end

module Window : sig 
  module Options : sig 
    type t
    val create: ?optional_params_here... () -> t
    val default : t
  end

  type t

  val create: ?options:Options.t -> t
  val width: t -> int
  val height: t -> int
  val events: t -> Event.t list
  val close: t -> unit
  val surface : t -> Surface.t
end 
```

There's a lot more functionality to be added to this API; this is just a sketch of what I think would be a nice start.  

This is going to be challenging for several reasons:
1. Writing typesafe and memory safe bindings between languages is hard
2. `winit` typically wants full control of the event loop, which won't play nicely with OCaml's event loop.  I think this can be worked around by pumping the events, as is done in `vendor/winit/examples/pump_events.rs`
3. The calls to `present` are going to happen outside of the `RedrawRequested` callback, which I think means that you're going to have to call `window.request_redraw()` to schedule them correctly.
4. Testing UI applications is hard!  I think you can use `Xvfb` and `import` to generate some screenshots that you can look at to see if things are working or not.

I'd like for you to explore the vendored libraries and come up with a plan for the implementation.  Write this plan down in a file and then get started!  I'd recommend prototyping something small in just Rust first to see if the APIs work as expected.  

Don't wait for me to chime in with input or guidance; this is your project and you should feel total ownership of its design and implementation feel free to modify the design as you see fit, but remember that the goal is to have a clean, fun, easy to use (and safe to use!) pixel-oriented library for OCaml users.
