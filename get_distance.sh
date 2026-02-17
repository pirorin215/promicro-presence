#!/bin/bash
# Pro Micro + HC-SR04 から距離を取得するシェルスクリプト

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/config.sh"

# 距離を1回だけ取得
head -n 1 "$DEVICE"
