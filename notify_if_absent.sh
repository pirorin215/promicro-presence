#!/bin/bash
# 在室判定して通知を送るスクリプト
# 在室時は通知しない、不在時のみ通知を送る

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/config.sh"

# ntfy.shに通知を送る関数
send_notification() {
    local title="$1"
    local message="$2"
    local tags="${3:-}"      # オプション: 絵文字タグ
    local priority="${4:-3}" # オプション: 優先度 (1-5, デフォルト3)

    local curl_cmd="curl -s"
    curl_cmd+=" -H 'X-Title: $title'"

    if [ -n "$tags" ]; then
        curl_cmd+=" -H 'X-Tags: $tags'"
    fi

    curl_cmd+=" -H 'X-Priority: $priority'"
    curl_cmd+=" -d \"$message\" \"$NOTIFY_URL\""

    eval "$curl_cmd"
}

# Claude Codeの最新の状態を判定
detect_claude_state() {
    local debug_dir="$HOME/.claude/debug"
    local latest_log_file=$(ls -t "$debug_dir" 2>/dev/null | grep -v '^latest$' | head -1)

    if [ -z "$latest_log_file" ]; then
        echo "unknown"
        return
    fi

    local latest_log="$debug_dir/$latest_log_file"

    if [ ! -f "$latest_log" ]; then
        echo "unknown"
        return
    fi

    sleep 3

    # 最新の30行から、最新（最後）のイベント行を抽出
    local last_line=$(tail -30 "$latest_log" | grep -E "permission_prompt|idle_prompt|AskUserQuestion|completed successfully|ERROR" | tail -1)

    # 判定：最新のイベントに基づいて
    if echo "$last_line" | grep -q "permission_prompt"; then
        echo "permission"
    elif echo "$last_line" | grep -q "idle_prompt"; then
        echo "idle"
    elif echo "$last_line" | grep -q "Getting matching hook commands for PermissionRequest with query: AskUserQuestion"; then
        echo "question"
    elif echo "$last_line" | grep -q "completed successfully"; then
        echo "completed"
    elif echo "$last_line" | grep -q "\[ERROR\]"; then
        # 大文字の[ERROR]のみを真のエラーとみなす
        echo "error"
    else
        echo "working"
    fi
}

# 距離を取得
DISTANCE=$(head -n 1 "$DEVICE" 2>/dev/null)

# 距離が取得できなかった場合は通知する（安全側）
if [ -z "$DISTANCE" ]; then
    afplay "$SOUND_FILE" &
    STATE=$(detect_claude_state)
    case "$STATE" in
        "permission")
            send_notification "⏸️ 許可待ち" "コマンドの実行許可を待っています" "thinking" 4
            ;;
        "question")
            send_notification "❓ 質問" "Claude Codeが質問しています" "question_mark" 3
            ;;
        "error")
            send_notification "❌ エラー" "エラーが発生しました" "x" 5
            ;;
        *)
            send_notification "💬 Claude Code" "$NOTIFY_MESSAGE" "speech_balloon" 3
            ;;
    esac
    exit 0
fi

# 整数に丸めて比較
DISTANCE_INT=${DISTANCE%.*}

afplay "$SOUND_FILE" &

# 在室判定（閾値以下なら在室とみなす）
if [ "$DISTANCE_INT" -le "$THRESHOLD_CM" ]; then
    # 在室: 通知しない
    exit 0
else
    # 不在: 音を鳴らして状態に応じた通知を送る
    STATE=$(detect_claude_state)
    case "$STATE" in
        "permission")
            send_notification "⏸️ 許可待ち" "コマンドの実行許可を待っています" "thinking" 4
            ;;
        "question")
            send_notification "❓ 質問" "Claude Codeが質問しています" "question_mark" 3
            ;;
        "error")
            send_notification "❌ エラー" "エラーが発生しました" "x" 5
            ;;
        "completed")
            send_notification "✅ 完了" "タスクが完了しました" "white_check_mark" 2
            ;;
        "idle")
            send_notification "😴 待機中" "Claude Codeが入力待ちです" "zzz" 2
            ;;
        "working"|"unknown"|*)
            send_notification "💬 Claude Code" "$NOTIFY_MESSAGE" "speech_balloon" 3
            ;;
    esac
    exit 0
fi
