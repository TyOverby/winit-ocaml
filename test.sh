#!/bin/bash
set -euo pipefail

echo "Running test_ffi.exe"
dune exec examples/test_ffi.exe
echo "done!"

echo ""
echo "Running \`dune runtest\`"
dune runtest
echo "done!"
