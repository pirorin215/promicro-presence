#!/bin/bash
# <swiftbar.runInTerminal>false</swiftbar.runInTerminal>
# <swiftbar.debugLog>false</swiftbar.debugLog>
# <swiftbar.hideAbout>true</swiftbar.hideAbout>
# <swiftbar.hideRunInTerminal>true</swiftbar.hideRunInTerminal>
# <swiftbar.hideLastUpdated>false</swiftbar.hideLastUpdated>
# <swiftbar.image>system:name=display</swiftbar.image>

# ディスプレイ接続検出時に自動的にcaffeinateを発行してディスプレイをオンにする
#
# 使い方:
# 1. SwiftBarでこのスクリプトを追加（3秒間隔推奨）
# 2. Thunderboltハブなどを接続すると自動的にディスプレイが起動します

# 状態ファイル
STATE_FILE="$HOME/.monitor_connect_wake_state"
# 一時停止設定ファイル
PAUSED_FILE="$HOME/.monitor_connect_wake_paused"
# ログファイル
LOG_FILE="$HOME/.monitor_connect_wake.log"

# ログ関数
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

# 前回のディスプレイ数を読み込み
load_state() {
    if [ -f "$STATE_FILE" ]; then
        source "$STATE_FILE"
    else
        PREV_DISPLAY_COUNT=0
    fi
}

# 状態を保存
save_state() {
    cat > "$STATE_FILE" <<EOF
PREV_DISPLAY_COUNT=$PREV_DISPLAY_COUNT
EOF
}

# メニューアクション処理
ACTION="$1"

case "$ACTION" in
    --toggle-pause)
        if [ -f "$PAUSED_FILE" ]; then
            rm -f "$PAUSED_FILE"
        else
            touch "$PAUSED_FILE"
        fi
        exit 0
        ;;
    --open-log)
        open "$LOG_FILE"
        exit 0
        ;;
esac

# 一時停止中
if [ -f "$PAUSED_FILE" ]; then
    echo "⏸️ OFF"
else
    # 状態を読み込み
    load_state

    # 現在接続されているディスプレイ数を取得
    # Resolution行の直前にあるディスプレイ名を取得し、"Display:"と"Resolution:"を除外
    DISPLAYS=$(system_profiler SPDisplaysDataType 2>/dev/null | grep -B1 "Resolution" | grep "^\s*[A-Z]" | grep -v "^\s*Display$" | grep -v "^\s*Resolution:")

    # Display:のみの場合は物理ディスプレイなし
    if echo "$DISPLAYS" | grep -q "^\s*Display:$"; then
        CURRENT_DISPLAY_COUNT=0
        DISPLAY_NAME="(なし)"
    else
        CURRENT_DISPLAY_COUNT=$(echo "$DISPLAYS" | wc -l | tr -d '[:space:]')
        DISPLAY_NAME=$(echo "$DISPLAYS" | head -1 | tr -d '[:space:]')
    fi

    log "ディスプレイ数: ${CURRENT_DISPLAY_COUNT} (${DISPLAY_NAME})"

    # ディスプレイ数が増えた（接続された）場合
    if [ "$CURRENT_DISPLAY_COUNT" -gt "$PREV_DISPLAY_COUNT" ]; then
        log "ディスプレイ接続を検出: ${PREV_DISPLAY_COUNT} -> ${CURRENT_DISPLAY_COUNT}"
        log "caffeinate -u -t 1 を発行"
        # ディスプレイをオンにする
        caffeinate -u -t 1 &
    fi

    # 状態を保存
    PREV_DISPLAY_COUNT=$CURRENT_DISPLAY_COUNT
    save_state

    # デバッグ用: ディスプレイ数の変化をログ（必要に応じてコメントアウト解除）
    # log "ディスプレイ数: ${CURRENT_DISPLAY_COUNT}"

    # メニュー表示
    echo "🖥️ ${CURRENT_DISPLAY_COUNT}"
fi

echo "---"
if [ -n "${DISPLAYS:-}" ]; then
    if [ "$CURRENT_DISPLAY_COUNT" -eq 0 ]; then
        echo "ディスプレイ: 接続なし | color=gray"
    else
        # 複数のディスプレイをそれぞれ表示
        echo "$DISPLAYS" | while read -r display; do
            display_trimmed=$(echo "$display" | tr -d '[:space:]')
            echo "ディスプレイ: $display_trimmed"
        done
    fi
fi
echo "---"
if [ -f "$PAUSED_FILE" ]; then
    echo "一時停止中 | color=yellow"
else
    echo "監視中"
fi
echo "--一時停止 | bash=$0 param1=--toggle-pause terminal=false refresh=true"
echo "---"
echo "ログを開く | bash=$0 param1=--open-log terminal=false"
echo "---"
echo "Refresh | refresh=true"
