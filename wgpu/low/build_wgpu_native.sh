#!/bin/bash
set -euo pipefail

PROFILE="$1"

# Determine dynamic library extension based on OS
case "$(uname)" in
  Darwin) DYLIB_EXT=dylib ;;
  *)      DYLIB_EXT=so ;;
esac

OUT_DIR=$(pwd)

# Navigate from _build/default/wgpu/low to the real project root
PROJECT_ROOT=$(cd ../../../.. && pwd)

if [ "$PROFILE" = "release" ]; then
  cargo build --quiet --release -p combined_ffi --manifest-path $PROJECT_ROOT/Cargo.toml
  cp $PROJECT_ROOT/_build/rust/release/libcombined_ffi.a $OUT_DIR/libwgpu_native.a
  # Placeholder .so files (not used in release mode)
  touch $OUT_DIR/dllwgpu_native.so
  touch $OUT_DIR/libwgpu_native.so
else
  cargo build --quiet -p wgpu-native --manifest-path $PROJECT_ROOT/Cargo.toml
  cp $PROJECT_ROOT/_build/rust/debug/libwgpu_native.a $OUT_DIR/libwgpu_native.a
  if [ -f $PROJECT_ROOT/_build/rust/debug/libwgpu_native.$DYLIB_EXT ]; then
    cp $PROJECT_ROOT/_build/rust/debug/libwgpu_native.$DYLIB_EXT $OUT_DIR/dllwgpu_native.so
    # Also copy with lib prefix for native dynamic linking
    cp $PROJECT_ROOT/_build/rust/debug/libwgpu_native.$DYLIB_EXT $OUT_DIR/libwgpu_native.so
  else
    touch $OUT_DIR/dllwgpu_native.so
    touch $OUT_DIR/libwgpu_native.so
  fi
fi
