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
# then into vendor/wgpu-native
SOURCE_ROOT=$(cd ../../../.. && pwd)/vendor/wgpu-native

# The project root (where .cargo/config.toml lives)
PROJECT_ROOT=$(cd ../../../.. && pwd)

if [ "$PROFILE" = "release" ]; then
  cargo build --quiet --release --manifest-path $SOURCE_ROOT/Cargo.toml
  cp $PROJECT_ROOT/_build/rust/release/libwgpu_native.a $OUT_DIR/libwgpu_native.a
  if [ -f $PROJECT_ROOT/_build/rust/release/libwgpu_native.$DYLIB_EXT ]; then
    cp $PROJECT_ROOT/_build/rust/release/libwgpu_native.$DYLIB_EXT $OUT_DIR/dllwgpu_native.so
  else
    # Create empty placeholder if no dylib (static-only build)
    touch $OUT_DIR/dllwgpu_native.so
  fi
else
  cargo build --quiet --manifest-path $SOURCE_ROOT/Cargo.toml
  cp $PROJECT_ROOT/_build/rust/debug/libwgpu_native.a $OUT_DIR/libwgpu_native.a
  if [ -f $PROJECT_ROOT/_build/rust/debug/libwgpu_native.$DYLIB_EXT ]; then
    cp $PROJECT_ROOT/_build/rust/debug/libwgpu_native.$DYLIB_EXT $OUT_DIR/dllwgpu_native.so
  else
    touch $OUT_DIR/dllwgpu_native.so
  fi
fi
