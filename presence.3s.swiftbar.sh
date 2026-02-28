#!/bin/bash
# <swiftbar.runInTerminal>false</swiftbar.runInTerminal>
# <swiftbar.debugLog>false</swiftbar.debugLog>
# <swiftbar.hideAbout>true</swiftbar.hideAbout>
# <swiftbar.hideRunInTerminal>true</swiftbar.hideRunInTerminal>
# <swiftbar.hideLastUpdated>false</swiftbar.hideLastUpdated>
# <swiftbar.image>system:name=person.fill</swiftbar.image>

. ~/Documents/Arduino/promicro-presence/config.sh

# ログファイル設定
LOG_FILE="/tmp/presence_debug.log"
MAX_LOG_LINES=5000  # ログファイルの最大行数（肥大化防止）

# ログ関数
log() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] $1" >> "$LOG_FILE"

    # ログファイルが大きすぎる場合は古い行を削除
    if [ -f "$LOG_FILE" ]; then
        local current_lines=$(wc -l < "$LOG_FILE" | tr -d '[:space:]')
        if [ "$current_lines" -gt "$MAX_LOG_LINES" ]; then
            tail -n $MAX_LOG_LINES "$LOG_FILE" > "$LOG_FILE.tmp"
            mv "$LOG_FILE.tmp" "$LOG_FILE"
        fi
    fi
}

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
    sed -i '' "s/^VERBOSE_MODE=.*/VERBOSE_MODE=$VERBOSE_MODE/" "$CONFIG_DIR/config.sh"
    sed -i '' "s/^PAUSED=.*/PAUSED=$PAUSED/" "$CONFIG_DIR/config.sh"
}

# ディスプレイをONにする（ArduinoにWコマンド送信、USB給電OFF時のみ）
display_on() {
    log "DISPLAY_ON: コマンド送信試行 (USB_POWER=$USB_POWER_INT, DISTANCE=$DISTANCE_INT)"
    if printf 'W\n' > "$DEVICE" 2>/dev/null; then
        log "DISPLAY_ON: コマンド送信成功"
    else
        log "DISPLAY_ON: コマンド送信失敗 (errno=$?)"
    fi
    IS_DISPLAY_OFF=false
}

# ディスプレイをOFFにする
display_off() {
    log "DISPLAY_OFF: ディスプレイをスリープさせます"
    pmset displaysleepnow
    IS_DISPLAY_OFF=true
}

# 状態ファイルから読み込み
load_state() {
    if [ -f "$STATE_FILE" ]; then
        source "$STATE_FILE"
    else
        LAST_PRESENT_TIME=$(date +%s)  # 初期値は現在時刻
        IS_DISPLAY_OFF=false
        PREV_USB_POWER=""  # 前回のUSB給電状態
        PREV_DEVICE_STATE=""  # 前回のデバイス状態
    fi
}

# 状態ファイルに保存
save_state() {
    cat > "$STATE_FILE" <<EOF
LAST_PRESENT_TIME=${LAST_PRESENT_TIME}
IS_DISPLAY_OFF=$IS_DISPLAY_OFF
PREV_USB_POWER=$PREV_USB_POWER
PREV_DEVICE_STATE=$PREV_DEVICE_STATE
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
            LAST_PRESENT_TIME=$(date +%s)
            IS_DISPLAY_OFF=false
            save_state
        fi
        save_config
        exit 0
        ;;
    --toggle-verbose-mode)
        load_config
        if [ "$VERBOSE_MODE" = true ]; then
            VERBOSE_MODE=false
        else
            VERBOSE_MODE=true
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
    # 状態を読み込む（デバイス判定より前に行う必要がある）
    load_state

    # 距離とUSB給電状態を取得
    SENSOR_DATA=$(head -n 1 "$DEVICE" 2>/dev/null)
    DISTANCE=$(echo "$SENSOR_DATA" | cut -d',' -f1)
    USB_POWER=$(echo "$SENSOR_DATA" | cut -d',' -f2)

    # デバイス接続エラー
    if [ -z "$DISTANCE" ]; then
        # デバイスエラー状態を記録（前回が正常だった場合のみログ）
        if [ "${PREV_DEVICE_STATE:-}" != "error" ]; then
            log "ERROR: デバイスからデータを取得できません (DEVICE=$DEVICE)"
            PREV_DEVICE_STATE="error"
            save_state
        fi
        echo "⚠️  No Device | color=red"
        echo "---"
        echo "Device: $DEVICE"
        echo "Refresh | refresh=true"
        exit 0
    fi

    # 整数に丸めて空白を削除
    DISTANCE_INT=${DISTANCE%.*}
    DISTANCE_INT=$(echo "$DISTANCE_INT" | tr -d '[:space:]')
    USB_POWER_INT=$(echo "$USB_POWER" | tr -d '[:space:]')

    # デバイス復帰判定
    if [ "${PREV_DEVICE_STATE:-}" = "error" ]; then
        log "DEVICE_RECOVERY: デバイスが復帰しました (距離: ${DISTANCE_INT}cm, USB: ${USB_POWER_INT})"
        display_on
        PREV_DEVICE_STATE="ok"
        save_state
    elif [ -z "${PREV_DEVICE_STATE:-}" ]; then
        # 初回起動時
        PREV_DEVICE_STATE="ok"
        save_state
    fi

    # USB状態マーク（300以上でONと判定）
    if [ "$USB_POWER_INT" -gt 300 ]; then
        USB_MARK="⚡"  # ON
        USB_STATUS="ON"
    else
        USB_MARK="💤"  # OFF
        USB_STATUS="OFF"
    fi

    # USB給電状態の変化をログ
    if [ -n "${PREV_USB_POWER:-}" ] && [ "$PREV_USB_POWER" != "$USB_STATUS" ]; then
        log "USB_POWER: ${PREV_USB_POWER} -> ${USB_STATUS} (値: $USB_POWER_INT)"
    fi
    PREV_USB_POWER="$USB_STATUS"

    # 基本情報をログ（常時記録）
    local presence_status=""
    if [ "$DISTANCE_INT" -le "$THRESHOLD_CM" ]; then
        presence_status="在室"
    else
        presence_status="不在"
    fi
    # 経過秒数を計算（不在の場合のみ）
    local elapsed_seconds=0
    if [ "$presence_status" = "不在" ] && [ -n "$LAST_PRESENT_TIME" ]; then
        elapsed_seconds=$(($(date +%s) - LAST_PRESENT_TIME))
    fi
    log "SENSOR: 距離=${DISTANCE_INT}cm, USB=${USB_STATUS}(${USB_POWER_INT}), 在室=${presence_status}, Display=$([ "$IS_DISPLAY_OFF" = true ] && echo "OFF" || echo "ON"), Elapsed=${elapsed_seconds}s"

    # ディスプレイ制御が有効な場合の処理
    if [ "$DISPLAY_OFF_SECONDS" -gt 0 ]; then
        # 在室判定
        if [ "$DISTANCE_INT" -le "$THRESHOLD_CM" ]; then
            # 在室：現在時刻を記録
            LAST_PRESENT_TIME=$(date +%s)

            # ディスプレイがOFF状態の場合
            if [ "$IS_DISPLAY_OFF" = true ]; then
                log "DISPLAY_RECOVERY: ディスプレイOFF状態から復帰します (距離: ${DISTANCE_INT}cm)"
                display_on
            fi
            # USB給電がOFFの時はdisplay_on
            if [ -n "$USB_POWER_INT" ] && [ "$USB_POWER_INT" -le 300 ]; then
                log "USB_POWER_RECOVERY: USB給電OFFから復帰します (値: ${USB_POWER_INT})"
                display_on
            fi
        else
            # 不在：経過時間を計算
            if [ -n "$LAST_PRESENT_TIME" ]; then
                local elapsed_seconds=$(($(date +%s) - LAST_PRESENT_TIME))

                if [ "$IS_DISPLAY_OFF" = false ] && [ "$elapsed_seconds" -ge "$DISPLAY_OFF_SECONDS" ]; then
                    log "DISPLAY_OFF: 不在継続によりディスプレイをスリープさせます (経過: ${elapsed_seconds}s/${DISPLAY_OFF_SECONDS}s)"
                    display_off
                fi
            fi
        fi

        save_state
    fi

    # 在室判定（表示用）
    if [ "$DISTANCE_INT" -le "$THRESHOLD_CM" ]; then
        # 在室
        if [ "$VERBOSE_MODE" = true ]; then
            echo "🟢 ${DISTANCE_INT}cm ${USB_MARK}"
        else
            echo "🟢 ${DISTANCE_INT}cm ${USB_MARK}"
        fi
        echo "---"
        echo "Status: 在室"
    else
        # 不在：経過秒数を計算
        local elapsed_seconds=0
        if [ -n "$LAST_PRESENT_TIME" ]; then
            elapsed_seconds=$(($(date +%s) - LAST_PRESENT_TIME))
        fi

        if [ "$VERBOSE_MODE" = true ]; then
            echo "🟠 ${DISTANCE_INT}cm ${USB_MARK} (${elapsed_seconds}s) | color=orange"
        else
            echo "🟠 ${DISTANCE_INT}cm ${USB_MARK} | color=orange"
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
    echo "⏱️  画面OFFまで: ${DISPLAY_OFF_SECONDS}秒"
    if [ "${IS_DISPLAY_OFF:-false}" = true ]; then
        echo "--Display: OFF | color=red"
    else
        echo "--Display: ON"
        # 経過秒数を表示
        local elapsed_seconds=0
        if [ -n "$LAST_PRESENT_TIME" ]; then
            elapsed_seconds=$(($(date +%s) - LAST_PRESENT_TIME))
        fi
        echo "--経過時間: ${elapsed_seconds}s/${DISPLAY_OFF_SECONDS}s"
    fi
fi
echo "---"
echo "--OFF | bash=$0 param1=--set-display-off-0 terminal=false refresh=true"
echo "--10秒 | bash=$0 param1=--set-display-off-10 terminal=false refresh=true"
echo "--30秒 | bash=$0 param1=--set-display-off-30 terminal=false refresh=true"
echo "--60秒 | bash=$0 param1=--set-display-off-60 terminal=false refresh=true"
echo "--120秒 | bash=$0 param1=--set-display-off-120 terminal=false refresh=true"

echo "---"
if [ "$VERBOSE_MODE" = true ]; then
    echo "📊 詳細表示: ON | color=yellow"
else
    echo "📊 詳細表示: OFF"
fi
echo "--詳細表示を切り替え | bash=$0 param1=--toggle-verbose-mode terminal=false refresh=true"

echo "---"
if [ "$VERBOSE_MODE" = true ] && [ -n "$USB_POWER_INT" ]; then
    # USB状態を表示
    if [ "$USB_POWER_INT" -gt 300 ]; then
        echo "⚡ USB Display: ON ($USB_POWER_INT) | color=green"
    else
        echo "💤 USB Display: OFF ($USB_POWER_INT) | color=gray"
    fi
fi

# デバッグログ関連メニュー
echo "---"
echo "📋 デバッグログ"
if [ -f "$LOG_FILE" ]; then
    LOG_LINES=$(wc -l < "$LOG_FILE" | tr -d '[:space:]')
    echo "--ログ行数: ${LOG_LINES}"
    echo "--ログを表示 | shell='/usr/bin/tail' param1 = '-F' param2='$LOG_FILE' terminal=true"
    echo "--ログを削除 | shell='/bin/rm' param1='$LOG_FILE' terminal=false refresh=true"
else
    echo "--ログなし | color=gray"
fi

echo "---"
echo "Refresh | refresh=true"
