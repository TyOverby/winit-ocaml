# Codegen Refactor

The OCaml library that generates the low level and high level libraries (`codegen`) has
grown in complexity and has become hard to maintain.  I'd like for you to read through the 
`codegen` library with a critical eye for code quality and write a report on the problems 
and proposed fixes.

Here are some goals that I have for this project:

- It's easy for a newcomer to reason about what part of the code generator is responsible
  for particular outputs
- It's easy for a newcomer to make changes and reason about their effect on the codebase
- The part of the code generator that hardcodes certain outputs should be obvious.  Maybe
  the hardcoded content should be in separate files which are read in by the generator?

And some early guidance:
- Splitting the project up into more files (or even libraries!) is fine - this
  project is big enough that the current file sizes are becoming a problem
- Right now there aren't any dedicated tests, and I think that Jane Street's expect test 
  setup could be useful here

Generate this report in `tasks/triage/code-quality/`.  Each individual
suggestion that you make should be in a separate markdown file, and it should
be tied together with guidance on ordering in a `tasks/triage/code-quality/report.md` 
file. For now don't comment on the quality of the _output_ of this program; for
the purposes of the code quality report, pretend that the output is fine
(though if you do find any bugs, file them under `tasks/triage`).
