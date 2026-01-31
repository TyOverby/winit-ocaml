#!/bin/bash
set -euo pipefail

case "$(uname)" in
  Darwin)
    echo '(-lpthread -framework CoreFoundation -framework CoreGraphics -framework AppKit -framework QuartzCore -framework CoreVideo -framework Metal -framework IOKit -framework IOSurface -framework Carbon -lobjc)' > c_library_flags.sexp
    ;;
  *)
    echo '(-lpthread -ldl -lm)' > c_library_flags.sexp
    ;;
esac
