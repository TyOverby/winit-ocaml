#!/bin/bash
set -euo pipefail

PROFILE="$1"

# Get absolute path to current directory (where the .so files are)
CURRENT_DIR=$(pwd)

if [ "$PROFILE" = "release" ]; then
  # Static linking - use -l: syntax to specify exact library filename
  echo "(-L$CURRENT_DIR -l:libsoftbuffer_ffi.a)" > link_mode_flags.sexp
else
  # Dynamic linking - use shared library with rpath for runtime lookup
  # Use -Wl,-Bdynamic to force dynamic linking for this library
  echo "(-Wl,-Bdynamic -L$CURRENT_DIR -lsoftbuffer_ffi -Wl,-rpath,$CURRENT_DIR)" > link_mode_flags.sexp
fi
