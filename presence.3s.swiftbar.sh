#!/bin/bash
# <swiftbar.runInTerminal>false</swiftbar.runInTerminal>
# <swiftbar.debugLog>false</swiftbar.debugLog>
# <swiftbar.hideAbout>true</swiftbar.hideAbout>
# <swiftbar.hideRunInTerminal>true</swiftbar.hideRunInTerminal>
# <swiftbar.hideLastUpdated>false</swiftbar.hideLastUpdated>
# <swiftbar.image>system:name=person.fill</swiftbar.image>

# プロジェクトのベースパス（共通設定）
PROJECT_DIR=~/dev/Arduino/promicro-presence
. "$PROJECT_DIR/config.sh"

# 定数
USB_POWER_THRESHOLD=300  # USB給電ON判定の閾値
LOG_ROTATION_INTERVAL=100  # ログ回転チェック間隔（呼び出し回数）

# ログファイル設定
LOG_FILE="/tmp/presence_debug.log"
MAX_LOG_LINES=5000  # ログファイルの最大行数（肥大化防止）
LOG_CALL_COUNT=0  # ログ呼び出しカウンター

# ログ関数（最適化済み）
log() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] $1" >> "$LOG_FILE"

    # ログ回転を定期的にチェック only（毎回チェックしない）
    LOG_CALL_COUNT=$((LOG_CALL_COUNT + 1))
    if [ $LOG_CALL_COUNT -ge $LOG_ROTATION_INTERVAL ]; then
        LOG_CALL_COUNT=0
        local current_lines=$(wc -l < "$LOG_FILE" 2>/dev/null | tr -d '[:space:]')
        if [ -n "$current_lines" ] && [ "$current_lines" -gt "$MAX_LOG_LINES" ]; then
            tail -n $MAX_LOG_LINES "$LOG_FILE" > "$LOG_FILE.tmp"
            mv "$LOG_FILE.tmp" "$LOG_FILE"
        fi
    fi
}

# 現在時刻をキャッシュ（スクリプト全体で再利用）
NOW=$(date +%s)

# Arduinoに閾値を送信（起動時のみ）
if [ -n "$THRESHOLD_CM" ]; then
    printf 'T%d\n' "$THRESHOLD_CM" > "$DEVICE" 2>/dev/null
fi

# 設定ファイルディレクトリ（プロジェクトパスを使用）
CONFIG_DIR="$PROJECT_DIR"
# 状態ファイル（不在カウント、ディスプレイOFF状態、前回の距離）
STATE_FILE="$CONFIG_DIR/.presence_display_state"

# トグルヘルパー関数（コピペ削減）
toggle_bool() {
    local var_name="$1"
    local current_value="${!var_name}"

    if [ "$current_value" = true ]; then
        eval "$var_name=false"
    else
        eval "$var_name=true"
    fi
}

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
        # 不在カウンターをクリア
        LAST_PRESENT_TIME=$NOW
        log "DISPLAY_ON: 不在カウンターをクリアしました"
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
        LAST_PRESENT_TIME=$NOW  # 初期値は現在時刻
        IS_DISPLAY_OFF=false
        PREV_USB_POWER=""  # 前回のUSB給電状態
        PREV_DEVICE_STATE=""  # 前回のデバイス状態
    fi
}

# 状態ファイルに保存（変更時のみ）
save_state() {
    local new_state=$(cat <<EOF
LAST_PRESENT_TIME=${LAST_PRESENT_TIME}
IS_DISPLAY_OFF=$IS_DISPLAY_OFF
PREV_USB_POWER=${PREV_USB_POWER}
PREV_DEVICE_STATE=${PREV_DEVICE_STATE}
EOF
)
    # 前回の状態と異なる場合のみ書き込み
    if [ ! -f "$STATE_FILE" ] || [ "$(<"$STATE_FILE")" != "$new_state" ]; then
        echo "$new_state" > "$STATE_FILE"
    fi
}

# 設定を再読み込みする関数
load_config() {
    . "$PROJECT_DIR/config.sh"
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
        toggle_bool PAUSED
        save_config
        exit 0
        ;;
    --set-threshold-*)
        # パラメータから値を抽出 (例: --set-threshold-150)
        new_threshold="${ACTION#--set-threshold-}"

        # config.shを書き換え
        sed -i '' "s/^THRESHOLD_CM=.*/THRESHOLD_CM=$new_threshold/" "$PROJECT_DIR/config.sh"

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
            # 状態初期化（キャッシュしたNOWを使用）
            LAST_PRESENT_TIME=$NOW
            IS_DISPLAY_OFF=false
            save_state
        fi
        save_config
        exit 0
        ;;
    --toggle-verbose-mode)
        load_config
        toggle_bool VERBOSE_MODE
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

    # USB状態マーク（USB_POWER_THRESHOLD以上でONと判定）
    if [ "$USB_POWER_INT" -gt "$USB_POWER_THRESHOLD" ]; then
        USB_MARK="⚡"  # ON
        USB_STATUS="ON"
    else
        USB_MARK="💤"  # OFF
        USB_STATUS="OFF"
    fi

    # USB給電状態の変化をログ
    if [ -n "${PREV_USB_POWER:-}" ] && [ "$PREV_USB_POWER" != "$USB_STATUS" ]; then
        log "USB_POWER: ${PREV_USB_POWER} -> ${USB_STATUS} (値: $USB_POWER_INT)"
        # USB状態変化時に不在カウンターをクリア
        LAST_PRESENT_TIME=$NOW
        log "USB_POWER: 不在カウンターをクリアしました"
    fi
    PREV_USB_POWER="$USB_STATUS"

    # 在室判定を1回だけ実行
    is_present=false
    if [ "$DISTANCE_INT" -le "$THRESHOLD_CM" ]; then
        is_present=true
    fi

    # 経過秒数を計算（常に計算して、在室/不在どちらでも使用可能にする）
    elapsed_seconds=0
    if [ -n "$LAST_PRESENT_TIME" ]; then
        elapsed_seconds=$((NOW - LAST_PRESENT_TIME))
    fi

    # ディスプレイ状態の文字列（ログ用に事前計算）
    display_status="OFF"
    if [ "$IS_DISPLAY_OFF" = false ]; then
        display_status="ON"
    fi

    # 基本情報をログ（常時記録）
    presence_status="不在"
    if [ "$is_present" = true ]; then
        presence_status="在室"
    fi
    log "SENSOR: 距離=${DISTANCE_INT}cm, USB=${USB_STATUS}(${USB_POWER_INT}), 在室=${presence_status}, Display=${display_status}, Elapsed=${elapsed_seconds}s"

    # ディスプレイ制御が有効な場合の処理
    if [ "$DISPLAY_OFF_SECONDS" -gt 0 ]; then
        if [ "$is_present" = true ]; then
            # 在室：現在時刻を記録
            LAST_PRESENT_TIME=$NOW

            # ディスプレイがOFF状態の場合
            if [ "$IS_DISPLAY_OFF" = true ]; then
                log "DISPLAY_RECOVERY: ディスプレイOFF状態から復帰します (距離: ${DISTANCE_INT}cm)"
                display_on
            fi
            # USB給電がOFFの時はdisplay_on
            if [ -n "$USB_POWER_INT" ] && [ "$USB_POWER_INT" -le "$USB_POWER_THRESHOLD" ]; then
                log "USB_POWER_RECOVERY: USB給電OFFから復帰します (値: ${USB_POWER_INT})"
                display_on
            fi
        else
            # 不在：経過時間判定
            if [ "$IS_DISPLAY_OFF" = false ] && [ "$elapsed_seconds" -ge "$DISPLAY_OFF_SECONDS" ]; then
                log "DISPLAY_OFF: 不在継続によりディスプレイをスリープさせます (経過: ${elapsed_seconds}s/${DISPLAY_OFF_SECONDS}s)"
                display_off
            fi
        fi

        save_state
    fi

    # 在室判定（表示用）
    if [ "$is_present" = true ]; then
        # 在室（条件分岐削減 - 両ブランチ同じ出力）
        echo "🟢 ${DISTANCE_INT}cm ${USB_MARK}"
        echo "---"
        echo "Status: 在室"
    else
        # 不在（計算済みのelapsed_secondsを使用）
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
        # 経過秒数を表示（センサーデータ取得済みの場合はその値、未取得の場合は計算）
        if [ -n "${elapsed_seconds:-}" ]; then
            echo "--経過時間: ${elapsed_seconds}s/${DISPLAY_OFF_SECONDS}s"
        elif [ -n "${LAST_PRESENT_TIME:-}" ]; then
            menu_elapsed=$((NOW - LAST_PRESENT_TIME))
            echo "--経過時間: ${menu_elapsed}s/${DISPLAY_OFF_SECONDS}s"
        else
            echo "--経過時間: 0s/${DISPLAY_OFF_SECONDS}s"
        fi
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
if [ "$VERBOSE_MODE" = true ]; then
    # USB状態を表示（定数USB_POWER_THRESHOLDを使用）
    if [ -n "$USB_POWER_INT" ]; then
        if [ "$USB_POWER_INT" -gt "$USB_POWER_THRESHOLD" ]; then
            echo "⚡ USB給電: ON ($USB_POWER_INT) | color=green"
        else
            echo "💤 USB給電: OFF ($USB_POWER_INT) | color=gray"
        fi
    fi

    # ディスプレイ状態を表示
    if [ "${IS_DISPLAY_OFF:-false}" = true ]; then
        echo "💻 ディスプレイ: OFF | color=red"
    else
        echo "💻 ディスプレイ: ON | color=green"
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
