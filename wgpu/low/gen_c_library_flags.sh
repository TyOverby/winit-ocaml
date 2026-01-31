#!/bin/bash
set -euo pipefail

case "$(uname)" in
  Darwin)
    echo '(-framework Foundation -framework CoreFoundation -framework CoreGraphics -framework Metal -framework IOKit -framework QuartzCore -framework IOSurface -lobjc)' > c_library_flags.sexp
    ;;
  *)
    echo '(-lpthread -ldl -lm)' > c_library_flags.sexp
    ;;
esac
