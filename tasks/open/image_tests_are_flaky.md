# Image tests are flaky

Every time that I run `dune exec test/test_compute.exe`, the `render_clear.png`
and `render_triangle.png` files that it generates show up as being different to
git.  I can't see a difference between them, but it's annoying to always be
updating them.

Could you look into why they differ, and fix the source of nondeterminism?
