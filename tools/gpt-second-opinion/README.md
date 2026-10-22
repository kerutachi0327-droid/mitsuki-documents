# GPT セカンドオピニオン（Claude Code → GPT 連携）

Claude Code の作業中に「GPTにも見てもらって」と頼むと、Mac にある OpenAI 公式 Codex CLI を **ChatGPT 有料プランのログインのまま**（API キーなし・追加費用なし）呼び出し、GPT の意見を Claude が整理して返します。

- 読み取り専用・1回だけ・空の一時フォルダで実行（GPT にファイル操作やコマンド実行はさせない）
- メール・電話番号を検出したら送信中止
- 利用上限・未ログイン・タイムアウトは終了コードで判別して案内

調査と検証の経緯は `_分析結果/claude_gpt連携/` を参照してください。

## セットアップ（Mac・初回のみ・約10分）

1. **ChatGPT の学習設定を OFF**: chatgpt.com → 設定 → データコントロール →「すべての人のためにモデルを改善する」を OFF。あわせてクレジットの自動リロードが OFF か確認。
2. **Codex CLI を入れる**（ターミナルで）
   ```bash
   brew install --cask codex      # Homebrew がない場合: curl -fsSL https://chatgpt.com/codex/install.sh | sh
   codex --version
   ```
   ※ `npm install -g codex` は別物です（npm なら `@openai/codex`）。
3. **ログイン（必ずご本人が操作）**
   ```bash
   codex login
   ```
   ブラウザで ChatGPT にサインイン。パスワードや `~/.codex/auth.json` の中身は Claude に渡さないでください。
4. **スキルを配置**（このリポジトリのフォルダで）
   ```bash
   bash tools/gpt-second-opinion/install.sh
   ```
5. **動作確認**
   ```bash
   printf '「接続OK」とだけ答えてください。\n' > /tmp/gpt-so-test.md
   ~/.claude/skills/gpt-second-opinion/run.sh /tmp/gpt-so-test.md; echo "終了コード: $?"
   ```
   「接続OK」と終了コード 0 なら成功。2=未導入、3=未ログイン、5=上限、6=タイムアウト。
6. Claude Code を再起動し、「この LINE 配信文を GPT にセカンドオピニオンしてもらって」と頼む。

## 使えないところ

- **claude.ai/code（クラウド）**: OpenAI 系ドメインがネットワークポリシーで拒否されるため不可。Mac ローカルの Claude Code で使ってください。
- **Cowork**: 動くかは未確認。
- `codex mcp-server` を使う古い記事の手順は、現行の Codex CLI（0.163.0）では動きません（サブコマンドが削除済み）。

## 後から足せるもの

- コードレビュー用に OpenAI 公式プラグイン: Claude Code で `/plugin marketplace add openai/codex-plugin-cc` → `/plugin install codex@openai-codex` → `/codex:setup`（review gate は利用枠を急速に消費するので有効にしない）
- クラウドで使う・画像を量産する場合のみ OpenAI API キー（ChatGPT プランとは別の従量課金）
