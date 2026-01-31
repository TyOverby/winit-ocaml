#!/bin/bash
set -euo pipefail

DIFF=$(compare "$1" "$2" null: 2>&1 | grep -oP '\(\K[0-9.]+([eE][+-]?[0-9]+)?' || true)
THRESHOLD=0.01

if awk "BEGIN {exit !($DIFF > $THRESHOLD)}"; then
    echo "FAIL: Images differ by $DIFF (threshold: $THRESHOLD):"
    echo "  $1"
    echo "  $2"
    echo ""
    exit 1
else
    exit 0
fi
