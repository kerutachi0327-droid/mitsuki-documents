#!/bin/bash
# gpt-second-opinion: Claude Code から公式 Codex CLI（ChatGPTログイン）を読み取り専用で1回呼ぶ
# 使い方: run.sh <プロンプトファイル> [--model <slug>] [--timeout <秒>]
# 終了コード: 0=成功 2=codex未インストール 3=未ログイン/認証切れ 4=個人情報らしき文字列を検出
#             5=利用上限到達 6=タイムアウト 64=引数エラー 1=その他
# macOS 標準の bash 3.2 / BSD ユーティリティ / perl で動く書き方にしている。
set -u

PROMPT_FILE="${1:-}"
if [ -z "$PROMPT_FILE" ] || [ ! -f "$PROMPT_FILE" ] || [ ! -r "$PROMPT_FILE" ] || [ ! -s "$PROMPT_FILE" ]; then
  echo "[gpt-so] プロンプトファイルを指定してください（存在する空でない通常ファイル）" >&2; exit 64
fi
shift
MODEL=""
TIMEOUT_SEC="${GPT_SO_TIMEOUT:-300}"
while [ $# -gt 0 ]; do
  case "$1" in
    --model)
      if [ $# -lt 2 ] || [ -z "$2" ]; then echo "[gpt-so] --model には slug を指定してください" >&2; exit 64; fi
      MODEL="$2"; shift 2 ;;
    --timeout)
      if [ $# -lt 2 ]; then echo "[gpt-so] --timeout には秒数を指定してください" >&2; exit 64; fi
      TIMEOUT_SEC="$2"; shift 2 ;;
    *) echo "[gpt-so] 不明なオプション: $1" >&2; exit 64 ;;
  esac
done
case "$TIMEOUT_SEC" in
  ''|*[!0-9]*) echo "[gpt-so] --timeout は 1〜3600 の整数（秒）で指定してください: $TIMEOUT_SEC" >&2; exit 64 ;;
esac
if [ "$TIMEOUT_SEC" -lt 1 ] || [ "$TIMEOUT_SEC" -gt 3600 ]; then
  echo "[gpt-so] --timeout は 1〜3600 の整数（秒）で指定してください: $TIMEOUT_SEC" >&2; exit 64
fi

# 1) 個人情報ガード（メールアドレス・電話番号らしき文字列があれば送らない）
#    perl で全角英数字を半角に正規化（NFKC）してから判定する。+81 表記・空白区切り・括弧も対象。
#    perl が無い環境では grep による半角のみの簡易判定に落とす。
PII_RC=0
if command -v perl >/dev/null 2>&1; then
  perl -CSD -MUnicode::Normalize -ne '
    $_ = NFKC($_); s/[\x{2010}-\x{2015}\x{2212}\x{30FC}\x{FF70}]/-/g;
    if (/[A-Za-z0-9._%+-]+@[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)*\.[A-Za-z]{2,}/) { $m = 10; last }
    if (/(?<![0-9])(?:\+81[-() ]{0,2}0?|0)[0-9]{1,4}[-() ]{0,2}[0-9]{1,4}[-() ]{0,2}[0-9]{3,4}(?![0-9])/) {
      $c = $&; $c =~ s/[^0-9]//g; if (length($c) >= 10 && length($c) <= 12) { $m = 11; last }
    }
    END { exit($m // 0) }' "$PROMPT_FILE" 2>/dev/null
  PII_RC=$?
  # perl 自体が失敗したとき（10/11 以外の非0）は、素通りさせず grep の判定に落とす
  case "$PII_RC" in 0|10|11) ;; *) PII_RC=0; NEED_GREP=1 ;; esac
else
  NEED_GREP=1
fi
if [ "${NEED_GREP:-0}" -eq 1 ]; then
  if grep -Eq '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}' "$PROMPT_FILE"; then PII_RC=10
  elif grep -Eq '0[0-9]{1,4}-[0-9]{1,4}-[0-9]{3,4}|0[5789]0[0-9]{8}' "$PROMPT_FILE"; then PII_RC=11
  fi
fi
if [ "$PII_RC" -eq 10 ]; then
  echo "[gpt-so] メールアドレスらしき文字列を検出したため送信を中止しました。[メール] などに置き換えてください。" >&2; exit 4
fi
if [ "$PII_RC" -eq 11 ]; then
  echo "[gpt-so] 電話番号らしき文字列を検出したため送信を中止しました。[電話] などに置き換えてください（日付の 01-01-2026 形式などを誤検出することがあります）。" >&2; exit 4
fi

# 2) PATH 対策（Claude Code の Bash はログインシェルの PATH を読まないことがある）
PATH="/opt/homebrew/bin:/usr/local/bin:$HOME/.local/bin:$HOME/.npm-global/bin:$HOME/.volta/bin:$PATH"
for d in "$HOME"/.nvm/versions/node/*/bin; do [ -d "$d" ] && PATH="$d:$PATH"; done
export PATH
CODEX="${CODEX_BIN:-$(command -v codex 2>/dev/null || true)}"
if [ -z "$CODEX" ] || [ ! -x "$CODEX" ]; then
  echo "[gpt-so] codex コマンドが見つかりません。ターミナルで 'brew install --cask codex' などで Codex CLI を導入してください。" >&2; exit 2
fi
case "$CODEX" in /*) ;; *) CODEX="$(cd "$(dirname "$CODEX")" && pwd)/$(basename "$CODEX")" ;; esac

# 3) ログイン確認（ログイン操作そのものは本人がターミナルで行う）
if ! "$CODEX" login status >/dev/null 2>&1; then
  echo "[gpt-so] Codex にログインしていません。ご本人がターミナルで 'codex login' を実行し、ブラウザで ChatGPT にサインインしてください。" >&2; exit 3
fi

# 4) 空の作業フォルダで実行（プロジェクトや会員データのあるフォルダを作業場所にしない）
WORK="$(mktemp -d "${TMPDIR:-/tmp}/gpt-so.XXXXXX")" || exit 1
cp "$PROMPT_FILE" "$WORK/prompt.md" || exit 1
OUT="$WORK/answer.md"
LOG="$WORK/codex.log"
# 送った本文のコピーは終了時に必ず消す（回答とログは残す。成功時はログも消す）
trap 'rm -f "$WORK/prompt.md"' EXIT

# タイムアウト付き実行。timeout / gtimeout が無い macOS では perl で代替する。
# perl 版は子をプロセスグループごと TERM→KILL する（npm 版 codex は node のラッパーが
# 本体を子プロセスとして起動するため、ラッパーだけ止めると本体が残る）。
run_with_timeout() {
  if command -v timeout >/dev/null 2>&1; then timeout -k 10 "$TIMEOUT_SEC" "$@"
  elif command -v gtimeout >/dev/null 2>&1; then gtimeout -k 10 "$TIMEOUT_SEC" "$@"
  else
    perl -e '
      my $t = shift @ARGV;
      my $pid = fork; defined $pid or die "fork failed: $!\n";
      if ($pid == 0) { setpgrp(0, 0); exec @ARGV or do { print STDERR "exec failed: $!\n"; exit 127 } }
      $SIG{ALRM} = sub { kill "TERM", -$pid; sleep 5; kill "KILL", -$pid; waitpid($pid, 0); exit 124 };
      $SIG{TERM} = $SIG{INT} = $SIG{HUP} = sub { kill "TERM", -$pid; waitpid($pid, 0); exit 143 };
      alarm $t; waitpid($pid, 0); alarm 0;
      my $s = $?; exit(($s & 127) ? 128 + ($s & 127) : ($s >> 8));
    ' "$TIMEOUT_SEC" "$@"
  fi
}

ARGS=(exec -s read-only --ephemeral --skip-git-repo-check --color never -C "$WORK" -o "$OUT")
# 文章レビューにはコマンド実行も外部連携も不要なので、既定で止める（読み取り専用でもディスクは読めるため）。
# GPT_SO_HARDEN=0 で無効化できる。0.163.0 で機能名の存在を確認済み（モデル応答時の挙動は未検証）。
HARDEN=(--disable shell_tool --disable unified_exec --disable apps --disable browser_use --disable computer_use)
if [ "${GPT_SO_HARDEN:-1}" = "1" ]; then ARGS+=("${HARDEN[@]}"); fi
if [ -n "$MODEL" ]; then ARGS+=(-m "$MODEL"); fi
ARGS+=(-)

( cd "$WORK" && run_with_timeout "$CODEX" "${ARGS[@]}" < "$WORK/prompt.md" ) > "$LOG" 2>&1
RC=$?
# 将来のバージョンで機能名が無くなった場合（起動直後に失敗し、本文は未送信）は、制限なしで1回だけやり直す
if [ $RC -ne 0 ] && [ "${GPT_SO_HARDEN:-1}" = "1" ] && grep -q "Unknown feature flag" "$LOG"; then
  echo "[gpt-so] 注意: この codex では一部の制限オプションが使えないため、制限なしで再実行します。" >&2
  ARGS=(exec -s read-only --ephemeral --skip-git-repo-check --color never -C "$WORK" -o "$OUT")
  if [ -n "$MODEL" ]; then ARGS+=(-m "$MODEL"); fi
  ARGS+=(-)
  ( cd "$WORK" && run_with_timeout "$CODEX" "${ARGS[@]}" < "$WORK/prompt.md" ) > "$LOG" 2>&1
  RC=$?
fi

if [ $RC -eq 0 ] && [ -s "$OUT" ]; then
  rm -f "$LOG"
  echo "[gpt-so] OK  回答ファイル: $OUT"
  echo "----- GPT の回答 -----"
  cat "$OUT"
  exit 0
fi
if [ $RC -eq 124 ] || [ $RC -eq 137 ] || [ $RC -eq 142 ]; then
  echo "[gpt-so] ${TIMEOUT_SEC}秒でタイムアウトしました。対象を短くするか --timeout を延ばしてください。ログ: $LOG" >&2; exit 6
fi
# 判定用に、ログから送った本文と同じ行を取り除く（codex はログに本文を表示するため）
DIAG="$(grep -vxF -f "$WORK/prompt.md" "$LOG" 2>/dev/null || true)"
if printf '%s\n' "$DIAG" | grep -Eiq "hit your usage limit|usage limit|rate limit exceeded|limit reached|purchase more credits" \
   || printf '%s\n' "$DIAG" | grep -Ei 'error|warn' | grep -Eiq '429|too many requests|quota|credits'; then
  echo "[gpt-so] ChatGPT プランの利用上限に達した可能性があります。リセットを待つか、ターミナルで codex を起動して /status で残量を確認してください（クレジットの追加購入はご本人の判断で）。ログ: $LOG" >&2; exit 5
fi
if printf '%s\n' "$DIAG" | grep -Eiq "not logged in|access token could not be refreshed|sign in again|log out and sign in|refresh_token_reused|no codex credentials" \
   || printf '%s\n' "$DIAG" | grep -Ei 'error|warn' | grep -Eiq '401|unauthorized|re-?authenticate'; then
  echo "[gpt-so] 認証が切れている可能性があります。ご本人がターミナルで 'codex login' をやり直してください。ログ: $LOG" >&2; exit 3
fi
if [ $RC -eq 0 ]; then
  echo "[gpt-so] codex は終了しましたが回答が空でした。ログ末尾:" >&2
else
  echo "[gpt-so] 失敗しました（終了コード $RC）。ログ末尾:" >&2
fi
printf '%s\n' "$DIAG" | tail -n 30 >&2
exit 1
