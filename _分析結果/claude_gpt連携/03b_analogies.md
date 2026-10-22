# 03b アナロジー事例：Claude Code × GPT/Codex 連携の実例・運用パターン（論点 I5 / I6 中心）

調査日: 2026-10-22。担当: アナロジー事例リサーチャー。

**調査の制約**: この環境では WebFetch で読めるドメインが限られていました。developers.openai.com、learn.chatgpt.com、zenn.dev、qiita.com、scrapbox.io などは DNS 解決エラーになりました。本文まで読めたのは github.com と code.claude.com のみです。ほかの出典は **検索結果の抜粋（スニペット）経由で確認した内容** で、各所に「（検索抜粋）」と明記しています。本文を読まずに断定したことはありません。

---

## 1. OpenAI 公式：Claude Code 用 Codex プラグイン「codex-plugin-cc」（最重要）

### 事実（出典: https://github.com/openai/codex-plugin-cc の README を本文で確認）
- OpenAI 自身が公開している Claude Code 用プラグインです。
- **インストール手順**（Claude Code 内で実行）:
  ```
  /plugin marketplace add openai/codex-plugin-cc
  /plugin install codex@openai-codex
  /reload-plugins
  /codex:setup          # 導入・認証の確認。npm があれば Codex の導入も提案される
  ```
  手動で入れる場合は `npm install -g @openai/codex`、ログインは `!codex login` です。
- **要件**: README の記載は「ChatGPT subscription (incl. Free) or OpenAI API key」。利用分は Codex の usage limits から消費されます。Node.js 18.18 以上が必要です。
- **認証の再利用**: README の記載は「If you are already signed into Codex on this machine, that account should work immediately here too」。ローカルの Codex CLI 認証と `~/.codex/config.toml`（およびプロジェクトが trusted のときの `.codex/config.toml`）をそのまま使います。
- **主なコマンド**:
  - `/codex:review`: 現在の変更を **read-only** でレビューする。`--base <ref>` / `--wait` / `--background` が使える。観点の指示文は受け付けない。
  - `/codex:adversarial-review`: read-only。設計判断や前提を疑う「反論型」レビューで、観点の指示文を渡せる。
  - `/codex:rescue`: `codex:codex-rescue` サブエージェント経由でタスクを Codex に委譲する。`--background` / `--resume` / `--fresh` / `--model` / `--effort` が使える。
  - `/codex:transfer`: 現在の Claude セッションから Codex スレッドを作り、`codex resume <id>` を表示する。
  - `/codex:status` / `/codex:result` / `/codex:cancel`: バックグラウンドジョブを管理する。
- **Review gate**: `/codex:setup --enable-review-gate` で有効になります。Stop フックが Claude の応答を Codex にレビューさせ、問題があれば停止をブロックします。README は「can create a long-running Claude/Codex loop and may drain usage limits quickly」と警告しています。
- README は長いレビューや rescue について「might take a long time」として、`--background` を推奨しています。

### 事実：既知の不具合（出典: https://github.com/openai/codex-plugin-cc/issues の一覧ページを本文で確認。open は 286 件で、見えたのは1ページ目のみ）
- ハング: #793「task hangs forever at "Starting Codex task thread."」、#781（ジョブが永久にハング）。
- 認証: #789「Long-lived app-server brokers burn the single-use ChatGPT refresh token (refresh_token_reused)」。
- 権限: #798「codex-rescue: unprompted, write-capable delegation by default」（rescue は既定で書き込みできる）。
- Review gate: #790（同じ指摘を何度もブロックし、上限や保留の手段がない）、#796。
- broker プロセスのリークや、別セッションのジョブ中断: #801、#803、#791、#782。
- 使用量: #102（検索抜粋）は、Claude Code 内から Codex の 5時間／週次の上限を確認できないという要望です（https://github.com/openai/codex-plugin-cc/issues/102 ）。

### 示唆
- ChatGPT 有料プランのみのユーザーにとっては、**公式が用意した Claude→Codex の正規ルート** と言えます。カスタム MCP を組むより先に検討すべき第一候補です。
- 文章・提案資料のレビュー用途なら、`/codex:adversarial-review "<観点>"` が「セカンドオピニオン」に最も近い形です。ただし設計は git 差分のレビュー向けです。git 管理されていない文書のレビューがどこまでうまくいくかは **未確認** です。
- review gate は、使用量の消費とループの危険があるため **既定では OFF にするのが妥当** です。rescue は書き込み可能が既定（#798）なので、レビュー目的なら review 系コマンドに限るのが安全です。
- **クラウド（claude.ai/code）では `/plugin` コマンドが使えません**（下記 §5 の公式ドキュメント）。このため、このプラグインは基本的に Mac ローカル用と考えるべきです。

---

## 2. `codex mcp-server` を Claude Code に MCP として登録する実例

### 事実
- **登録コマンドの実例**（検索抜粋）:
  - `claude mcp add --transport stdio codex -- codex mcp-server`: Algomatic Tech Blog の 2026-07-14 の記事。Claude Code 2.1.197 と codex-cli 0.142.4 で、疎通・追質問・議論を検証している。https://tech.algomatic.jp/entry/2026/07/14/160815
  - `claude mcp add --scope user codex -- /opt/homebrew/bin/codex mcp-server`: Homebrew の絶対パスでユーザースコープに登録する例。https://qiita.com/YasuhiroKawano/items/76d255b1fd97548dedc5 （検索抜粋ではこの例と同じ記事群として提示）
  - `.mcp.json` に `"command": "codex", "args": ["mcp-server"]` を置く最小構成: https://qiita.com/harnesswinner/items/996fec8e78a219b5159b 。作業ルールは設定ファイルに入れず、呼び出し側の Skill や依頼文で固定する方針。
- **公開されるツール**: `codex`（新規セッション）と `codex-reply`（threadId を指定して続きを依頼する）の2つ。出典は OpenAI 公式ガイド「Use Codex with the Agents SDK」（検索抜粋）https://developers.openai.com/codex/guides/agents-sdk と Algomatic の記事（検索抜粋）。
- **認証**: OpenAI ドキュメントのミラーとされるページ（検索抜粋）に「The MCP server uses the same authentication as regular Codex: 1. ChatGPT OAuth credentials (if logged in with codex login) 2. API key ...」とある。ただしこれはフォーク上のミラーで、公式原文は **未確認**（https://forge.lthn.ai/core/core-agent-ide/src/commit/167b4f0e254638165191a6162f264cefb4bced79/docs/advanced.md ）。一方、公式 Agents SDK ガイドは前提条件に「OpenAI API key」を挙げている（検索抜粋）。ただしこれは Agents SDK（Python）側に必要なもので、mcp-server 単体が ChatGPT 認証で動くかどうかとは別の話と解釈できる（解釈は示唆）。
- **古い記事との差**: 古い記事には `codex mcp` と書かれており、後から「コマンドが変わった」と追記した Zenn 記事もある（検索抜粋）。https://zenn.dev/tmasuyama1114/articles/cdfd4562bdce78

### 事実：MCP 方式で報告された失敗（検索抜粋）
- **承認待ちのハング**: approval-policy を指定しないと、Codex 内部で unsafe と判定されたコマンド（sort、awk など）が承認待ちになります。MCP 経由では応答できず、ハングします。原因は、Claude Code がサーバーからの入力要求（elicitation）に未対応で、Codex 側がタイムアウトなしで待ち続けるためと説明されています。回避策は `approval-policy: "never"` を明示することです。（Zenn foxytanuki: https://zenn.dev/foxytanuki/articles/9df8e0134ed412 。約250日前の記事なので、現在も同じ挙動かは **未確認**）
- **ブラックボックス化と長時間処理**: MCP ツールの実行中は進捗が見えず、返答も少ない。長時間タスクではタイムアウトや無応答が起きた、という報告があります。https://zenn.dev/owayo/articles/63d325934ba0de 、https://minna-systems.co.jp/test/blog/claude-code-call-codex/
- **タイムアウトの設定項目**: Claude Code 側では、stdio サーバーの起動タイムアウトの既定が30秒で、`MCP_TIMEOUT`（ミリ秒）で延ばせます。Codex 側では config.toml の `startup_timeout_sec` / `tool_timeout_sec` で調整します。出典は https://uravation.com/media/codex-mcp-setup-guide-2026/ ほか（検索抜粋）。
- **前提の曖昧さ**: 詰まった原因は JSON 設定そのものではなく、「Codex CLI の実体、作業ディレクトリ、sandbox / approval policy の前提が曖昧だった」ことだった、という報告があります。https://qiita.com/harnesswinner/items/996fec8e78a219b5159b

---

## 3. `codex exec` を Bash や Skill で包むパターン（MCP からの乗り換え組）

### 事実
- **公式の既定値**: 公式ドキュメント（検索抜粋）は「By default, `codex exec` runs in a read-only sandbox」としています。`--sandbox workspace-write` などで上書きでき、`--json` を付けると stdout が JSONL のイベントストリームになります。https://developers.openai.com/codex/noninteractive
- **最終メッセージのファイル出力**: `--output-last-message` で最終メッセージをファイルに書き出せます。出典はサードパーティの JSR ドキュメント（検索抜粋）https://jsr.io/@zuke/codex/doc 。`--json` と組み合わせたときの挙動は **未確認** です。
- **headless での承認**: `codex exec` は承認ポリシーが既定で Never 相当で、境界に当たると止まらず失敗します。Claude Code の `--max-turns` に当たるターン上限はないため、外側で `timeout 3600 codex exec ...` のように壁時計で上限を付ける例があります（サードパーティ、検索抜粋）。https://agentpatterns.ai/workflows/headless-codex-bounding/ 、https://sharedcontext.ai/skills/external/tobihagemann/codex-exec
- **MCP から Skill に切り替えた評価**（検索抜粋）:
  - Skill にすると Codex をコマンドとして直接実行する形になる。追加の応答を求められたときは `codex exec ... resume <session_id>` で継続する。https://zenn.dev/owayo/articles/63d325934ba0de
  - 「Codex の出力がリアルタイムでターミナルに流れてくる」ので、ブラックボックス感が減る。長時間タスクは `codex exec`、文脈の引き継ぎは `codex exec resume` を推奨。https://www.m-totsu.com/1202/ 、https://zenn.dev/totsu_ai_lab/articles/claude-code-codex-mcp-vs-skill-bash
  - 「codex exec を read-only サンドボックスで呼ぶだけ」のスキルやスラッシュコマンドとして実装した例。https://qiita.com/fuji1009_REBELL/items/2d2e17d9ff9ea717bd8a
  - 「セカンドオピニオン」などの言葉で発動し、レビュー依頼と実装依頼を分けて扱うスキルの例（claude-code-harness / codex-review）。https://playbooks.com/skills/chachamaru127/claude-code-harness/codex-review
  - 計画→承認→実装→検証の4段階を Skill で回す例。https://zenn.dev/yujmatsu/articles/20260205_claude_code_codex_skill
- **「相談する行為そのもの」の価値**: shokai 氏は、手作業のコピペ相談を Agent Skill で置き換えたと書いています。別の論点として、Codex が単に賢いのか、相談という行為自体に価値があるのかも論じています（検索抜粋）。https://scrapbox.io/shokai/Claude_Code%E3%81%8B%E3%82%89Codex_CLI%E3%82%92%E5%91%BC%E3%81%B3%E5%87%BA%E3%81%97%E3%81%A6%E7%9B%B8%E8%AB%87%E3%81%95%E3%81%9B%E3%82%8BAgent_Skill
- **同時編集の回避**: 「同一プロジェクトを2者で回すのであれば」両者に同じファイルを同時に編集させない、という注意があります（検索抜粋）。https://library.libecity.com/articles/01KP9NTRDK6NFVD8VVSC791K2K

### 示唆（I6：運用設計）
- 日本語の実践記事には「**MCP より Skill + `codex exec`（read-only）が安定する**」という傾向がはっきりあります。理由は、進捗が見えること、承認待ちでハングしないこと、`resume` で追質問できること、外側で timeout を付けられることです。
- Claude Code の Bash は既定2分・最大10分で、それを超えるとバックグラウンドに回ります（§5）。このため、セカンドオピニオンでは「入力を絞る」「出力は `--output-last-message` でファイルに書かせ、Claude が要約して読む」形が実務的です（設計案）。
- 非エンジニアの文章レビュー用途での実例は、今回の検索では見つかりませんでした（**未確認**）。ほぼすべてがコードレビューの事例です。

---

## 4. マルチモデル中継 MCP（コミュニティ製）

### 事実
- **pal-mcp-server（旧 Zen MCP）の `clink`**（出典: https://github.com/BeehiveInnovations/pal-mcp-server/blob/main/docs/tools/clink.md を本文で確認）
  - CLI-to-CLI ブリッジ。Gemini（既定）、Claude、Codex をサブエージェントとして起動し、最終結果だけをメインのセッションに返す。
  - Codex のプリセット `codex.json` は、`codex exec` を JSON 出力付きで、**承認とサンドボックスをバイパスするフラグ付きで** 実行する。ドキュメントは「Only enable them in trusted sandboxes」と警告し、フラグを外せば読み取りと報告だけになると書いている。
  - ロールは default / planner / codereviewer。各 CLI の認証方式の詳細は書かれておらず、「Pre-authenticate CLIs」とあるのみ。
- そのほかのラッパー（いずれも非公式。保守状況は **未確認**）:
  - `@cexll/codex-mcp-server`: `claude mcp add codex-cli -- npx -y @cexll/codex-mcp-server`。https://glama.ai/mcp/servers/@cexll/codex-mcp-server/blob/19fbc1b6441f4f8888cf5b45fcb427a379e05632/docs/getting-started.md
  - `codex-as-mcp`: 例として `uvx codex-as-mcp@latest --yolo`。`--yolo` は確認を省略するオプション。https://mcp.so/ja/servers/codex-as-mcp 、https://glama.ai/mcp/servers/kky42/codex-as-mcp
  - `j-token/codex-mcp`: 「No API key required — authenticates via ChatGPT OAuth login」と説明している。https://glama.ai/mcp/servers/j-token/codex-mcp
  - codex-fusion-mcp: Claude が提案し、Codex がレビューし、Claude が調整する流れ。https://glama.ai/mcp/servers/vyf4abons2

### 示唆
- 公式の `codex mcp-server` と codex-plugin-cc があるので、**ChatGPT プランだけを使う前提ならコミュニティ製ラッパーを挟む利点は薄い** です。挟むほど、権限を緩めるフラグ（yolo やサンドボックスのバイパス）の既定値というリスクが加わります。

---

## 5. 非ローカル環境（claude.ai/code クラウド・CI）で ChatGPT 認証の Codex を動かす

### 事実：OpenAI 側（検索抜粋。公式ページは本環境から取得不可）
- **headless への持ち込み**: ブラウザのある機械で `codex login` してから、`~/.codex/auth.json` をコピーする方法が公式に記載されています。OS の資格情報ストアに保存されている場合は `cli_auth_credentials_store = "file"` に切り替えます。https://developers.openai.com/codex/auth
- **CI/CD のガイド**: 自動化には **API キーが推奨**。auth.json の持ち込みは「trusted private automation 向けの advanced option」という位置づけです。記載されている条件は次のとおりです。https://developers.openai.com/codex/auth/ci-cd-auth
  - 1つの auth.json を使うのは1台、または直列のジョブ列だけにする。
  - Codex がファイルを更新するので、更新後のファイルを次回のために保存しておく（「run Codex and persist the updated auth.json」）。
  - 最終リフレッシュから約8日経つと更新され、401 の場合も refresh して再試行する。
  - **公開リポジトリや OSS では使わない**。
  - auth.json はパスワードと同等に扱い、コミットやチャットへの貼り付けをしない。
- **デバイスコード方式**: `codex login --device-auth` は headless 向けです。ただし ChatGPT のセキュリティ設定で事前に有効化する必要があります（サードパーティ、検索抜粋）。https://codex.danielvaughan.com/2026/04/01/codex-cli-authentication-flows-credential-management/
- **個人プランの CI 実例**: クラスメソッドの記事「【個人プラン】Plus / Pro で Codex を CI で動かす」があります（タイトルのみ確認、本文は **未確認**）。https://dev.classmethod.jp/articles/codex-cli-plus-pro-auth-json-ci/
- **refresh token の再利用エラー**: codex-plugin-cc の #789 に、長時間動く broker が単回使用の ChatGPT refresh token を消費して `refresh_token_reused` になる報告があります（§1）。

### 事実：Anthropic 側（出典: https://code.claude.com/docs/en/cloud-environments と https://code.claude.com/docs/en/claude-code-on-the-web を本文で確認）
- **ネットワークのアクセスレベル**: None / Trusted（既定。パッケージレジストリ、GitHub、クラウド SDK など）/ Full / Custom（独自の許可リスト）の4つ。**Trusted の既定許可リストに openai.com や chatgpt.com 系は含まれていません**（取得した許可リストを grep で確認）。
- **Custom で許可を追加する方法**: 「Allowed domains」に1行1ドメインで書きます。`*.` はサブドメインにマッチします。既定リストも残すにはチェックボックスを入れます。変更は新しいセッションから反映されます（新しい値は VM の復元または再構築のときに読まれる）。
- **環境変数**: 「Anyone who uses the environment can read the values」。秘密情報は環境変数ではなく **network secret** に入れるよう案内されています。network secret は、エージェントプロキシが指定ホスト宛てのリクエストヘッダーに後付けする方式で、VM 内からは見えません（Bearer トークンやカスタムヘッダー）。
- **時間制限**: Bash は既定2分・最大10分で、それを超えるとバックグラウンドに回され、さらに最大30分。`BASH_DEFAULT_TIMEOUT_MS` / `BASH_MAX_TIMEOUT_MS` で延長できます。setup script はおよそ5分以内でないとキャッシュされません。
- **クラウドセッションで使えないコマンド**: 「Commands that only run in the terminal interface, such as `/plugin` or `/resume`, aren't available」。
- 本セッションの材料ファイルにも、api.openai.com / chatgpt.com / auth.openai.com が 403 で拒否されると記録されています。

### 示唆（I5：クラウドの条件）
- クラウドで ChatGPT 認証の Codex を動かすには、少なくとも次が必要と推定されます。
  - (a) 環境を Custom にして OpenAI 側のホストを許可する。必要なホストの正確な一覧（chatgpt.com、auth.openai.com、api.openai.com など）は **未確認**。
  - (b) auth.json を VM に置く。
- ただし (b) は、公式が推奨しない「advanced option」に当たります。さらに次の理由で相性が悪いです。
  - 環境変数は同じ環境の利用者全員が読める。
  - network secret はヘッダーを付ける方式で、auth.json（refresh で更新されるファイル）の持ち込みには合わない（推論）。
  - VM は再構築されるので、更新された auth.json を保存し続ける仕組みが必要になる。
  - 同時に動く複数セッションで1つの auth.json を共有すると、公式の「1台または直列のみ」に反し、refresh token の再利用エラーの危険がある。
- 結論として、**ChatGPT プランでの連携は Mac ローカル（Claude Code CLI / Desktop の Local）に限定するのが現実的** です。クラウドや CI で必要になったら API キー（network secret で注入）に切り替えるのが、公式推奨とも一致する筋です。
- クラウドで ChatGPT 認証の Codex を実際に動かした第三者の事例は、今回の検索では **見つかりませんでした（未確認）**。

---

## 6. OpenAI 公式：Agents SDK × `codex mcp-server`

### 事実（検索抜粋。https://developers.openai.com/codex/guides/agents-sdk ）
- `codex mcp-server` を起動して MCP Inspector で確認できます。ツールは `codex` と `codex-reply()` で、`codex` は Codex の Config 構造体に合わせた設定パラメータを受け取ります。
- 前提条件は、Codex CLI、Python 3.10 以上、OpenAI API キー（Inspector を使う場合は Node 18 以上）です。
- ガイドは、単一エージェントでブラウザゲームを作る例と、ハンドオフ・ガードレール・トレースを使うマルチエージェントの例を扱っています。OpenAI Cookbook と同じ内容です。

### 示唆
- 公式は「Codex を MCP サーバーにして他のエージェントのツールにする」構成を正式なパターンとして示しています。Claude Code を MCP クライアントにする構成も技術的には同じ型です。ただし、Claude Code を名指しした公式の手順書は codex-plugin-cc だけでした。
- Agents SDK 側は API キーが前提なので、ChatGPT プランだけのユーザーには直接は使えません。

---

## 7. 運用設計への示唆まとめ（I6。みつき案件向けのたたき台）

1. **第一候補**: Mac ローカルで codex-plugin-cc を導入する（`/codex:setup` で ChatGPT ログインを確認）。普段は `/codex:adversarial-review "<観点>"` か、自作 Skill を使う。review gate は OFF にし、rescue はレビュー用途では使わない。
2. **文書レビュー用の自作 Skill**（プラグインが git 差分前提のため）。設計案で、実証は未確認:
   - `codex exec --sandbox read-only` を中心にし、外側に `timeout` を付ける。出力は `--output-last-message <file>` で受け取る。
   - プロンプトは「役割（例: 辛口の編集者）＋観点リスト＋対象ファイルのパス＋出力形式（指摘を重大度順に最大 N 件）」で固定する。
   - 追質問には `codex exec resume` を使う。
   - CLAUDE.md には「重要な提案資料、LP 文面、配信文は確定前に /second-opinion を通す」「Codex の指摘は採否と理由を明記してユーザーに提示する」「Codex にファイルを書かせない」を書く。
3. **MCP 登録**（`claude mcp add --transport stdio --scope user codex -- codex mcp-server`）は、手軽な反面、承認待ちのハングと進捗が見えない点の報告が多いです。採用するなら、approval-policy を never、sandbox を read-only に明示し、`MCP_TIMEOUT` と `tool_timeout_sec` を調整します。
4. **クラウドと CI** は ChatGPT 認証に向かないので、使うなら API キーに分離します（§5）。
5. **使用量の監視**: Claude Code 内からは Codex の残量が見えません（#102）。Codex の TUI で `/status` を見る運用が必要です（検索抜粋）。
