# Project organization

Right now the project is organized by language first and then library:

```
ocaml/
  image_buf/
  softbuffer/
  winit/
  examples/
rust/
  src/
  vendor/
  prototype/
```

I'd like for you to make two big changes:
1. split the rust crate into two crates `softbuffer_ffi` and `winit_ffi`
3. reorganize the repo to be "library major", like so:

```
softbuffer/
  ffi/ # Rust code
  src/ # Ocaml code
winit/
  ffi/ # Rust code
  src/ # Ocaml code
vendor/
image_buf/
examples/
  # existing examples here
  prototype/
```

This will probably necessitate a more involved "cargo workspace" strategy.

Use `git mv` whenever possible.
