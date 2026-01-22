# Dune knows about cargo

Right now, the build steps involve manually building the rust project, cleaning the ocaml project, and then rebuilding the 
ocaml project.  This is unfortunate, and I think we could make it so that `dune` rebuilds the rust stuff any time that 
rust code changes.
