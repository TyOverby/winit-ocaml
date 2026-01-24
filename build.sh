#!/bin/bash
set -euo pipefail
dune build
dune build ./ocaml/examples/paint.exe
