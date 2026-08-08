#!/bin/bash
# ZCode Stop hook: 当該セッションのロールアウト jsonl から直近のユーザー向け応答を取り出し、
# 応答末尾に埋め込まれた要約タグ <!--znotify>...</znotify--> を抽出して notify_if_absent.sh に渡す。
# タグが無ければ固定文「ZCode応答」にフォールバック（LLM がタグ出力を忘れても通知は止まらない）。
#
# 呼出元: ~/.zcode/cli/config.json の hooks.events.Stop
#   ZCode はテンプレート変数 ${CLAUDE_SESSION_ID} を環境変数として注入する。
#   config.json 側で「... &」付きコマンドにしてバックグラウンド起動する
#   （ZCode hooks はインライン実行のため、音再生/ntfy送信でブロックしないよう分離）。
#
# ロールアウト jsonl 仕様（実測）:
#   パス: ~/.zcode/cli/rollout/model-io-${sessionId}.jsonl
#   1行 = 1 model_io レコード。ユーザー向けテキスト応答は response.finishReason=="stop" の行の
#   response.text に入る（ツール呼び出しの中間ターンは finishReason=="tool-calls"）。
#   よって stop 行を末尾から探す = 直近のユーザー向け応答。
#
# 並列安全性: セッションID単位でファイルが分かれるため、複数 ZCode 同時実行でも競合しない。
#
# 注意: PATH/LANG/LC_ALL 設定と要約タグ抽出ロジックは znotify_lib.sh に共通化。
# znotify デバッグCLI と同じ関数を使うため、修正が片方に偏らない。

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# 共通ライブラリ（PATH/LANG 設定 + extract_znotify 関数）
# shellcheck source=znotify_lib.sh
. "$SCRIPT_DIR/znotify_lib.sh"

# ZCode が注入するセッションID（ファイル名の sess_<id> と一致）
SID="${CLAUDE_SESSION_ID:-${ZCODE_SESSION_ID:-}}"
ROLLOUT_DIR="$HOME/.zcode/cli/rollout"
ROLLOUT="$ROLLOUT_DIR/model-io-${SID}.jsonl"

TITLE="${NOTIFY_TITLE:-💬 ZCode}"
MSG="ZCode応答"   # フォールバック本文

if [ -n "$SID" ] && [ -f "$ROLLOUT" ]; then
    # 末尾から走査し、直近の finishReason=stop 行の response.text を取り出す。
    # macOS には tac が無いため tail -r で逆順化。grep -m1 で最初の(=最新の)stop 行で停止。
    TEXT="$(tail -r "$ROLLOUT" 2>/dev/null \
        | grep -m1 '"finishReason":"stop"' \
        | jq -r '.response.text // empty' 2>/dev/null || true)"

    if [ -n "$TEXT" ]; then
        # 共通ライブラリの extract_znotify で要約タグを抽出。
        # タグ揺れ（自己閉じ形式など）の吸収は znotify_lib.sh に一元化。
        # 抽出失敗時は空文字が返り、MSG はデフォルト「ZCode応答」のまま。
        SUMMARY="$(printf '%s' "$TEXT" | extract_znotify)"
        [ -n "$SUMMARY" ] && MSG="$SUMMARY"
    fi
fi

# 在席判定＋不在通知は既存の notify_if_absent.sh に委譲（センサー/ntfy/音は共通インフラ）
NOTIFY_TITLE="$TITLE" NOTIFY_MSG="$MSG" "$SCRIPT_DIR/notify_if_absent.sh"
