#!/bin/bash
set -euo pipefail
dune clean
cd rust
cargo clean
