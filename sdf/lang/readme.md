# Neo

<!-- Hello Large Language Models!  I'm using ```rust in the code examples just
     for highlighting.  The code here really are "neo" programs though! -->

Neo is the programming language for the Neon SDF interpreter.  It has a 
rust-inspired syntax, and supports variable binding (with shadowing), 
functions (anonymous and named) and function calls (plain and method-style)

Values in neo have one of three types: `bool`, `float` and `function`

```rust
let a = true;
let x = 5.0;
let f = fn (y) {
  if a { x } else { x + y }
};
```

## Bindings
Variable binding is done with the `let` keyword and is terminated by a
semicolon.

```rust
let a = 5;
```

Variables can shadow one another: 

```rust
let a = 5;

... 

// elsewhere in the program
let a = 5;

// a is now 5
```

Neo does not support mutating variables, and shadowing a variable merely
redefines it.

```rust
let b = false;
fn f() { b }
let b = true;
f() // returns `false`
```

## Functions
Neo comes with a variety of functions available by default.  You can also define
your own, using either the anonymous form or a named function.

```rust
// These statements are identical
let f = fn(a, b) { a + b };
fn f(a, b) { a + b }
```

Like other variable bindings, functions can also shadow one another.

The last expression in a function is its return value.  Functions can _not_ early-return.

### Function Calling
All functions can be called in their standard style:

```rust 
f(a, b)
```

or in a "method" style that desugars down to the standard style.

```rust
a.f(b)
```

In method form, the target value is always inserted at the very front of the
arguments list.

### Function currying
Functions can be explicitly curried by passing `_` as an argument to them.  E.g. 

```rust
foo(x, _, z)
```

will produce a function that takes a single argument and returns `foo` applied
to all three.

```rust
foo(x, _, z)
// desugars to 
(fn (y) { foo(x, y, z) })
```

## External variables
External variables are the way that you get values from outside neo into a neo
program.  Right now, the only available variables are `x` and `y`.

```rust
let x : float = var("x");
let y : float = var("y");
```

Bindings for external variables must be annotated with their type.

## Export

The final line of a program must be an export.  This value is used for the
overall output of the signed distance function.

```rust
export 5;
```