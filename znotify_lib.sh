#!/bin/bash
# znotify_lib.sh — znotify 要約タグ抽出の共通ライブラリ
#
# zcode_notify.sh（Stop hook・通知用）と znotify（デバッグCLI）の両方から
# source される。抽出ロジックを一元化し、修正が片方に偏るのを防ぐ。
#
# 使い方:
#   source /path/to/znotify_lib.sh
#   summary=$(printf '%s' "$text" | extract_znotify)
#
# 抽出対象のタグ形式（以下の揺れ全てに対応）:
#   正:  <!--znotify>要約</znotify-->
#   揺1: <!--znotify>要約-->          （終了タグ省略）
#   揺2: <!--znotify-->要約-->        （開始タグが自己閉じ ← GLM-5.2 で多発）
#   揺3: <!--znotify>要約</znotify>   （終了タグの -- 省略）
#
# 注意: macOS BSD sed は ERE で `--?`（連続ハイフンの省略）を正しく解釈しない。
#   代わりに `-{0,2}` を使う（BSD sed は interval 式をサポート）。

# ZCode hook 実行環境は最小 PATH の場合があり、sed/grep が見つからないと
# 粛々と失敗するため、標準パスを明示的に確保。
export PATH="/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:${PATH:-}"
export LANG="${LANG:-ja_JP.UTF-8}"
export LC_ALL="${LC_ALL:-ja_JP.UTF-8}"

# extract_znotify — 標準入力のテキストから znotify 要約を抽出して stdout へ。
# タグ無し・抽出失敗時は何も出力しない（空文字）。
# 呼出元は [ -n "$result" ] で成否を判定すること。
extract_znotify() {
    local text
    text=$(cat)
    [ -z "$text" ] && return 0
    # タグ自体が無い場合は sed が本文全体を残してしまうため、grep で事前チェックし
    # 何も出力しない（呼出元でフォールバックに委譲）。
    printf '%s' "$text" | grep -q '<!--znotify' || return 0
    # 開始タグ（<!--znotify> or <!--znotify-->）より後ろを取り、
    # 末尾の終了タグ（</znotify--> / </znotify> / -->）を削除して本文を得る。
    # 本文は1文・60字以内で --> を含まないため、貪欲一致で安全。
    # 改行もまたぐよう正規化。BSD tr は不正バイト列で Illegal byte sequence を
    # 出すため LC_ALL=C でバイト単位処理に退避（出力文字化けは起きない）。
    printf '%s' "$text" | LC_ALL=C tr '\n' ' ' \
        | sed -E 's/.*<!--znotify-{0,2}>//' \
        | sed -E 's/[[:space:]]*<\/?znotify-{0,2}>$//; s/[[:space:]]*-->$//; s/[[:space:]]+$//'
}

# セッションIDから rollout jsonl のパスを返す。存在しない場合は空文字。
# 引数: $1 = セッションID（sess_xxx 形式）
rollout_path() {
    local sid="$1"
    [ -z "$sid" ] && return 0
    local path="$HOME/.zcode/cli/rollout/model-io-${sid}.jsonl"
    [ -f "$path" ] && printf '%s' "$path"
}

# 最新（mtime順）の rollout jsonl パスを返す。
latest_rollout_path() {
    ls -t "$HOME"/.zcode/cli/rollout/model-io-*.jsonl 2>/dev/null | head -1
}
