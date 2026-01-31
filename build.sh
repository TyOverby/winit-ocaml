#!/bin/bash
set -euo pipefail
dune build
dune build ./examples/paint.exe
dune build ./examples/hello_triangle_wgpu.exe
