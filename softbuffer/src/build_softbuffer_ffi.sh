#!/bin/bash
set -euo pipefail

PROFILE="$1"

# Determine dynamic library extension based on OS
case "$(uname)" in
  Darwin) DYLIB_EXT=dylib ;;
  *)      DYLIB_EXT=so ;;
esac

OUT_DIR=$(pwd)

# Find the actual source root by going up from _build/default/softbuffer/src
SOURCE_ROOT=$(cd ../../../.. && pwd)

if [ "$PROFILE" = "release" ]; then
  cargo build --release -p softbuffer_ffi --manifest-path $SOURCE_ROOT/Cargo.toml
  cp $SOURCE_ROOT/_build/rust/release/libsoftbuffer_ffi.a $OUT_DIR/libsoftbuffer_ffi.a
  cp $SOURCE_ROOT/_build/rust/release/libsoftbuffer_ffi.$DYLIB_EXT $OUT_DIR/dllsoftbuffer_ffi.so
else
  cargo build -p softbuffer_ffi --manifest-path $SOURCE_ROOT/Cargo.toml
  cp $SOURCE_ROOT/_build/rust/debug/libsoftbuffer_ffi.a $OUT_DIR/libsoftbuffer_ffi.a
  cp $SOURCE_ROOT/_build/rust/debug/libsoftbuffer_ffi.$DYLIB_EXT $OUT_DIR/dllsoftbuffer_ffi.so
fi
