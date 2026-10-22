# 03a ベンチマーク：Claude Code から GPT を呼ぶ手段の比較（論点 I1 / I3 / I4）

調査日: 2026-10-22（JST前提）／担当: 市場・競合・ベンチマーク

## 0. 調査方法と制約（先に読んでください）

- **このクラウド環境から developers.openai.com / openai.com / help.openai.com / learn.chatgpt.com は WebFetch・curl とも到達不可**（DNS解決失敗またはプロキシ拒否）。そのため公式ページの記述は **WebSearch の検索結果スニペット経由**で確認したもので、本文の全文は読めていない。該当箇所には「(検索経由)」と付けた。
- 一方、**raw.githubusercontent.com と npm registry は到達可**。そのため以下は**一次資料を直接確認済み**:
  - `@openai/codex` **0.163.0**（npm の最新、2026-10-22 00:21 UTC 更新）を scratchpad にインストールし、`--help` / `debug models --bundled` / `features list` を実行して確認（ログインはしていない。api.openai.com が403のため実際の推論呼び出しは未検証）。
  - openai/codex-plugin-cc の README、BeehiveInnovations/pal-mcp-server の README と docs/tools/clink.md。
- 価格や上限は **OpenAI 側で頻繁に変わる**。導入前に公式ページを Mac のブラウザで再確認すること。

---

## 1. 事実（Facts）

### 1-1. OpenAI Codex CLI（@openai/codex）

| 項目 | 確認内容 | 出典 |
|---|---|---|
| 最新版 | 0.163.0（2026-10-22 時点の npm `latest`） | `npm view @openai/codex`（ローカル実行） / https://www.npmjs.com/package/@openai/codex |
| インストール | `npm install -g @openai/codex`、`brew install --cask codex`、または `curl -fsSL https://chatgpt.com/codex/install.sh \| sh`（Mac/Linux） | https://raw.githubusercontent.com/openai/codex/main/README.md |
| ChatGPTプランでの利用 | README:「Run `codex` and select **Sign in with ChatGPT**. We recommend signing into your ChatGPT account to use Codex as part of your Plus, Pro, Business, Edu, or Enterprise plan.」 API キーでも使えるが追加設定が必要 | 同上 |
| 対象プラン | Codex は Free / Go($8) / Plus($20) / Pro($100〜) / Business / Edu / Enterprise に含まれる (検索経由) | https://developers.openai.com/codex/pricing |

#### ログイン方式（`codex login`）
`codex login --help`（0.163.0 実機）で確認できたオプション:
- 引数なし → ブラウザで ChatGPT サインイン（既定経路。公式 auth ページも「Sign in with ChatGPT がCLIの既定」と記載(検索経由)） — https://developers.openai.com/codex/auth
- `--device-auth` → OAuth デバイスコード方式。**事前に ChatGPT のセキュリティ設定（個人）またはワークスペース管理者の権限設定で device code login を有効化する必要がある**、beta 表記、デバイスコードはフィッシングされ得るので共有しない、との公式記述 (検索経由) — https://learn.chatgpt.com/docs/auth / https://developers.openai.com/codex/auth
- `--with-api-key`（stdin から API キー）、`--with-access-token`（stdin からアクセストークン）
- `codex login status`（ログイン状態表示）
- ヘッドレス機への持ち込み: ブラウザのある機で `codex login` → `~/.codex/auth.json` を同じパスにコピー。「アクセストークンを含むのでパスワード同様に扱う」、OSの資格情報ストアに保存している場合は file-based storage 設定が必要、との公式記述 (検索経由) — https://developers.openai.com/codex/auth

#### 非対話モード `codex exec`（0.163.0 実機の `codex exec --help` で確認）
- `codex exec "プロンプト"`、または stdin から（`-` か省略時）。stdin とプロンプト併用時は stdin が `<stdin>` ブロックとして追記される。
- 主なオプション: `-m/--model`、`-s/--sandbox read-only|workspace-write|danger-full-access`、`--json`（JSONL イベント出力）、`-o/--output-last-message <FILE>`（最終回答をファイル出力）、`--output-schema <FILE>`（JSON Schema で出力形を指定）、`-i/--image <FILE>`（画像入力）、`--skip-git-repo-check`、`--ephemeral`（セッションを保存しない）、`-C/--cd`、サブコマンド `resume` / `fork` / `review`。
- トップレベル `codex review`（非対話コードレビュー）も存在。
- 出典: ローカル実行結果（`codex exec --help`）。公式説明ページ: https://developers.openai.com/codex/noninteractive （到達不可・未読）

#### `codex mcp-server` は **廃止済み**（重要）
- 0.163.0 では `codex mcp-server` は**サブコマンドとして存在しない**（`codex help mcp-server` → `error: unrecognized subcommand 'mcp-server'`。ローカル実行で確認）。
- 経緯 (検索経由・二次情報): 0.149 系で非推奨警告追加（PR #39657, 2026-08-20 マージ）、公式 changelog で 2026-08-24 に非推奨化、**0.154.0 で `codex mcp-server` と単体 `codex-mcp-server` バイナリを削除**（PR #42993, 2026-09-05 マージ、リリースは 2026-09-09 とする情報あり）。後継は **app-server**（MCPではない独自プロトコル、experimental）で、Claude Code 向けの公式経路は Codex plugin とされる。
  - https://x.com/CodexReleases/status/2097817398040551429 （"The deprecated codex mcp-server entry point is no longer available."）
  - https://codex.danielvaughan.com/2026/08/30/codex-mcp-server-deprecated-migration-app-server-agents-sdk/
  - https://www.developersdigest.tech/blog/codex-mcp-server-removed
  - https://note.com/fast_camel9956/n/n31e647a10cf9
- 旧 mcp-server が公開していたツール（参考・旧仕様）: `codex`（新規セッション開始。prompt、approval-policy、sandbox 等）と `codex-reply`（`prompt` と `threadId` で継続。`conversationId` は旧名）(検索経由) — https://techdevnotes.com/releases/codex-cli/0.152.0/content/docs/codex-rs/codex_mcp_interface.md
- 0.153.x 以前に固定すれば旧コマンドは動くが一時しのぎ、との二次情報あり（同上 danielvaughan）。
- なお `codex mcp list|get|add|remove|login|logout` は「Codex が外部MCPサーバーを使う」ための管理コマンドで、Codex を MCP として公開する機能ではない（ローカル `codex mcp --help`）。
- `codex app-server`（[experimental]）は 0.163.0 に存在（`daemon` / `proxy` / `generate-ts` / `generate-json-schema`）（ローカル `codex app-server --help`）。

#### 利用可能モデル（0.163.0 同梱カタログ `codex debug models --bundled`、ローカル実行で確認）
表示対象（visibility=list）:

| slug | 表示名 | 同梱カタログの説明 |
|---|---|---|
| gpt-6.1-sol | GPT-6.1-Sol | "Latest workhorse model for coding and everyday work."（priority 1 = 既定候補） |
| gpt-6-astra | GPT-6-Astra | "Frontier intelligence for the most demanding work." |
| gpt-6-sol | GPT-6-Sol | "Previous generation workhorse model." |
| gpt-6-luna | GPT-6-Luna | "Fast and affordable model for easier tasks." |
| gpt-5.6-sol / gpt-5.6-terra / gpt-5.6-luna | | 旧世代 |
| gpt-5.5 | | "Legacy coding model." |

- 全モデル `input_modalities: text, image`、`supports_search_tool: true`、context_window 272,000（カタログ値）。
- 同梱カタログはオンラインで更新され得る（`--bundled` は同梱分のみ）。**プラン別にどのモデルが選べるかはカタログに記載なし**。公式 pricing は「Plus includes GPT-6.1 Sol and GPT-6 Luna」、ヘルプ記事は「Plus / Standard Business は Astra の利用が限定的」と記載 (検索経由) — https://developers.openai.com/codex/pricing / https://help.openai.com/en/articles/20001516-managing-usage-with-gpt-6-astra-in-work-and-codex

#### プラン別利用上限（公式 pricing、検索経由）
- **Plus / Standard Business（5時間あたりのローカルメッセージ目安）**: GPT-6 Astra 5–45、GPT-6.1 Sol 15–160、GPT-6 Sol 15–150、GPT-6 Luna 350–3,000。週次上限もあり得る。「固定上限ではなく目安。使用量ダッシュボードで確認」との注記 — https://developers.openai.com/codex/pricing
- **Pro 100 / 200 / 500**: 現在 Work と Codex で**5時間上限なし**（ただし含まれる利用枠・週次上限はある）。Pro 500 のみ Ultrafast 含む。非グランドファザーの新規 Pro 200 は従来より枠が小さい — https://help.openai.com/en/articles/9793128-about-chatgpt-pro-tiers / https://help.openai.com/en/articles/20001516-managing-usage-with-gpt-6-astra-in-work-and-codex
- Go は Codex（ローカル）含むが Codex Cloud は Free/Go 対象外 (検索経由) — https://developers.openai.com/codex/pricing
- 上限超過時: Plus/Pro はクレジット追加購入可。API キーで追加のローカル利用（API標準料金）も可 (検索経由) — 同上
- Fast は Standard の 2.5倍、GPT-6.1 Sol Ultrafast は 8倍の速度で枠を消費 (検索経由) — 同上
- Pro の具体的な倍率（Plus比 5x/10x/20x 等）は二次情報間で矛盾しており**未確認**。

#### 画像生成
- 0.163.0 の feature flag `image_generation` = **stable / 有効**（ローカル `codex features list`）。
- 公式 (検索経由): Codex の組み込み画像生成は **gpt-image-2** を使い、Codex CLI でも利用可、**一般の Codex 利用枠に計上され、テキストの3〜5倍の速さで枠を消費**。**Free プランでは不可**。上限到達後はクレジットから消費。OPENAI_API_KEY を設定すれば API 料金側で生成も可能 — https://learn.chatgpt.com/docs/image-generation / https://developers.openai.com/codex/pricing
- 矛盾: ヘルプセンターは ChatGPT の画像生成は別枠と記載しており、Codex 内の画像生成と同一枠かは**未確認**（要ダッシュボード確認） — https://help.openai.com/en/articles/11369540-using-codex-with-your-chatgpt-plan
- `codex exec` から画像ファイルを保存するまでの具体的手順は**未検証**（本環境でログイン不可のため）。

#### Web検索
- 0.163.0 の `--search`:「Enable live web search. ... the native Responses `web_search` tool is available to the model (no per‑call approval)」（ローカル `codex --help`）。※ `--search` はトップレベルにあり、`codex exec --help` には表示されない → exec では `-c web_search="live"` で指定する形になると推測（**未検証**）。
- 公式 config (検索経由): `web_search` 既定は **"cached"**（OpenAI管理インデックス、外部アクセスなし）、`"live"` でライブ検索、`--yolo` 等フルアクセス時は既定 live、`"disabled"` で無効 — https://developers.openai.com/codex/config-reference / https://learn.chatgpt.com/docs/web-search
- プラン別の可否差は**未確認**。

### 1-2. OpenAI 公式 Claude Code プラグイン（openai/codex-plugin-cc）
README を raw で直接確認: https://raw.githubusercontent.com/openai/codex-plugin-cc/main/README.md
- 要件: 「**ChatGPT subscription (incl. Free) or OpenAI API key.** Usage will contribute to your Codex usage limits.」、Node.js 18.18+
- 導入: `/plugin marketplace add openai/codex-plugin-cc` → `/plugin install codex@openai-codex` → `/reload-plugins` → `/codex:setup`（未導入なら Codex CLI の npm インストールを提案）→ 未ログインなら `!codex login`
- コマンド: `/codex:review`（読み取り専用レビュー、`--base <ref>`、`--background`/`--wait`、フォーカス指定不可）、`/codex:adversarial-review`（フォーカス文を渡せる“攻める”レビュー）、`/codex:rescue`（`codex:codex-rescue` サブエージェントに委任、`--model`/`--effort`/`--resume`/`--fresh`）、`/codex:transfer`、`/codex:status`、`/codex:result`、`/codex:cancel`
- 仕組み: 「wraps the Codex app server」、ローカルのグローバル `codex` バイナリと `~/.codex/config.toml` 設定・認証状態をそのまま使う
- 任意の review gate（Stopフックで自動レビュー）は「usage limits を急速に消費し得る」と警告
- 公開日: 2026-03-30〜31（二次情報、OpenAI の Romain Huet 投稿「You can call Codex from Claude Code with your ChatGPT subscription.」）— https://x.com/romainhuet/status/2038677236304245087 / https://the-decoder.com/openai-launches-a-codex-plugin-that-runs-inside-anthropics-claude-code/
- README のモデル例は `gpt-5.4-mini` / `gpt-5.3-codex-spark` で、最新カタログ（GPT-6系）と記述が古い可能性あり（事実として README に記載）。

### 1-3. OpenAI API 直接利用（APIキー・従量課金）
- **ChatGPT と API は別課金**:「ChatGPT and the API platform have separate billing systems」「API usage is billed separately from your ChatGPT subscription」(検索経由) — https://help.openai.com/en/articles/8156019-is-api-usage-included-in-chatgpt-subscriptions-even-if-you-have-a-paid-chatgpt-account
- テキストモデル価格（Standard、per 1M tokens、公式モデルページ・検索経由）:

| モデル | 入力 | キャッシュ入力 | 出力 | 出典 |
|---|---|---|---|---|
| gpt-6-astra | $10 | $1.00 | $50 | https://developers.openai.com/api/docs/models/gpt-6-astra / https://openai.com/index/gpt-6-astra/ |
| gpt-6.1-sol | $2 | $0.10 | $10 | https://developers.openai.com/api/docs/models/gpt-6.1-sol |
| gpt-6-luna | $0.10 | $0.01 | $0.50 | https://developers.openai.com/api/docs/models/gpt-6-luna |

  - 272K 超の入力は入力2倍・出力1.5倍。Batch/Flex は50%引き、Fast は2倍、Ultrafast は6倍（gpt-6.1-sol）(検索経由) — 同上
  - gpt-6-sol 単体の価格は二次情報のみ（$2/$10）で公式未確認。
- 画像生成 API (検索経由、公式 image generation ガイド):
  - GPT Image 2（1024×1024）: low 約 $0.006 / medium $0.053 / high $0.211 per image
  - GPT Image 1.5: $0.009 / $0.034 / $0.133、GPT Image 1 Mini: $0.005 / $0.011 / $0.036
  - GPT Image 2.5 系トークン単価: 画像入力 $8、画像出力 $30、テキスト入力 $5 /1M（料金ページと一部不一致あり）
  - https://developers.openai.com/api/docs/guides/image-generation / https://developers.openai.com/api/docs/models/gpt-image-2.5-flare / https://developers.openai.com/api/docs/pricing

### 1-4. コミュニティ製 MCP
**PAL MCP Server（旧 Zen MCP Server, BeehiveInnovations/pal-mcp-server）** — README / clink.md を raw で直接確認
- https://raw.githubusercontent.com/BeehiveInnovations/pal-mcp-server/main/README.md
- 前提: Python 3.10+、uv。「**You need at least one API key**」（OpenRouter / Gemini / OpenAI / Azure / X.AI / DIAL / Ollama のいずれか。Ollama はローカルで無料）— https://raw.githubusercontent.com/BeehiveInnovations/pal-mcp-server/main/docs/getting-started.md
- OpenAI モデルを直接呼ぶ場合は `OPENAI_API_KEY`（API従量）。
- `clink` ツール: 外部CLI（Codex CLI / Gemini CLI / Claude Code）をサブエージェントとして起動。Codex プリセットは `codex exec --json --dangerously-bypass-approvals-and-sandbox` を実行し、「Pre-authenticate CLIs」と記載 → **Codex CLI を ChatGPT ログイン済みにしておけば clink 経由でプラン枠を使える構造**（README上の構造からの読み取り。実動作は未検証）。clink は緩い権限フラグで起動する旨の CAUTION あり — https://raw.githubusercontent.com/BeehiveInnovations/pal-mcp-server/main/docs/tools/clink.md
- 「API キーなし・clink のみ」で起動できるかは**未確認**（README は最低1キー必須と記載）。
- セキュリティ: 前身 Zen MCP Server 9.8.2 未満にパストラバーサル脆弱性（CVE）の記載 — https://releasealert.dev/github/BeehiveInnovations/pal-mcp-server/cves
- その他の「codex を MCP 化する」サードパーティ（例: cexll/codex-mcp-server、codex-octopus 等）は存在が検索で確認できたが、多くは廃止された `codex mcp-server` か `codex exec` のラッパーで、認証は Codex CLI に依存。個別の保守状況は**未確認** — https://glama.ai/mcp/servers/@cexll/codex-mcp-server/blob/19fbc1b6441f4f8888cf5b45fcb427a379e05632/docs/authentication.md

---

## 2. 比較表（I1 / I3 / I4）

| 方式 | 認証 | GPT利用料 | テキスト（セカンドオピニオン/レビュー） | 画像生成 | Web検索 | 2026-10時点の状態 |
|---|---|---|---|---|---|---|
| A1. Bash で `codex exec` | ChatGPTログイン可 | プラン枠内（追加費用なし） | 可（`-o`/`--json`/`--output-schema`） | 可（gpt-image-2、枠を3〜5倍消費、Free不可） | 可（既定 cached、live は設定） | 公式・現行 |
| A2. `codex mcp-server` をMCP登録 | — | — | — | — | — | **0.154.0で削除済み・不可** |
| A3. 公式 codex-plugin-cc | ChatGPTログイン可（Free含む） | プラン枠内 | 可（`/codex:review`、`/codex:adversarial-review`、`/codex:rescue`） | プラグイン経由の画像生成は未確認（rescue 委任で可能性あり） | 未確認（Codex設定依存） | 公式・現行（app-server ラップ） |
| B. OpenAI API 直接 | APIキー必須 | 従量（別課金） | 可 | 可（$0.006〜0.211/枚） | 可（Responses の web_search ツール。料金は未確認） | 現行 |
| C. PAL MCP | 最低1つのAPIキー必須。clink は Codex CLI の認証を流用 | APIキー分は従量、clink→Codex はプラン枠 | 可 | 未確認 | 未確認 | コミュニティ・現行 |

## 3. 月額コスト試算（I3）

前提: 1日30回 × 30日 = **900回/月**、1回 入力5,000 / 出力1,000 トークン → 月 **入力4.5M / 出力0.9M トークン**。キャッシュ・Batch割引なし、Standard料金。出力1,000には推論トークンを含むと仮定。

| モデル（API直接） | 入力費 | 出力費 | 月額 |
|---|---|---|---|
| gpt-6-luna | 4.5×$0.10 = $0.45 | 0.9×$0.50 = $0.45 | **約 $0.90** |
| gpt-6.1-sol | 4.5×$2 = $9 | 0.9×$10 = $9 | **約 $18** |
| gpt-6-astra | 4.5×$10 = $45 | 0.9×$50 = $45 | **約 $90** |

感度: 推論トークンで出力が実質3,000/回になると gpt-6.1-sol は $9 + $27 = **約 $36**、astra は $45 + $135 = **約 $180**。
画像（参考）: GPT Image 2 medium 1024² を 1日10枚 → 300枚 × $0.053 ≈ **約 $16/月**。

比較: ChatGPT Plus は **$20/月**で、Codex 経由なら GPT-6.1 Sol が 5時間あたり 15–160 メッセージの目安（上記 900回/月 = 平均 1日30回は、1回が軽いレビューであれば目安の範囲内に収まる見込み。ただし Codex はエージェントとしてシステムプロンプトやファイル読み込みで1回あたりのトークンが API 直呼びより大きくなりやすく、実際の枠消費は**未検証**）。

---

## 4. 示唆（Implications）— 事実ではなく解釈

1. **「ChatGPTプランのみ」の制約下での第一候補は、公式 codex-plugin-cc（A3）か `codex exec` の Bash 呼び出し（A1）**。どちらも OpenAI 公式で ChatGPT ログインを明示的にサポートし、追加課金なしでプラン枠を使う。材料ファイル仮説Aの「`codex mcp-server` を MCP 登録」は**既に廃止されており採用不可**。後続ステップ（手順・運用設計）では mcp-server 前提の記述を除外すべき。
2. 事業用途（文章・提案資料のレビュー）では、コード差分前提の `/codex:review` より、**フォーカス文を渡せる `/codex:adversarial-review` か、Claude Code の Skill/スラッシュコマンドから `codex exec -s read-only --ephemeral -o out.md "..."` を呼ぶ自作ラッパー**の方が合う可能性が高い（README上 `/codex:review` は「not steerable」）。
3. コスト面では、想定負荷なら API 直接でも gpt-6.1-sol で月 $18〜36 程度と小さい。ただしユーザーは API キー未保有で、別課金・支払い設定が必要。**Plus 枠で足りるかを1〜2週間試し、足りなければ API キーを追加**する段階導入が合理的。
4. 画像生成は Codex 経由でもプラン枠で可能だが、枠を3〜5倍消費し Free 不可。大量生成は API（gpt-image-2 medium ≈ $0.05/枚）に逃がす設計が妥当。
5. PAL MCP は API キー必須が前提で、clink 経由の Codex 呼び出しは公式プラグインと機能が重複し、さらに危険な権限フラグで起動する。**この利用者には優先度低**。
6. クラウドセッション（本環境）では OpenAI 系ドメインがブロックされており、`codex exec` も実推論は不可。**当面は Mac ローカル限定**と考えるのが安全（ネットワーク許可の可否は I5 担当で要確認）。
7. モデル名・上限・価格は 2026年に入り何度も変わっている（GPT-5.x → GPT-6 Sol/Luna/Astra → 6.1 Sol）。手順書には「`codex debug models` で現行モデルを確認」「既定モデルは Codex に任せる」と書き、特定モデル名をハードコードしない方が保守しやすい。

## 5. 未確認事項（残課題）
- 公式ドキュメント本文（developers.openai.com / learn.chatgpt.com / help.openai.com）を直接読めていない（検索スニペット経由）。
- ChatGPTログイン状態での `codex exec` 実行・画像生成・live検索の実動作（本環境では api.openai.com 等が403）。
- Plus の週次上限の具体値、Pro 各ティアの Plus 比倍率。
- Codex 内画像生成が ChatGPT 本体の画像生成枠と同一かどうか。
- `codex exec` での live 検索の指定方法（`-c web_search="live"` と推測）。
- PAL MCP を API キーなし（clink のみ）で起動できるか。
- API の web_search ツール利用料金。
