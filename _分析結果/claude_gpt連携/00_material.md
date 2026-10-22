# 材料ファイル：Claude → GPT 連携の実現

## 依頼
ユーザー（ケンティー）: 「ClaudeとGPTの連携を実現」
確認済み回答:
- 方向: **ClaudeからGPTを呼ぶ**（Claude Code の作業中に GPT をセカンドオピニオン・文章生成・画像生成などで使う）
- GPT側の環境: **ChatGPT有料プランのみ（OpenAI APIキーなし）**

## ユーザーの環境（判明している事実）
- 主作業環境: Mac（/Users/macbookpro_ko/Documents/Claude/Projects/EC基盤構築ビジネス/…）。Claude Code / Cowork（Claude Desktop）を利用。
- このクラウドセッション（claude.ai/code リモート環境）では api.openai.com / chatgpt.com / auth.openai.com が**ネットワークポリシーで403拒否**。npm registry は可（@openai/codex 最新 0.163.0 が取得可能）。
- 業務: みつき「Secret TeaRoom」オンラインサロン運営（UTAGE＝ファネル/LINE配信/会員サイト、Googleスプレッドシート、Instagram、静的HTML資料を Cloudflare Pages で公開）。Claude Code から UTAGE MCP、Gmail、Google Sheets、Notion 等を使用。
- 作業スタイル: 5段パイプライン（材料→イシュー→並列リサーチ×3→ストラテジスト→レビュー）。サブエージェント多用。日本語。非エンジニア寄りの事業者だが Claude Code は日常利用。
- リポジトリ: kerutachi0327-droid/mitsuki-documents（静的HTML、Cloudflare Pages）。

## 想定される実現方式（仮説・要検証）
A. OpenAI Codex CLI を「Sign in with ChatGPT」でログインし、Claude Code から `codex exec` を Bash で呼ぶ／`codex mcp-server` を MCP として登録（ChatGPTプランの枠内で GPT 系モデルを利用できる可能性）
B. OpenAI API キーを別途取得（従量課金）し、MCPサーバー or スクリプト経由で Claude から呼ぶ
C. 既存のコミュニティ製 MCP（例: "ask GPT"系、zen/pal-mcp-server 等の multi-model）を利用
D. ブラウザ自動化で chatgpt.com を操作（規約・安定性リスク）
E. 手動コピペ運用（連携ではない・比較の下限）

## 判断に必要な論点（Step2で構造化）
- ChatGPT有料プランだけで、Claude から GPT をプログラム的に呼べるか（規約・技術）
- 各方式のコスト、セットアップ難度、Mac での手順、安定性、規約適合性
- 画像生成（gpt-image系）がプランで使えるか
- クラウドセッション（本環境）で使えるか／Macローカル限定か

## Step2 イシュー構造（主論点：ChatGPT有料プランのみの状態で、Claude Code から GPT を実用的・規約適合的に呼ぶ最善の方式は何か）
I1. 実現可能性: ChatGPTプラン認証で Claude から GPT を呼べる公式経路はあるか（Codex CLI の ChatGPT ログイン、`codex exec`、`codex mcp-server`、利用可能モデル、レート上限）。2026年10月時点の最新事実で。
I2. 規約・リスク: Codex CLI を他エージェント（Claude Code）から非対話で呼ぶことは OpenAI 利用規約上許容か。ブラウザ自動化・非公式APIラッパーのリスク。
I3. コスト比較: ChatGPTプラン内利用 vs API従量（代表的な使い方＝1日数十回のセカンドオピニオン/文章レビュー で月額いくら）。
I4. 機能範囲: テキスト（セカンドオピニオン/文章生成/コードレビュー）、画像生成、Web検索がそれぞれどの方式で可能か。
I5. 導入手順: Mac での具体手順（インストール→ログイン→Claude Codeへ登録→動作確認）、および claude.ai/code クラウド環境で使う場合の条件（ネットワーク許可ドメイン、認証情報の持ち込み可否）。
I6. 運用設計: Claude Code 側の呼び出し口（Skill / スラッシュコマンド / MCP / CLAUDE.md ルール）をどう作ると日常業務（みつき案件の文章・提案資料レビュー等）で使いやすいか。

## ローカル実機確認（このクラウド環境で @openai/codex 0.163.0 をnpm導入して確認。認証・API呼出しは未実施＝ネットワーク拒否のため）
- `codex exec` あり（非対話。stdin入力可、`-m/--model`、`-s read-only|workspace-write|danger-full-access`、`-i/--image`、`--json`、`-o/--output-last-message <FILE>`、`--output-schema`、`--ephemeral`、`--skip-git-repo-check`、`-C/--cd`）
- `codex review` あり（非対話コードレビュー）
- `codex login` に `--device-auth`（デバイスコード方式）、`--with-api-key`、`--with-access-token`、`status` サブコマンドあり
- **`codex mcp-server` サブコマンドは 0.163.0 のトップレベルヘルプに表示されない**（`codex mcp` は「Codexが外部MCPを使う」側の管理）。代わりに `app-server`/`exec-server`（experimental）が存在。→ 古い記事の `claude mcp add codex -- codex mcp-server` が現行版で動くかは要確認
