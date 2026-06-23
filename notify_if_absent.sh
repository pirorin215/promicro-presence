#!/bin/bash
# 在室判定して通知を送るスクリプト
# 在室時は通知しない、不在時のみ通知を送る
# 音は応答のたび（センサーから距離が読めたら）必ず鳴る
# 通知の title/message は環境変数 NOTIFY_TITLE / NOTIFY_MSG で上書き可能
# （未設定なら config.sh の値 / デフォルト）
# omp の session_stop 拡張、および Claude Code の hooks.Stop/Notification から呼ばれる

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/config.sh"

# 通知内容（呼び出し元が環境変数で上書き可能）
TITLE="${NOTIFY_TITLE:-💬 エージェント}"
MESSAGE="${NOTIFY_MSG:-$NOTIFY_MESSAGE}"

# ntfy.shに通知を送る関数
send_notification() {
    local title="$1"
    local message="$2"
    local tags="${3:-}"      # オプション: 絵文字タグ
    local priority="${4:-3}" # オプション: 優先度 (1-5, デフォルト3)

    local -a hdrs=(-H "X-Title: $title" -H "X-Priority: $priority")
    [ -n "$tags" ] && hdrs+=(-H "X-Tags: $tags")
    curl -s "${hdrs[@]}" -H "Content-Type: text/plain" --data-binary "$message" "$NOTIFY_URL" >/dev/null
}

# 距離を取得
DISTANCE=$(head -n 1 "$DEVICE" 2>/dev/null)

# 距離が取得できなかった場合は通知する（安全側）
if [ -z "$DISTANCE" ]; then
    afplay "$SOUND_FILE" &
    send_notification "$TITLE" "$MESSAGE" "speech_balloon" 3
    exit 0
fi

# 整数に丸めて比較
DISTANCE_INT=${DISTANCE%.*}

# 音は応答のたびに鳴らす（在室/不在問わず）
afplay "$SOUND_FILE" &

# 在室判定（閾値以下なら在室とみなす）
if [ "$DISTANCE_INT" -le "$THRESHOLD_CM" ]; then
    # 在室: 通知しない（音は鳴った）
    exit 0
else
    # 不在: 通知を送る
    send_notification "$TITLE" "$MESSAGE" "speech_balloon" 3
    exit 0
fi
