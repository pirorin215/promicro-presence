#!/bin/bash
# 在室判定して通知を送るスクリプト
# 在室時は通知しない、不在時のみ通知を送る

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/config.sh"

# 距離を取得
DISTANCE=$(head -n 1 "$DEVICE" 2>/dev/null)

# 距離が取得できなかった場合は通知する（安全側）
if [ -z "$DISTANCE" ]; then
    curl -s -d "$NOTIFY_MESSAGE" "$NOTIFY_URL"
    exit 0
fi

# 整数に丸めて比較
DISTANCE_INT=${DISTANCE%.*}

# 在室判定（閾値以下なら在室とみなす）
if [ "$DISTANCE_INT" -le "$THRESHOLD_CM" ]; then
    # 在室: 通知しない
    exit 0
else
    # 不在: 通知を送る
    curl -s -d "$NOTIFY_MESSAGE" "$NOTIFY_URL"
    exit 0
fi
