#!/bin/bash
set -euo pipefail

case "$(uname)" in
  Darwin)
    echo '(-framework CoreFoundation -framework CoreGraphics -framework AppKit -framework QuartzCore -framework CoreVideo -framework Metal -framework IOKit -framework IOSurface -framework Carbon)' > c_library_flags.sexp
    ;;
  *)
    echo '(-lpthread -ldl -lm)' > c_library_flags.sexp
    ;;
esac
