#!/bin/bash
# <swiftbar.runInTerminal>false</swiftbar.runInTerminal>
# <swiftbar.debugLog>false</swiftbar.debugLog>
# <swiftbar.hideAbout>true</swiftbar.hideAbout>
# <swiftbar.hideRunInTerminal>true</swiftbar.hideRunInTerminal>
# <swiftbar.hideLastUpdated>false</swiftbar.hideLastUpdated>
# <swiftbar.image>system:name=person.fill</swiftbar.image>

. ~/Documents/Arduino/promicro-presence/config.sh

# Arduinoに閾値を送信（起動時のみ）
if [ -n "$THRESHOLD_CM" ]; then
    printf 'T%d\n' "$THRESHOLD_CM" > "$DEVICE" 2>/dev/null
fi

# 設定ファイルディレクトリ
CONFIG_DIR=~/Documents/Arduino/promicro-presence
# 状態ファイル（不在カウント、ディスプレイOFF状態、前回の距離）
STATE_FILE="$CONFIG_DIR/.presence_display_state"

# 設定ファイルに保存（ディスプレイ制御設定のみ）
save_config() {
    # config.shのディスプレイ制御設定部分を更新
    sed -i '' "s/^DISPLAY_OFF_SECONDS=.*/DISPLAY_OFF_SECONDS=$DISPLAY_OFF_SECONDS/" "$CONFIG_DIR/config.sh"
    sed -i '' "s/^DEBUG_MODE=.*/DEBUG_MODE=$DEBUG_MODE/" "$CONFIG_DIR/config.sh"
    sed -i '' "s/^PAUSED=.*/PAUSED=$PAUSED/" "$CONFIG_DIR/config.sh"
}

# ディスプレイをONにする（ArduinoにF20キー送信コマンド）
display_on() {
    # caffeinate -u -t 1  # 元の方法（macOSコマンド）
    printf 'W\n' > "$DEVICE" 2>/dev/null
    IS_DISPLAY_OFF=false
}

# ディスプレイをOFFにする
display_off() {
    pmset displaysleepnow
    IS_DISPLAY_OFF=true
}

# 状態ファイルから読み込み
load_state() {
    if [ -f "$STATE_FILE" ]; then
        source "$STATE_FILE"
    else
        ABSENT_COUNT=0
        IS_DISPLAY_OFF=false
        PREV_DISTANCE_INT=999
    fi
}

# 状態ファイルに保存
save_state() {
    cat > "$STATE_FILE" <<EOF
ABSENT_COUNT=$ABSENT_COUNT
IS_DISPLAY_OFF=$IS_DISPLAY_OFF
PREV_DISTANCE_INT=$PREV_DISTANCE_INT
EOF
}

# 設定の更新関数
update_config() {
    load_config
    save_config
}

# メニューアクション処理
ACTION="$1"

# トグルアクション
case "$ACTION" in
    --toggle-pause)
        load_config
        if [ "$PAUSED" = true ]; then
            PAUSED=false
        else
            PAUSED=true
        fi
        save_config
        exit 0
        ;;
    --set-threshold-*)
        # パラメータから値を抽出 (例: --set-threshold-150)
        new_threshold="${ACTION#--set-threshold-}"

        # config.shを書き換え
        sed -i '' "s/^THRESHOLD_CM=.*/THRESHOLD_CM=$new_threshold/" ~/Documents/Arduino/promicro-presence/config.sh

        # Arduinoに送信
        printf 'T%d\n' "$new_threshold" > "$DEVICE" 2>/dev/null
        exit 0
        ;;
    --set-display-off-*)
        # パラメータから秒数を抽出 (例: --set-display-off-30)
        display_off_seconds="${ACTION#--set-display-off-}"

        if [ "$display_off_seconds" = "0" ]; then
            # 0の場合はディスプレイ自動制御をOFF
            DISPLAY_CONTROL_ENABLED=false
            DISPLAY_OFF_SECONDS=0
        else
            # 秒数を設定
            DISPLAY_OFF_SECONDS=$display_off_seconds
            # ディスプレイ自動制御をON
            DISPLAY_CONTROL_ENABLED=true
            # 状態初期化
            ABSENT_COUNT=0
            IS_DISPLAY_OFF=false
            save_state
        fi
        save_config
        exit 0
        ;;
    --toggle-debug-mode)
        load_config
        if [ "$DEBUG_MODE" = true ]; then
            DEBUG_MODE=false
        else
            DEBUG_MODE=true
        fi
        save_config
        exit 0
        ;;
esac

# 一時停止中なら距離取得をスキップ
load_config
if [ "$PAUSED" = true ]; then
    echo "⏸️ 一時停止中 | color=yellow"
    IS_PAUSED=true
else
    # 距離を取得
    DISTANCE=$(head -n 1 "$DEVICE" 2>/dev/null)

    # デバイス接続エラー
    if [ -z "$DISTANCE" ]; then
        echo "⚠️  No Device | color=red"
        echo "---"
        echo "Device: $DEVICE"
        echo "Refresh | refresh=true"
        exit 0
    fi

    # 整数に丸めて空白を削除
    DISTANCE_INT=${DISTANCE%.*}
    DISTANCE_INT=$(echo "$DISTANCE_INT" | tr -d '[:space:]')

    # 状態を読み込み
    load_state

    # ディスプレイ制御が有効な場合の処理
    if [ "$DISPLAY_OFF_SECONDS" -gt 0 ]; then
        # 距離の変化量を計算
        DISTANCE_DIFF=$((DISTANCE_INT - PREV_DISTANCE_INT))
        DISTANCE_DIFF=${DISTANCE_DIFF#-}  # 絶対値

        # 在室判定
        if [ "$DISTANCE_INT" -le "$THRESHOLD_CM" ]; then
            # 在室：10cm以上の変動がある場合、またはディスプレイがOFF状態の場合
            if [ "$DISTANCE_DIFF" -ge 10 ] || [ "$IS_DISPLAY_OFF" = true ]; then
                display_on
            fi
            ABSENT_COUNT=0
        else
            # 不在
            ABSENT_COUNT=$((ABSENT_COUNT + 1))

            # 秒数を回数に変換（3秒間隔なので ÷3、切り上げ）
            DISPLAY_OFF_THRESHOLD=$(( (DISPLAY_OFF_SECONDS + 2) / 3 ))

            if [ "$IS_DISPLAY_OFF" = false ] && [ "$ABSENT_COUNT" -ge "$DISPLAY_OFF_THRESHOLD" ]; then
                display_off
            fi
        fi

        # 前回の距離を更新して保存
        PREV_DISTANCE_INT=$DISTANCE_INT
        save_state
    fi

    # 在室判定（表示用）
    if [ "$DISTANCE_INT" -le "$THRESHOLD_CM" ]; then
        # 在室
        if [ "$DEBUG_MODE" = true ]; then
            echo "🟢 ${DISTANCE_INT}cm (A:${ABSENT_COUNT})"
        else
            echo "🟢 ${DISTANCE_INT}cm"
        fi
        echo "---"
        echo "Status: 在室"
    else
        # 不在
        if [ "$DEBUG_MODE" = true ]; then
            echo "🟠 ${DISTANCE_INT}cm (A:${ABSENT_COUNT}) | color=orange"
        else
            echo "🟠 ${DISTANCE_INT}cm | color=orange"
        fi
        echo "---"
        echo "Status: 不在"
    fi
fi

# Device表示（共通）
echo "---"
echo "Device: $DEVICE"

# 一時停止の状態表示
if [ "$PAUSED" = true ]; then
    echo "---"
    echo "⏸️ 一時停止: ON | color=yellow"
else
    echo "---"
    echo "⏸️ 一時停止: OFF"
fi
echo "--一時停止を切り替え | bash=$0 param1=--toggle-pause terminal=false refresh=true"

# 距離しきい値変更メニュー
echo "---"
echo "📏 距離しきい値: ${THRESHOLD_CM}cm"
echo "--10cm | bash=$0 param1=--set-threshold-10 terminal=false refresh=true"
echo "--50cm | bash=$0 param1=--set-threshold-50 terminal=false refresh=true"
echo "--150cm | bash=$0 param1=--set-threshold-150 terminal=false refresh=true"
echo "--200cm | bash=$0 param1=--set-threshold-200 terminal=false refresh=true"

# 画面OFFまでの秒数変更メニュー
echo "---"
if [ "$DISPLAY_OFF_SECONDS" -eq 0 ]; then
    echo "⏱️  画面OFFまで: OFF"
else
    # 秒数を回数に変換（3秒間隔、切り上げ）
    DISPLAY_OFF_THRESHOLD=$(( (DISPLAY_OFF_SECONDS + 2) / 3 ))

    echo "⏱️  画面OFFまで: ${DISPLAY_OFF_SECONDS}秒"
    if [ "${IS_DISPLAY_OFF:-false}" = true ]; then
        echo "--Display: OFF | color=red"
    else
        echo "--Display: ON"
    fi
    echo "--Absent Count: ${ABSENT_COUNT:-0}/${DISPLAY_OFF_THRESHOLD}"
fi
echo "---"
echo "--OFF | bash=$0 param1=--set-display-off-0 terminal=false refresh=true"
echo "--10秒 | bash=$0 param1=--set-display-off-10 terminal=false refresh=true"
echo "--30秒 | bash=$0 param1=--set-display-off-30 terminal=false refresh=true"
echo "--60秒 | bash=$0 param1=--set-display-off-60 terminal=false refresh=true"
echo "--120秒 | bash=$0 param1=--set-display-off-120 terminal=false refresh=true"

echo "---"
if [ "$DEBUG_MODE" = true ]; then
    echo "🐛 デバッグモード: ON | color=yellow"
else
    echo "🐛 デバッグモード: OFF"
fi
echo "--デバッグモードを切り替え | bash=$0 param1=--toggle-debug-mode terminal=false refresh=true"

echo "---"
echo "Refresh | refresh=true"
