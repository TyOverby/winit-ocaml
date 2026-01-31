#!/bin/bash
set -euo pipefail

DIFF=$(compare "$1" "$2" null: 2>&1 | sed -n 's/.*(\([0-9.eE+-]*\)).*/\1/p' || true)
THRESHOLD=0.01

# Handle empty DIFF (treat as 0)
if [ -z "$DIFF" ]; then
    DIFF=0
fi

if awk "BEGIN {exit !($DIFF > $THRESHOLD)}"; then
    echo "FAIL: Images differ by $DIFF (threshold: $THRESHOLD):"
    echo "  $1"
    echo "  $2"
    echo ""
    exit 1
else
    exit 0
fi
