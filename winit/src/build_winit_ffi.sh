#!/bin/bash
set -euo pipefail

PROFILE="$1"

# Determine dynamic library extension based on OS
case "$(uname)" in
  Darwin) DYLIB_EXT=dylib ;;
  *)      DYLIB_EXT=so ;;
esac

OUT_DIR=$(pwd)

# Find the actual source root by going up from _build/default/winit/src
# We're in _build/default/winit/src, need to go to project root then back out of _build
SOURCE_ROOT=$(cd ../../../.. && pwd)

if [ "$PROFILE" = "release" ]; then
  cargo build --release -p winit_ffi --manifest-path $SOURCE_ROOT/Cargo.toml
  cp $SOURCE_ROOT/_build/rust/release/libwinit_ffi.a $OUT_DIR/libwinit_ffi.a
  cp $SOURCE_ROOT/_build/rust/release/libwinit_ffi.$DYLIB_EXT $OUT_DIR/dllwinit_ffi.so
else
  cargo build -p winit_ffi --manifest-path $SOURCE_ROOT/Cargo.toml
  cp $SOURCE_ROOT/_build/rust/debug/libwinit_ffi.a $OUT_DIR/libwinit_ffi.a
  cp $SOURCE_ROOT/_build/rust/debug/libwinit_ffi.$DYLIB_EXT $OUT_DIR/dllwinit_ffi.so
fi
