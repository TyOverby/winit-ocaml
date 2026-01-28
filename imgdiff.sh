#!/bin/bash
set -euo pipefail

DIFF=$(compare "$1" "$2" null: 2>&1 | grep -oP '\(\K[0-9.]+' || true)
THRESHOLD=0.01

if (( $(echo "$DIFF > $THRESHOLD" | bc -l) )); then
    echo "FAIL: Images differ by $DIFF (threshold: $THRESHOLD):"
    echo "  $1"
    echo "  $2"
    echo ""
    exit 1
else
    exit 0
fi
