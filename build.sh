#!/bin/bash
set -euo pipefail
dune build
dune build ./examples/paint.exe
