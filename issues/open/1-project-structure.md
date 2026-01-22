# Project structure

Right now, there's a few issues with the current project structure:
1. things are scattered about:
   - the ocaml examples should live inside of the `./ocaml` directory
   - the rust `prototype` directory should live inside of `./rust`
   - the rust `vendor` directory should live inside of `./rust`
     (currently `vendor` doesn't build, don't worry about it for now)
2. rust should use a workspace at the project root so that it uses the vendored projects
