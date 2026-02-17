#!/bin/bash
# 継続監視モード

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/config.sh"

echo "監視開始（$DEVICE）、Ctrl+Cで終了"
cat "$DEVICE"
