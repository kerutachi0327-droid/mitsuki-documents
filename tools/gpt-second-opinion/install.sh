#!/bin/bash
# gpt-second-opinion スキルを ~/.claude/skills/ に配置する（Mac 用）
# 使い方: bash tools/gpt-second-opinion/install.sh
set -eu

SRC="$(cd "$(dirname "$0")" && pwd)"
DEST="$HOME/.claude/skills/gpt-second-opinion"

mkdir -p "$DEST"
cp "$SRC/SKILL.md" "$SRC/run.sh" "$DEST/"
chmod +x "$DEST/run.sh"
echo "配置しました: $DEST"

PATH="/opt/homebrew/bin:/usr/local/bin:$HOME/.local/bin:$PATH"
if ! command -v codex >/dev/null 2>&1; then
  echo "次に Codex CLI を入れてください: brew install --cask codex"
elif ! codex login status >/dev/null 2>&1; then
  echo "次にターミナルで 'codex login' を実行し、ブラウザで ChatGPT にサインインしてください。"
else
  echo "Codex CLI 導入済み・ログイン済みです。Claude Code を再起動すると使えます。"
fi
