#!/bin/bash
# 在室監視してディスプレイを自動制御するスクリプト
# 不在が一定時間続くとディスプレイをオフ、在室になるとオンにする

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/config.sh"

# ディスプレイをオフにするまでの時間（秒）
DISPLAY_OFF_THRESHOLD=30

# チェック間隔（秒）
CHECK_INTERVAL=1

# 状態変数
ABSENT_COUNT=0
IS_DISPLAY_OFF=false

echo "ディスプレイ制御デーモンを開始します"
echo "不在閾値: ${DISPLAY_OFF_THRESHOLD}秒, チェック間隔: ${CHECK_INTERVAL}秒"

# 在室監視ループ
while true; do
    # 距離を取得
    DISTANCE=$(head -n 1 "$DEVICE" 2>/dev/null)

    # デバイス接続エラー
    if [ -z "$DISTANCE" ]; then
        echo "警告: デバイスからの読み取りに失敗しました"
        sleep "$CHECK_INTERVAL"
        continue
    fi

    # 整数に丸めて空白を削除
    DISTANCE_INT=${DISTANCE%.*}
    DISTANCE_INT=$(echo "$DISTANCE_INT" | tr -d '[:space:]')

    # 在室判定
    if [ "$DISTANCE_INT" -le "$THRESHOLD_CM" ]; then
        # 在室
        if [ "$IS_DISPLAY_OFF" = true ]; then
            echo "在室を検知: ディスプレイをオンにします"
            # ディスプレイをオンにする（短い時間スリープを解除する）
            caffeinate -u -t 1 &
            IS_DISPLAY_OFF=false
        fi
        ABSENT_COUNT=0
    else
        # 不在
        ABSENT_COUNT=$((ABSENT_COUNT + CHECK_INTERVAL))

        if [ "$IS_DISPLAY_OFF" = false ] && [ "$ABSENT_COUNT" -ge "$DISPLAY_OFF_THRESHOLD" ]; then
            echo "不在${ABSENT_COUNT}秒: ディスプレイをオフにします"
            # ディスプレイをオフにする
            pmset displaysleepnow
            IS_DISPLAY_OFF=true
        fi
    fi

    sleep "$CHECK_INTERVAL"
done
