#!/bin/bash
# <swiftbar.runInTerminal>false</swiftbar.runInTerminal>
# <swiftbar.debugLog>false</swiftbar.debugLog>
# <swiftbar.hideAbout>true</swiftbar.hideAbout>
# <swiftbar.hideRunInTerminal>true</swiftbar.hideRunInTerminal>
# <swiftbar.hideLastUpdated>false</swiftbar.hideLastUpdated>
# <swiftbar.image>system:name=person.fill</swiftbar.image>

. ~/Documents/Arduino/promicro-presence/config.sh

# ディスプレイ制御設定ファイル
DISPLAY_CONTROL_ENABLED_FILE="$HOME/.display_control_enabled"
# デバッグモード設定ファイル
DEBUG_MODE_FILE="$HOME/.display_control_debug"
# 状態ファイル
STATE_FILE="$HOME/.display_control_state"
# ディスプレイをオフにするまでの時間（秒）= 3秒間隔 × 10回 = 30秒
DISPLAY_OFF_THRESHOLD=10

# 状態ファイルから読み込み
load_state() {
    if [ -f "$STATE_FILE" ]; then
        source "$STATE_FILE"
    else
        ABSENT_COUNT=0
        IS_DISPLAY_OFF=false
    fi
}

# 状態ファイルに保存
save_state() {
    cat > "$STATE_FILE" <<EOF
ABSENT_COUNT=$ABSENT_COUNT
IS_DISPLAY_OFF=$IS_DISPLAY_OFF
EOF
}

# メニューアクション処理
ACTION="$1"

# トグルアクション
case "$ACTION" in
    --toggle-display-control)
        if [ -f "$DISPLAY_CONTROL_ENABLED_FILE" ]; then
            rm -f "$DISPLAY_CONTROL_ENABLED_FILE"
            # 状態もリセット
            rm -f "$STATE_FILE"
        else
            touch "$DISPLAY_CONTROL_ENABLED_FILE"
            # 状態初期化
            ABSENT_COUNT=0
            IS_DISPLAY_OFF=false
            save_state
        fi
        exit 0
        ;;
    --toggle-debug-mode)
        if [ -f "$DEBUG_MODE_FILE" ]; then
            rm -f "$DEBUG_MODE_FILE"
        else
            touch "$DEBUG_MODE_FILE"
        fi
        exit 0
        ;;
esac

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
if [ -f "$DISPLAY_CONTROL_ENABLED_FILE" ]; then
    # 在室判定
    if [ "$DISTANCE_INT" -le "$THRESHOLD_CM" ]; then
        # 在室
        if [ "$IS_DISPLAY_OFF" = true ]; then
            caffeinate -u -t 1 &
            IS_DISPLAY_OFF=false
        fi
        ABSENT_COUNT=0
    else
        # 不在
        ABSENT_COUNT=$((ABSENT_COUNT + 1))

        if [ "$IS_DISPLAY_OFF" = false ] && [ "$ABSENT_COUNT" -ge "$DISPLAY_OFF_THRESHOLD" ]; then
            pmset displaysleepnow
            IS_DISPLAY_OFF=true
        fi
    fi

    # 状態を保存
    save_state
fi

# 在室判定（表示用）
if [ "$DISTANCE_INT" -le "$THRESHOLD_CM" ]; then
    # 在室
    if [ -f "$DEBUG_MODE_FILE" ]; then
        echo "🟢 ${DISTANCE_INT}cm (A:${ABSENT_COUNT}) | color=green"
    else
        echo "🟢 ${DISTANCE_INT}cm | color=green"
    fi
    echo "---"
    echo "Status: 在室"
else
    # 不在
    if [ -f "$DEBUG_MODE_FILE" ]; then
        echo "🟠 ${DISTANCE_INT}cm (A:${ABSENT_COUNT}) | color=orange"
    else
        echo "🟠 ${DISTANCE_INT}cm | color=orange"
    fi
    echo "---"
    echo "Status: 不在"
fi

echo "---"
echo "Device: $DEVICE"
echo "Threshold: ${THRESHOLD_CM}cm"

# ディスプレイ自動制御の状態表示
if [ -f "$DISPLAY_CONTROL_ENABLED_FILE" ]; then
    echo "---"
    echo "✅ ディスプレイ自動制御: ON | color=green"
    if [ "$IS_DISPLAY_OFF" = true ]; then
        echo "--Display: OFF | color=red"
    else
        echo "--Display: ON | color=green"
    fi
    echo "--Absent Count: ${ABSENT_COUNT}/${DISPLAY_OFF_THRESHOLD}"
else
    echo "---"
    echo "⬜ ディスプレイ自動制御: OFF | color=gray"
fi

echo "--ディスプレイ自動制御を切り替え | bash=$0 param1=--toggle-display-control terminal=false refresh=true"

echo "---"
if [ -f "$DEBUG_MODE_FILE" ]; then
    echo "🐛 デバッグモード: ON | color=yellow"
else
    echo "🐛 デバッグモード: OFF | color=gray"
fi
echo "--デバッグモードを切り替え | bash=$0 param1=--toggle-debug-mode terminal=false refresh=true"

echo "---"
echo "Refresh | refresh=true"
