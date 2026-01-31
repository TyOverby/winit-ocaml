#!/bin/bash
set -euo pipefail

PROFILE="$1"

# Determine dynamic library extension based on OS
case "$(uname)" in
  Darwin) DYLIB_EXT=dylib ;;
  *)      DYLIB_EXT=so ;;
esac

OUT_DIR=$(pwd)

# Navigate from _build/default/low to the real project root
# then into vendor/wgpu-native
SOURCE_ROOT=$(cd ../../.. && pwd)/vendor/wgpu-native

if [ "$PROFILE" = "release" ]; then
  cargo build --release --manifest-path $SOURCE_ROOT/Cargo.toml
  cp $SOURCE_ROOT/target/release/libwgpu_native.a $OUT_DIR/libwgpu_native.a
  if [ -f $SOURCE_ROOT/target/release/libwgpu_native.$DYLIB_EXT ]; then
    cp $SOURCE_ROOT/target/release/libwgpu_native.$DYLIB_EXT $OUT_DIR/dllwgpu_native.so
  else
    # Create empty placeholder if no dylib (static-only build)
    touch $OUT_DIR/dllwgpu_native.so
  fi
else
  cargo build --manifest-path $SOURCE_ROOT/Cargo.toml
  cp $SOURCE_ROOT/target/debug/libwgpu_native.a $OUT_DIR/libwgpu_native.a
  if [ -f $SOURCE_ROOT/target/debug/libwgpu_native.$DYLIB_EXT ]; then
    cp $SOURCE_ROOT/target/debug/libwgpu_native.$DYLIB_EXT $OUT_DIR/dllwgpu_native.so
  else
    touch $OUT_DIR/dllwgpu_native.so
  fi
fi
