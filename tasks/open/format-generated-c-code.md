# Format generated C code

The generated ocaml code is passed through ocamlformat, but the generated C code is currently not formatted at all. 
Use `clang-format` to format the generated C code inside the dune rule that produces it.
