# Codegen Code Quality Report

## Executive Summary

The codegen library has grown organically to ~4700 lines across 5 files. While
functional, it has accumulated complexity that makes it difficult to maintain,
extend, and onboard new contributors. The main issues are:

1. **Large monolithic files** - gen_high.ml (2295 lines) and gen_low.ml (1882 lines)
2. **Hardcoded templates mixed with generation logic**
3. **Duplicated code between ML and MLI generation**
4. **No automated tests**
5. **Complex function signatures with opaque return types**

This report contains 10 specific issues with proposed fixes. They are ordered by
recommended implementation priority, balancing value and effort.

## No output changes!
It is very important to note that these are all code organization changes, and
at no point should there ever be a change to generated code!  Minor whitespace 
diffs are acceptable, but the generator should more or less behave identically
to before!

## File Overview

| File | Lines | Purpose |
|------|-------|---------|
| gen_high.ml | 2295 | High-level OCaml API generation |
| gen_low.ml | 1882 | Low-level bindings + C stubs generation |
| parse_yml.ml | 301 | YAML parsing to IR |
| ir.ml | 163 | Intermediate representation types |
| gen_bindings.ml | 69 | CLI entry point |

## Issues by Priority

1. [Add Expect Tests](./04-add-expect-tests.md)
2. [Extract Configuration](./06-configuration-extraction.md)
3. [Externalize Hardcoded Templates](./01-hardcoded-templates.md)
4. [Improve Naming](./07-improve-naming.md)
5. [Simplify Complex Return Types](./05-complex-return-types.md)
6. [Create Type Mapping Layer](./08-type-mapping-abstraction.md)
7. [Reduce ML/MLI Duplication](./03-duplicated-logic.md)
8. [Split Large Files](./02-split-large-files.md)
9. [No more printf](./09-no-more-printf.md)
10. [Separate Concerns in Method Generation](./10-separate-concerns-in-method-gen.md)

## Metrics for Success

After refactoring, the codebase should meet these criteria:

1. **No file > 500 lines** (excluding templates)
2. **Test coverage for all utility functions**
3. **Each file has a single, clear purpose**
4. **ML/MLI are generated from shared code**
5. **Hardcoded content is in separate template files**
6. **New contributors can find relevant code within 5 minutes**

## Non-Goals

This report focuses on code quality, not functionality. The following are
explicitly out of scope:

- Changing what the generator outputs
- Adding new features to the generated bindings
- Modifying the IR representation
- Changing the YAML parsing

## Conclusion

The codegen library is functional but has grown to the point where maintenance is
becoming difficult. By addressing the issues in this report incrementally, starting
with tests and quick wins, we can improve the codebase without risking the working
functionality.

The recommended first step is adding expect tests for utility functions, which
provides a safety net for all subsequent refactoring.
