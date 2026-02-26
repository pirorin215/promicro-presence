#!/bin/bash
# <swiftbar.runInTerminal>false</swiftbar.runInTerminal>
# <swiftbar.debugLog>false</swiftbar.debugLog>
# <swiftbar.hideAbout>true</swiftbar.hideAbout>
# <swiftbar.hideRunInTerminal>true</swiftbar.hideRunInTerminal>
# <swiftbar.hideLastUpdated>false</swiftbar.hideLastUpdated>
# <swiftbar.image>system:name=display</swiftbar.image>

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
    --open-displays)
        open "x-apple.systempreferences:com.apple.preference.displays"
        exit 0
        ;;
esac

# 一時停止中
if [ -f "$PAUSED_FILE" ]; then
    echo "⏸️ OFF"
else
    # 状態を読み込み
    load_state

    # 現在接続されているディスプレイ情報を取得（名前と解像度のペア）
    # grep -B1 "Resolution:" でディスプレイ名と解像度を取得して整形
    DISPLAY_INFO=$(system_profiler SPDisplaysDataType 2>/dev/null | grep -B1 "Resolution:" | awk '
        BEGIN { display_name = ""; resolution = ""; }
        /^[[:space:]]+[A-Z].*:[[:space:]]*$/ {
            # ディスプレイ名行（: で終わるもの）
            display_name = $0;
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", display_name);
            next;
        }
        /Resolution:/ {
            # 解像度行
            resolution = $0;
            sub(/^[[:space:]]*Resolution:[[:space:]]*/, "", resolution);
            # 括弧以下の情報を削除（例: 3440 x 1440 (UWQHD - Ultra-Wide Quad HD) -> 3440 x 1440）
            sub(/[[:space:]]*\(.*$/, "", resolution);
            gsub(/[[:space:]]+$/, "", resolution);
            # ディスプレイ名と解像度をペアで出力
            if (display_name != "") {
                print display_name "|" resolution;
                display_name = "";
                resolution = "";
            }
            next;
        }
    ')

    # Display:のみの場合は物理ディスプレイなし
    if [ -z "$DISPLAY_INFO" ]; then
        CURRENT_DISPLAY_COUNT=0
        DISPLAY_NAME="(なし)"
    else
        CURRENT_DISPLAY_COUNT=$(echo "$DISPLAY_INFO" | wc -l | tr -d '[:space:]')
        DISPLAY_NAME=$(echo "$DISPLAY_INFO" | head -1 | cut -d'|' -f1 | tr -d '[:space:]')
    fi

    log "ディスプレイ数: ${CURRENT_DISPLAY_COUNT} (${DISPLAY_NAME})"

    # ディスプレイ数が増えた（接続された）場合
    if [ "$CURRENT_DISPLAY_COUNT" -gt "$PREV_DISPLAY_COUNT" ]; then
        log "ディスプレイ接続を検出: ${PREV_DISPLAY_COUNT} -> ${CURRENT_DISPLAY_COUNT}"
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
if [ -n "${DISPLAY_INFO:-}" ]; then
    if [ "$CURRENT_DISPLAY_COUNT" -eq 0 ]; then
        echo "ディスプレイ: 接続なし | color=gray"
    else
        # 複数のディスプレイをそれぞれ表示（名前と解像度）
        echo "$DISPLAY_INFO" | while IFS='|' read -r display_name resolution; do
            display_name_trimmed=$(echo "$display_name" | tr -d '[:space:]')
            if [ -n "$resolution" ]; then
                echo "$display_name_trimmed ($resolution)"
            else
                echo "ディスプレイ: $display_name_trimmed"
            fi
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
echo "ディスプレイ設定を開く | bash=$0 param1=--open-displays terminal=false"
echo "---"
echo "Refresh | refresh=true"
