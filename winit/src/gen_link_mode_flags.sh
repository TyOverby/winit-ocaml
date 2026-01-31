#!/bin/bash
set -euo pipefail

PROFILE="$1"

# Get absolute path to current directory (where the .so/.dylib files are)
CURRENT_DIR=$(pwd)

# Detect platform
case "$(uname -s)" in
  Darwin)
    # macOS
    if [ "$PROFILE" = "release" ]; then
      # Static linking - reference the .a file directly (quoted for dune sexp)
      echo "(\"$CURRENT_DIR/libwinit_ffi.a\")" > link_mode_flags.sexp
    else
      # Dynamic linking - macOS uses .dylib and different rpath syntax
      echo "(-L$CURRENT_DIR -lwinit_ffi -Wl,-rpath,$CURRENT_DIR)" > link_mode_flags.sexp
    fi
    ;;
  *)
    # Linux and others
    if [ "$PROFILE" = "release" ]; then
      # Static linking - use -l: syntax to specify exact library filename
      echo "(-L$CURRENT_DIR -l:libwinit_ffi.a)" > link_mode_flags.sexp
    else
      # Dynamic linking - use shared library with rpath for runtime lookup
      # Use -Wl,-Bdynamic to force dynamic linking for this library
      echo "(-Wl,-Bdynamic -L$CURRENT_DIR -lwinit_ffi -Wl,-rpath,$CURRENT_DIR)" > link_mode_flags.sexp
    fi
    ;;
esac
