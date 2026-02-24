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

# ディスプレイ制御設定ファイル
DISPLAY_CONTROL_ENABLED_FILE="$HOME/.display_control_enabled"
# デバッグモード設定ファイル
DEBUG_MODE_FILE="$HOME/.display_control_debug"
# 一時停止設定ファイル
PAUSED_FILE="$HOME/.display_control_paused"
# 状態ファイル
STATE_FILE="$HOME/.display_control_state"
# ディスプレイをオフにするまでの秒数設定ファイル
DISPLAY_OFF_THRESHOLD_FILE="$HOME/.display_control_off_threshold"

# ディスプレイをオフにするまでの回数（3秒間隔）
if [ -f "$DISPLAY_OFF_THRESHOLD_FILE" ]; then
    DISPLAY_OFF_THRESHOLD=$(cat "$DISPLAY_OFF_THRESHOLD_FILE")
else
    DISPLAY_OFF_THRESHOLD=10  # デフォルト: 30秒 (10回 × 3秒)
fi

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
    --toggle-pause)
        if [ -f "$PAUSED_FILE" ]; then
            rm -f "$PAUSED_FILE"
        else
            touch "$PAUSED_FILE"
        fi
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
            rm -f "$DISPLAY_CONTROL_ENABLED_FILE"
            rm -f "$STATE_FILE"
        else
            # 回数に変換（3秒間隔なので ÷3）
            display_off_count=$((display_off_seconds / 3))

            # 設定ファイルに保存
            echo "$display_off_count" > "$DISPLAY_OFF_THRESHOLD_FILE"

            # ディスプレイ自動制御をON
            if [ ! -f "$DISPLAY_CONTROL_ENABLED_FILE" ]; then
                touch "$DISPLAY_CONTROL_ENABLED_FILE"
                # 状態初期化
                ABSENT_COUNT=0
                IS_DISPLAY_OFF=false
                save_state
            fi
        fi

        exit 0
        ;;
    --toggle-display-control)
        # 内部使用のみ（画面OFF時間設定から自動的に呼ばれる）
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

# 一時停止中なら距離取得をスキップ
if [ -f "$PAUSED_FILE" ]; then
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
fi

# Device表示（共通）
echo "---"
echo "Device: $DEVICE"

# 一時停止の状態表示
if [ -f "$PAUSED_FILE" ]; then
    echo "---"
    echo "⏸️ 一時停止: ON | color=yellow"
else
    echo "---"
    echo "⏸️ 一時停止: OFF | color=gray"
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
if [ -f "$DISPLAY_CONTROL_ENABLED_FILE" ]; then
    display_off_seconds=$((DISPLAY_OFF_THRESHOLD * 3))
    echo "---"
    echo "⏱️  画面OFFまで: ${display_off_seconds}秒"
    if [ "${IS_DISPLAY_OFF:-false}" = true ]; then
        echo "--Display: OFF | color=red"
    else
        echo "--Display: ON | color=green"
    fi
    echo "--Absent Count: ${ABSENT_COUNT:-0}/${DISPLAY_OFF_THRESHOLD}"
    echo "---"
    echo "--OFF | bash=$0 param1=--set-display-off-0 terminal=false refresh=true"
    echo "--30秒 | bash=$0 param1=--set-display-off-30 terminal=false refresh=true"
    echo "--60秒 | bash=$0 param1=--set-display-off-60 terminal=false refresh=true"
    echo "--90秒 | bash=$0 param1=--set-display-off-90 terminal=false refresh=true"
    echo "--120秒 | bash=$0 param1=--set-display-off-120 terminal=false refresh=true"
else
    echo "---"
    echo "⏱️  画面OFFまで: OFF"
    echo "---"
    echo "--30秒 | bash=$0 param1=--set-display-off-30 terminal=false refresh=true"
    echo "--60秒 | bash=$0 param1=--set-display-off-60 terminal=false refresh=true"
    echo "--90秒 | bash=$0 param1=--set-display-off-90 terminal=false refresh=true"
    echo "--120秒 | bash=$0 param1=--set-display-off-120 terminal=false refresh=true"
fi

echo "---"
if [ -f "$DEBUG_MODE_FILE" ]; then
    echo "🐛 デバッグモード: ON | color=yellow"
else
    echo "🐛 デバッグモード: OFF | color=gray"
fi
echo "--デバッグモードを切り替え | bash=$0 param1=--toggle-debug-mode terminal=false refresh=true"

echo "---"
echo "Refresh | refresh=true"
