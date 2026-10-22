# 03c 顧客・ユーザー視点リサーチ：制約とリスク（I2 / I3 / I5 中心）

調査日: 2026-10-22／担当: 顧客・ユーザー（ChatGPT有料プランのみ・Mac・非エンジニア寄りの事業者）

## 0. 調査方法と信頼度の注意（必読）
- この環境からは openai.com / developers.openai.com / help.openai.com へ**直接アクセスできなかった**（DNS解決不可・curl 000）。OpenAI公式ページの内容は **WebSearch の検索結果要約（公式URL付き）経由**で確認しており、本文の逐語確認はしていない。重要な数値や条文はユーザーのMacで公式ページを開いて再確認すること。
- 直接取得できたもの: GitHub `openai/codex` README・docs/install.md、npm registry（`@openai/codex`）、Anthropic公式（code.claude.com / support.claude.com）。
- 表記: **[事実]** 出典で確認できたこと／**[示唆]** 事実からの推論・提案／**[未確認]** 確認できなかったこと。

---

## 1. I2 規約・リスク

### 1-1. Codex CLI を ChatGPT ログインで他エージェント（Claude Code）から非対話で呼ぶこと
- [事実] 非対話実行は公式機能。`codex exec`（短縮 `codex e`）は「人の操作なしで完了すべきスクリプト／CI的な実行」用で、進捗は stderr、最終メッセージのみ stdout に出る。 — https://developers.openai.com/codex/noninteractive
- [事実] 自動化では **APIキーが既定（推奨）**。ChatGPT管理の認証は「自分の Codex アカウントとして実行する必要がある場合」向けの advanced 扱い。公開/OSSリポジトリでの利用は非推奨と明記。 — https://developers.openai.com/codex/noninteractive , https://developers.openai.com/codex/auth/ci-cd-auth
- [事実] ChatGPT認証のCI運用ガイドでは「auth.json は runner（または直列化したワークフロー）ごとに1つ」「**同時実行ジョブや複数マシン間で共有しない**」「Codex が約8日ごとにトークンを自動更新し auth.json に書き戻す」。 — https://developers.openai.com/codex/auth/ci-cd-auth
- [事実] OpenAI は2026年に「Sign in with ChatGPT」を第三者ツール向けに公式化。Go/Plus/Pro 等のプラン利用枠を他アプリで使え、**アプリごとに週上限を設定可能**、上限到達で停止（勝手に課金されない。クレジット利用は明示許可時のみ）。対応OSSとして OpenClaw / OpenCode / Pi / T3 などが挙がる。 — https://help.openai.com/en/articles/20001542-using-your-chatgpt-plan-in-other-apps-and-sites , https://developers.openai.com/siwc
  - [未確認] **Claude Code が公式パートナー/対応アプリに含まれるかは確認できず**（含まれない可能性が高い）。ただし本件は「Claude Code が公式 Codex CLI バイナリを Bash で起動する」形であり、Codex 自体は公式クライアント。
- [事実] Sign in with ChatGPT 開発者規約では、ChatGPTプラン利用枠の **プール・譲渡・転売・贈与、ある利用者のサブスクで他人のリクエストを処理すること** を禁止。 — https://openai.com/policies/sign-in-with-chatgpt-terms/
- [事実（二次情報）] 2026年8月、個人サブスクを「sub2api」等で共有APIとして再配信する使い方は「サポート外で不正検知に引っかかる」と Codex 責任者が発言したと報道。一方、公式クライアントや対応OSSで自分のアカウントの枠を使うのはサポートされる経路とされる。 — https://0dev.duckdns.org/en/posts/openai-clarifies-codex-limits-subscription-to-api-sharing-triggers-anti-fraud-systems , https://explainx.ai/blog/codex-usage-limits-sub2api-sign-in-chatgpt-august-2026 （一次ソース未確認）
- [示唆] **本人が自分のMac上で、公式 Codex CLI を自分のChatGPTアカウントで、自分の業務のために `codex exec` で呼ぶ**のは、公式ドキュメントが想定する範囲（自分のアカウントとして実行・自分のレート上限を使う）に収まり、リスクは低いと判断できる。明文で「Claude Code から呼んでよい」とは書かれていないため「明示的許可」ではなく「禁止事項に該当しない」という位置づけ。

### 1-2. `codex mcp-server` は廃止（重要・I1/I5にも影響）
- [事実] `codex mcp-server` コマンドと `codex-mcp-server` バイナリは**削除済み**。後継は Codex app server（独自JSON-RPC、MCPではない、実験的）や Codex SDK。Codex が**外部MCPを使う側**（`codex mcp`）は存続。ある公式ページでは削除日を2026-09-05と記載。 — https://developers.openai.com/codex/guides/agents-sdk , https://developers.openai.com/codex/sdk , https://developers.openai.com/codex/app-server
- [示唆] 材料の方式A「`codex mcp-server` を MCP 登録」は**現行版では不可**。Claude Code からは `codex exec` を Bash/Skill で呼ぶ方式が本線。ネット上の古い記事（`claude mcp add codex -- codex mcp-server`）を真似るとつまずく。

### 1-3. 認証情報の他マシン（クラウド）へのコピー
- [事実] 公式認証ドキュメントは、ブラウザのない機械向けに ①デバイスコード認証（beta、`codex login --device-auth`、個人はChatGPTのセキュリティ設定で有効化が必要）②ブラウザのある機械でログインし `~/.codex/auth.json` を scp 等でコピー、を案内。auth.json は**アクセストークンを含むためパスワード同様に扱い、コミット・チケット貼付・チャット共有をしない**よう警告。 — https://developers.openai.com/codex/auth
- [事実] 資格情報の保存先は `cli_auth_credentials_store`（file / keyring / auto / ephemeral）で選択。keyring の場合 auth.json が無いことがある。 — https://developers.openai.com/codex/config-reference , https://developers.openai.com/codex/auth
- [事実] 消費者向け利用規約: 「アカウント認証情報を共有したり、他人にアカウントを利用させてはならず、アカウント上の全行為に責任を負う」。 — https://openai.com/policies/row-terms-of-use/
- [示唆] 自分専用のクラウド環境へ自分の auth.json を置くこと自体は公式手順の範囲。ただし①claude.ai/code の環境は auth.openai.com / chatgpt.com 等がネットワークポリシーで拒否されており（材料記載）許可ドメイン追加が前提、②**環境変数・セットアップスクリプト・リポジトリに auth.json を入れる＝第三者（チームメンバーや漏洩先）が使える状態**になり規約・セキュリティ両面でNG、③Macとクラウドの両方で同じauth.jsonを並行利用するとトークン更新競合で401が起き得る（「複数マシンで共有しない」ルール）。→ **当面Macローカル限定運用を推奨**。
- [事実] claude.ai/code クラウド環境のネットワークは環境設定（Network access／Allowed domains）で変更可能。 — https://code.claude.com/docs/en/cloud-environments#network-access

### 1-4. ブラウザ自動化（chatgpt.com 操作）・非公式APIラッパー
- [事実] OpenAI利用規約の禁止事項に「**自動的またはプログラム的にデータやOutputを抽出すること**」がある。 — https://openai.com/policies/terms-of-use/ （本文は検索要約経由で確認）
- [事実（二次情報）] 非公式のサブスク→OpenAI互換API変換プロキシ（CLIProxyAPI等）は、非公開でバージョン管理されないバックエンドに依存し、規約違反・アカウント措置のリスクがあると各所で指摘。 — https://zylos.ai/research/2026-07-13-subscription-auth-boundaries-official-cli-agent-automation , https://braindetox.kr/en/posts/subscription_as_api_proxy.html
- [示唆] 方式D（ブラウザ自動化）と「非公式ラッパー」は**規約上グレー〜違反寄り＋UI変更で壊れる**ため、事業アカウント（サロン運営の主要アカウント）では採用しないのが妥当。

### 1-5. Anthropic 側の制約
- [事実] Claude Code の利用は Pro/Max 等は Consumer Terms、Team/Enterprise/API は Commercial Terms、加えて Usage Policy に従う。OAuth（Claudeログイン）は通常利用向けで、第三者が Claude.ai ログインを自製品に組み込む・他人のためにサブスク資格でリクエストを中継することは禁止。 — https://code.claude.com/docs/en/legal-and-compliance
- [未確認] 「Claude Code から外部CLI（他社AI）を呼ぶこと」を直接制限する条項は**見つからなかった**。
- [示唆] Anthropic側の制約は「Claudeの資格情報の扱い」に関するもので、Claude Code が Bash で別ツールを起動すること自体は通常の使い方。実質的な制約なしと見てよい（ただし Usage Policy は行為内容に適用）。
- [事実] MCP登録の公式手順: `claude mcp add [options] <name> -- <command> [args...]`、スコープ local（既定, ~/.claude.json）/ project（.mcp.json, 共有）/ user（全プロジェクト）。確認は `claude mcp list` / `claude mcp get <name>` / セッション内 `/mcp`。Claude Desktop の設定は `claude mcp add-from-claude-desktop` で取り込み可（macOS/WSL）。「接続前にサーバーを信頼できるか確認。外部コンテンツを取得するサーバーはプロンプトインジェクションのリスク」と注意。 — https://code.claude.com/docs/en/mcp

---

## 2. I3（ユーザー視点）プラン別の可否・上限・超過時挙動

| プラン | Codex CLI | 備考 | 出典 |
|---|---|---|---|
| Free ($0) | 可（ローカル利用のみ） | Codex Cloud不可、画像生成不可 | [1][2][5] |
| Go ($8/月) | 可（ローカル・軽量タスク） | Codex Cloud不可。利用可能モデルが限定（上位モデル不可） | [1][2] |
| Plus ($20/月) | 可（Web/CLI/IDE/iOS） | 5時間枠＋週枠あり | [2] |
| Pro ($100/$200/$500) | 可 | 現在**5時間枠なし**、週枠は適用あり得る | [2] |
| Business ($20/人/月 年払い, 2名〜) | 可 | 既定で学習に使われない | [2][6] |

- [事実] Plus の目安（ローカルメッセージ/5時間）: GPT-6 Astra で約5–45、GPT-6.1 Sol で約15–160（Business Standard 同等）。あくまで推定値で、モデル・タスクで大きく変動。古い版のページの数値（例: Plus 33–168）は旧情報。 — [2] https://developers.openai.com/codex/pricing （検索要約経由。モデル名・数値は**要実画面確認**）
- [事実] Codex・ChatGPT Work・ChatGPT for Excel 等は**共通の利用枠/クレジットプール**を共有。つまり Claude から呼ぶ Codex の消費は、普段の ChatGPT 上の「Work/Codex」系利用と同じ枠を食う。 — [1] https://help.openai.com/en/articles/11369540-using-codex-with-your-chatgpt-plan
- [事実] 上限到達時: 実行中のターンは（フェアユース範囲で）完了できる → その後は「リセットを待つ／保有リセットを使う／クレジット購入（Settings > Usage）／アップグレード」。クレジットは**プラン枠を使い切った後にのみ消費**。自動リロード設定あり。Plus/Pro 個人は有料の即時リセット購入可（週枠到達時に提示、返金不可）。 — https://help.openai.com/en/articles/12642688-using-credits-for-flexible-usage-in-chatgpt-personal-plans , https://help.openai.com/en/articles/20001507-paid-weekly-work-and-codex-rate-limit-resets , https://help.openai.com/en/articles/20001498-how-banked-codex-resets-work
- [事実] 残量確認は CLI 内で `/status`。 — https://help.openai.com/en/articles/11369540-codex-usage-limits （検索要約）
- [事実] Codex内の画像生成は gpt-image-2 を使い**一般の Codex 利用枠を消費**、CLIでも可（`$imagegen`）。Freeでは不可。ChatGPT側の画像回数制限とは別。 — https://developers.openai.com/codex/image-generation
- [示唆] 「1日数十回のセカンドオピニオン/文章レビュー」は Plus で概ね収まる可能性が高いが、長文資料＋上位モデル＋高推論だと5時間枠に当たり得る。**自動リロード（クレジット自動購入）はOFFのまま**にしておくと想定外課金を防げる。Goは対応範囲・モデルが限定的で、業務利用なら Plus 以上が無難。

出典番号: [1] https://help.openai.com/en/articles/11369540-using-codex-with-your-chatgpt-plan [2] https://developers.openai.com/codex/pricing [5] https://developers.openai.com/codex/image-generation [6] https://help.openai.com/en/articles/8542115-chatgpt-business-general-faq
- [未確認] ユーザー（ケンティー）が現在どのプランか。Go のCLI対応については二次情報で「デスクトップアプリのみ」とする記事もあり食い違い（公式要約ではCLIも可）。

---

## 3. I5（ユーザー視点）Mac セットアップのつまずきポイント

### 事実
- インストール方法（公式README）: ①`curl -fsSL https://chatgpt.com/codex/install.sh | sh`（スタンドアロン、Node不要）②`npm install -g @openai/codex` ③`brew install --cask codex`。 — https://github.com/openai/codex/blob/main/README.md
- 要件: macOS 12+、RAM 4GB以上（8GB推奨）。 — https://github.com/openai/codex/blob/main/docs/install.md
- npm版 `@openai/codex` 最新 0.163.0、engines は `node >=16`（npm registry 実測）。 — https://registry.npmjs.org/@openai/codex/latest
- ログイン: `codex` 初回起動で「Sign in with ChatGPT」を選ぶ／`codex login` でブラウザOAuth。ブラウザが使えない場合 `codex login --device-auth`（beta）。 — https://github.com/openai/codex/blob/main/README.md , https://developers.openai.com/codex/auth
- Codex は ChatGPT デスクトップアプリ（macOS）にも統合済み（2026年7月）。 — https://developers.openai.com/codex/changelog
- Claude Desktop/Cowork: 公式サポート記事間で記述が食い違う。「claude_desktop_config.json で設定したローカルMCPは Cowork / claude.ai では使えない」とする記事と、「ローカルMCPを参照するプラグインは Cowork と Claude Code で動く（chatでは不可）」とする記事がある。 — https://support.claude.com/en/articles/11175166-get-started-with-custom-connectors-using-remote-mcp , https://support.claude.com/en/articles/11725091-when-to-use-desktop-and-web-connectors
- Claude Code のサンドボックスはシェルコマンドが対象。ローカルMCPサーバー等は利用者の権限で動く。 — https://code.claude.com/docs/en/sandboxing （検索要約）

### 非エンジニアがつまずく点（示唆）
1. **パッケージ名の取り違え**: npm の `codex`（無関係の古いパッケージ）を入れてしまう → 必ず `@openai/codex`。（二次情報: https://www.verdent.ai/guides/install-codex-cli-mac-windows-linux ）
2. **`command not found`**: Homebrew の bin（Apple Silicon は `/opt/homebrew/bin`）や nvm 配下の npm グローバルが PATH に無い。Claude Code の Bash は別シェル設定で起動することがあり、ターミナルでは動くのに Claude からは見つからない、が起きやすい → `which codex` の絶対パスを Skill に書くのが確実。（二次情報: https://codex.danielvaughan.com/2026/04/08/installing-codex-cli/ ）
3. **Node不要ルートを選ぶ**: Node/npm に不慣れなら Homebrew cask かスタンドアロンinstallerが簡単。
4. **ログインはユーザー本人が1回だけ対話で**: ブラウザでのChatGPTログインは Claude に代行させない（認証情報をAIに渡さない）。
5. **`codex exec` の承認/サンドボックス設定**: 非対話時に書き込み・ネットワーク許可をどう与えるか（読むだけのレビュー用途なら読み取り専用で十分）。[未確認] 具体フラグ名は公式CLIリファレンス（https://developers.openai.com/codex/cli/reference ）で要確認。
6. **Cowork から使えるかは不確実**: 上記の通り公式記述が割れているため、**Claude Code（ターミナル or Desktop の Code タブ）から使う前提で設計**し、Coworkは実機確認後に判断。
7. **クラウド（claude.ai/code）では動かない前提**: OpenAI系ドメインが403。許可ドメイン追加＋auth.json持ち込みが必要で、1-3のリスクがある。

---

## 4. データ取り扱い（顧客個人情報）

### 事実
- 個人プラン（Free/Plus/Pro、Goも個人プラン）では会話がモデル改善に使われ得る。ChatGPTの「**Improve the model for everyone（すべての人のためにモデルを改善する）**」をOFFにすると新しい会話は学習に使われない。**個人プランでは同じ設定が Codex のタスクにも適用**。Privacy Portal の「Do not train on my content」でも可。 — https://help.openai.com/en/articles/7730893-data-controls-in-chatgpt , https://help.openai.com/en/articles/11369540-using-codex-with-your-chatgpt-plan
- 設定場所: Web はアカウントメニュー → Settings → Data controls。ログイン中はアカウント単位で全デバイスに適用。 — https://help.openai.com/en/articles/7730893-data-controls-in-chatgpt
- Business/Enterprise/API は既定で入力・出力を学習に使わない。 — https://help.openai.com/en/articles/11369540-using-codex-with-your-chatgpt-plan , https://help.openai.com/en/articles/8542115-chatgpt-business-general-faq
- 個人情報保護委員会（2023/6/2）の注意喚起: 個人情報取扱事業者がプロンプトに個人情報を含める場合は**利用目的の範囲内か確認**、本人同意なく個人データを入力し応答以外の目的で扱われると法違反のおそれ → **提供事業者が入力を機械学習に使わないこと等を確認**すること。 — https://www8.cao.go.jp/cstp/ai/ai_team/6kai/shiryouchuuikanki.pdf （内閣府掲載の同資料）
- [未確認] 学習OFF時の Codex 入力の保持期間（不正監視目的の一時保持の日数）は Codex 固有の記載を確認できず（一時チャットは最大30日保持と記載あり: https://help.openai.com/en/articles/7730893-data-controls-in-chatgpt ）。

### 示唆
- 導入前に**学習OFFを必ず設定**（チェックリスト化）。
- サロン会員の氏名・メール・LINE ID・購入履歴などは**原則 GPT に送らない**。Claude 側で匿名化（「会員A」「xxx@…」等へ置換）してから渡すルールを Skill/CLAUDE.md に明記。Claude（Anthropic）と OpenAI の**2社に個人データが渡る**構成になる点も意識。
- `codex exec` はカレントディレクトリのファイルを読める。**会員リストCSV等があるフォルダで実行しない**（専用の空フォルダ or 一時ファイルで実行）。
- 外国にある第三者への提供（個人情報保護法）やプライバシーポリシーへの記載要否は[未確認]。顧客データを送る運用にするなら専門家確認を推奨。

---

## 5. まとめ（ユーザーに伝えるべきリスク順）
1. `codex mcp-server` は廃止済み → `codex exec` を Bash/Skill で呼ぶ方式が現実解。
2. 本人のMacで公式CLIを自分のアカウントで使う＝規約上の低リスク経路。ブラウザ自動化・非公式ラッパー・アカウント/auth.json共有は避ける。
3. 枠はChatGPTの Work/Codex と共有。超過時は待つかクレジット購入。自動リロードOFF推奨。
4. 学習OFF設定と、個人情報を送らない運用ルールが前提。
5. クラウド（claude.ai/code）とCoworkは不確実／制約大 → Mac の Claude Code 限定で開始。
