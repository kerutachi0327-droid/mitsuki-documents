> **注意（レビュー後追記）**: 本書 §3-1・§3-2 に埋め込まれた SKILL.md / run.sh は**レビュー前の版**です。導入には `tools/gpt-second-opinion/` の修正版を使ってください（修正内容は 05_review.md）。

# 04 ストラテジー：Claude Code → GPT 連携の実現オプション統合と推奨

作成日: 2026-10-22／担当: ストラテジスト
入力: 00_material.md（末尾ローカル実機確認）、03a_benchmark.md、03b_analogies.md、03c_user.md
前提: ユーザーは **ChatGPT 有料プランのみ（OpenAI API キーなし）**、主環境は **Mac の Claude Code**。

> 信頼度の注意: OpenAI 公式ページ（developers.openai.com / help.openai.com / learn.chatgpt.com）は3本とも **検索抜粋経由** で、本文は読めていない。一次確認できたのは、npm の `@openai/codex` 0.163.0 の実機ヘルプ、GitHub README（codex / codex-plugin-cc / pal-mcp-server）、code.claude.com。価格・上限・モデル名は導入前に Mac のブラウザで再確認すること。

---

## 0. 矛盾点の整理（ローカル実機確認を優先）

| # | 論点 | 食い違い | 採用する結論 | 根拠 |
|---|---|---|---|---|
| C1 | `codex mcp-server` | **03b** は §2・§4・§7-3 で「公式の `codex mcp-server` を MCP 登録」を実例付きで有効な選択肢として扱う。参照元はいずれも 2026-07 以前の記事（例: codex-cli 0.142.4 の Algomatic 記事 https://tech.algomatic.jp/entry/2026/07/14/160815 ）。03a・03c は「削除済み」。 | **使えない（採用不可）**。材料のローカル確認で 0.163.0 のトップレベルヘルプに表示されず、03a の実機確認で `codex help mcp-server` → `unrecognized subcommand`。0.154.0 で削除（PR #42993）とする情報と整合。 | 00_material.md 末尾／03a §1-1（https://x.com/CodexReleases/status/2097817398040551429 、https://www.developersdigest.tech/blog/codex-mcp-server-removed ）／03c §1-2（https://developers.openai.com/codex/guides/agents-sdk 検索抜粋） |
| C2 | `codex mcp` の意味 | 古い記事は `codex mcp` を「Codex を MCP として公開」と読める書き方（03b §2 の Zenn 追記）。 | 現行の `codex mcp` は **Codex が外部 MCP を使う側** の管理コマンド。Claude から Codex を呼ぶ用途ではない。 | 00_material.md／03a（`codex mcp --help` 実機） |
| C3 | Codex 内の画像生成と ChatGPT 本体の画像枠 | 03a は「help center は別枠と記載、同一枠かは未確認」。03c は「Codex 利用枠を消費、ChatGPT 側の画像回数制限とは別」。 | **Codex 内の画像生成は Codex 利用枠を消費（テキストの3〜5倍）**、ChatGPT アプリ内の画像枠とは別、と読むのが両者と整合。ただし実画面では **未確認**。 | https://developers.openai.com/codex/image-generation ／ https://help.openai.com/en/articles/11369540-using-codex-with-your-chatgpt-plan |
| C4 | Go プランで CLI が使えるか | 03c 内で公式要約（CLI 可）と二次情報（デスクトップのみ）が食い違う。 | **未確認**。業務用途は Plus 以上を前提にする。 | 03c §2 |
| C5 | Cowork でローカル MCP／ローカル連携が動くか | Anthropic サポート記事間で記述が割れる。 | **未確認**。まず Claude Code（ターミナル／Desktop の Code タブ）で設計し、Cowork は実機で試してから判断。 | https://support.claude.com/en/articles/11175166 ／ https://support.claude.com/en/articles/11725091 |
| C6 | `codex exec` の既定サンドボックス | 03b は公式（検索抜粋）で「既定 read-only」。 | 既定に頼らず **`-s read-only` を明示**。今回このクラウド環境で `codex exec -s read-only --ephemeral ...` を起動し、バナーに `sandbox: read-only` / `approval: never` と出ることを確認済み（推論はネットワーク 403 で未到達）。 | 本ドキュメント作成時の実機確認 |
| C7 | web 検索フラグ | `--search` はトップレベルのみで、`codex exec --help` にない（03a）。 | exec での live 検索は `-c web_search="live"` と **推測（未検証）**。今回の Skill では使わない。 | 03a §1-1 |

### 本ドキュメント作成時に追加で実機確認した事実（このクラウド環境、0.163.0、未ログイン）
- `codex login status` は未ログイン時に `Not logged in` を出し **終了コード 1**（ログイン確認に使える）。
- `codex exec` は stdin がパイプされていると `Reading additional input from stdin...` と表示して読み込む。**引数 `-` を付けて stdin からプロンプトを渡す方式** が、Claude Code の Bash（TTY なし）でも待ち状態にならず確実。
- 未ログインでもすぐにエラー終了せず API に接続を試み、接続できないと `Reconnecting... waiting for network` で **待ち続けた**。外側のタイムアウトは必須。
- 既定モデルの表示は `gpt-6.1-sol`（同梱カタログの既定）。ただしプラン・カタログ更新で変わり得るので **ハードコードしない**。
- **macOS には標準で `timeout` コマンドがない**（GNU coreutils 由来。Homebrew の `gtimeout` は別途導入が必要）。そのため、下の実装では `timeout` → `gtimeout` → `perl` の `alarm` の順で代替する（perl 方式は終了コード 142 でタイムアウトすることをここで確認済み）。

---

## 1. オプション比較

除外したもの（比較表に入れない）:
- **`codex mcp-server` を MCP 登録**: 現行版で削除済み（C1）。
- **ブラウザ自動化（chatgpt.com 操作）・非公式のサブスク→API 変換プロキシ**: 利用規約の「自動的またはプログラム的に Output を抽出」の禁止に抵触し得て、UI 変更で壊れる（https://openai.com/policies/terms-of-use/ 、https://zylos.ai/research/2026-07-13-subscription-auth-boundaries-official-cli-agent-automation ）。
- **PAL MCP（旧 Zen）などコミュニティ製の中継 MCP**: API キーが最低1つ必須で、Codex 連携（clink）は承認とサンドボックスをバイパスするフラグで起動する（https://raw.githubusercontent.com/BeehiveInnovations/pal-mcp-server/main/docs/tools/clink.md ）。公式経路と機能が重なるうえ、リスクが増える。
- **手動コピペ**: 連携ではない。比較の下限としてのみ扱う。

| 観点 | A. 公式プラグイン codex-plugin-cc 単体 | **B. 自作 Skill ＋ `codex exec`（read-only）** | C. OpenAI API キー追加（従量） | **D. 併用（B を主、A をコード用、C は必要時のみ）** |
|---|---|---|---|---|
| 追加コスト | 0円（ChatGPT プラン枠を消費） | 0円（プラン枠を消費） | 別課金。試算で gpt-6.1-sol 月約 $18〜36、luna 約 $1、astra 約 $90〜180（1日30回想定、03a §3） | 当面0円。C を足した分だけ従量 |
| 導入難易度（非エンジニア） | 低い。Claude Code 内で `/plugin` 4コマンド＋本人のログイン | 低〜中。Codex 導入＋ログイン＋ファイル2つの設置（Claude に作らせれば可） | 中〜高。API 支払い設定、キー管理、呼び出し口（スクリプトか MCP）の自作 | 中（B の後に A を足すだけ） |
| 規約リスク | 低（OpenAI 公式、ChatGPT サブスク対応を明記） | 低（公式 CLI を本人のアカウントで本人の業務に使う。明示の許可ではなく「禁止事項に該当しない」位置づけ、03c §1-1） | 低（API は本来の用途） | 低 |
| 文章・提案資料レビュー | △ `/codex:review` は git 差分前提で観点を指定できない。`/codex:adversarial-review "<観点>"` は観点を渡せるが、git 管理外の文書でどこまで機能するかは **未確認** | ◎ 任意の文章を観点と出力形式つきで渡せる | ◎（自作次第） | ◎ |
| セカンドオピニオン（設計・方針） | ○ adversarial-review / rescue（rescue は既定で書き込み可、issue #798） | ◎ 読み取り専用で1回呼ぶ形に固定 | ◎ | ◎ |
| コードレビュー（HTML リポジトリ等） | ◎ 本来の用途 | ○（`codex review` も可） | ○ | ◎（A を使う） |
| 画像生成 | **未確認**（rescue 委任で可能性あり） | 理論上可（gpt-image-2、枠を3〜5倍消費、Free 不可）。`codex exec` から画像ファイルを保存する手順は **未検証** | ◎ 確実（GPT Image 2 medium 約 $0.053/枚） | 試行は B、量が多ければ C |
| 安定性 | △ ハング（#793, #781）、refresh token の再利用エラー（#789）、broker のリーク（#801 等）の open issue が多い（https://github.com/openai/codex-plugin-cc/issues ） | ○ 単発プロセスで常駐しない。外側の timeout、終了コードで状態を判別できる。実践記事でも「MCP より Skill＋exec が安定」の傾向（03b §3） | ◎（API は安定。自作部分次第） | ○ |
| Cowork | **未確認**（C5） | **未確認**（ユーザースコープの Skill を Cowork が読むか、Cowork の実行環境から Mac の codex と認証にアクセスできるかは要実機確認） | 構成次第で可能性あり（**未確認**） | 未確認 |
| クラウド（claude.ai/code） | ✕ `/plugin` はクラウドで使えない（https://code.claude.com/docs/en/claude-code-on-the-web ） | ✕ 現状 OpenAI 系ドメインが 403。許可ドメイン追加＋auth.json 持ち込みは公式で「advanced」扱い、複数マシン共有不可（https://developers.openai.com/codex/auth/ci-cd-auth ）。推奨しない | ○ 許可ドメイン追加＋キーを network secret で注入すれば成立する見込み（公式推奨とも一致。実動作は **未確認**） | クラウドが必要になったら C |
| 使用量の見え方 | Claude Code 内から残量が見えない（#102） | 同じ。上限到達はログから検知し、残量は `codex` を起動して `/status` で確認 | API ダッシュボード | — |

---

## 2. 推奨案と段階導入

### 推奨: **D（併用）の段階導入。今日は B（自作 Skill ＋ `codex exec`）だけを入れる**

理由:
1. **業務の中心は文章**（LP・配信文・提案資料・サロン運営資料）。任意の文章に観点を付けて読み取り専用で渡せるのは B だけ。A は git 差分のコードレビュー向けの設計。
2. **追加費用ゼロ・規約リスク低**。公式 CLI を本人の ChatGPT アカウントで使う経路で、API キーも別課金も不要。
3. **安定性と安全性を自分で固定できる**。read-only・ephemeral・空フォルダで実行・timeout・個人情報ガードを1本のスクリプトにまとめられる。A は open issue（ハング、トークンの消耗、rescue の書き込み既定）が多く、主経路にするにはまだ不安がある。
4. **`codex mcp-server` を前提にした古い手順に依存しない**（C1）。
5. A と C は B と同じ Codex のログイン状態や仕組みの延長で足せるので、後から足しても手戻りがない。

### 段階導入

| 時期 | やること | 完了の目安 |
|---|---|---|
| **今日（30〜45分）** | ① ChatGPT の学習 OFF（Settings → Data controls → 「Improve the model for everyone」を OFF）② Mac に Codex CLI を導入 ③ **本人が** `codex login` ④ Skill（§3-1）を設置 ⑤ 動作確認（§3-3）⑥ クレジットの自動リロードが OFF であることを確認 | 「この文章を GPT にセカンドオピニオンして」で、指摘と Claude の採否が返ってくる |
| **1〜2週間** | 実運用。重要な配信文・LP・提案資料だけに使う。上限に当たった回数と、指摘が役に立った率をメモ | 「Plus 枠で足りるか」「GPT の指摘が有用か」を判断できる |
| **必要になったら** | A を追加（Cloudflare Pages の HTML リポジトリのコードレビュー用、§3-4）。review gate は OFF、rescue はレビュー目的では使わない | `/codex:review` が動く |
| **さらに必要なら** | C を追加（クラウドセッションや Cowork から使いたい／画像を量産したい場合）。キーは network secret で注入、支払い上限を設定 | 用途が具体化してから設計 |
| **随時** | 画像生成の試行（B で `$imagegen` 等。**手順は未検証**なので、別途実機で検証してから Skill 化） | — |

---

## 3. 推奨案の実装仕様（ユーザーの Mac 用）

### 3-0. ファイル構成

```
~/.claude/skills/gpt-second-opinion/
├── SKILL.md   … Claude Code が読む手順書（いつ・どう使うか、守るルール）
└── run.sh     … 実際に codex exec を呼ぶ実行スクリプト（実行権限を付ける）
```

- ユーザースコープ（`~/.claude/skills/`）に置くので、どのプロジェクトの Claude Code からも使える。
- `codex exec` の呼び出し内容（run.sh が組み立てる実コマンド）:
  `codex exec -s read-only --ephemeral --skip-git-repo-check --color never -C <空の一時フォルダ> -o <一時フォルダ>/answer.md [-m <指定時のみ>] -  < prompt.md`
  - `-s read-only`: GPT はファイルを書き換えられない。ただし read-only でも **ディスクの読み取り自体は可能** と考えるべき（サンドボックスの仕様上の推測。未検証）。そのため、作業場所を空フォルダにし、プロンプトで「対象テキストだけで判断、探索不要」と明示して、リスクを下げている。
  - `--ephemeral`: セッションを保存しない（後から `resume` で追質問はできない。必要になったら外す）。
  - `-o`: 最終回答だけをファイルに書き出し、それを表示する。
  - `-`: プロンプトを stdin から読む（C6 の下の実機確認を参照）。
- このクラウド環境で検証済みの分岐: 引数エラー（64）、メール検出（4）、電話番号検出（4）、codex 未検出（2）、未ログイン（3）、タイムアウト（6、`timeout` と perl `alarm` の両方）。**未検証**: Mac 上でのログイン後の成功（0）、上限到達（5）、認証切れ（3）の実際のエラーメッセージ。上限・認証切れの検知はエラー行の文言（usage limit / rate limit / 429 / 401 など）からの推定なので、実際の文言を見て調整が必要になる可能性がある。

### 3-1a. SKILL.md 全文

~~~~markdown
---
name: gpt-second-opinion
description: OpenAI の GPT（公式 Codex CLI・ChatGPT プランのログイン）に、文章・LP・LINE/メール配信文・提案資料・企画や方針のセカンドオピニオンを読み取り専用で1回だけ求める。「GPTに聞いて」「GPTの意見」「セカンドオピニオン」「Codexにレビューさせて」「別のAIにも見てもらって」と言われたとき、または重要な配信文・LP・提案資料を確定する前に使う。コードの差分レビューは /codex:review（公式プラグイン）を優先する。
---

# GPT セカンドオピニオン

Claude が作業中の文章や方針について、OpenAI の GPT に独立した意見を1回だけ求め、Claude が採否を判断してユーザーに提示する。GPT はユーザーの Mac にある公式 Codex CLI（`codex exec`）を、ユーザー本人の ChatGPT ログインで呼ぶ。API キーは使わない。

実行は同じフォルダの `run.sh` が行う。run.sh は read-only サンドボックス、セッションを保存しない（`--ephemeral`）、空の一時フォルダで実行、最終回答をファイルに出力（`-o`）、タイムアウト、PATH の補正、ログイン確認、メール・電話番号の検出をまとめて処理する。

## 絶対ルール

1. **個人情報を送らない。** 会員・顧客の氏名、メールアドレス、電話番号、LINE の表示名や ID、住所、購入・決済の履歴、個別の相談内容は送信前に置き換える（例: 「会員A」「[メール]」「[電話]」「[住所]」）。会員リスト、CSV、スプレッドシートの行データ、UTAGE や Gmail から取得した生データはそのまま送らない。伏せると成り立たない依頼なら、送る前にユーザーに確認する。
2. **GPT にファイルを書かせない・コマンドを実行させない。** run.sh 以外の方法で codex を呼ばない。`--dangerously-bypass-approvals-and-sandbox`、`--sandbox workspace-write`、`danger-full-access`、`--approve-for-me` は使わない。
3. **ログインを代行しない。** 未ログインや認証切れのときは、ユーザー本人にターミナルで `codex login` を実行してもらう。パスワード、デバイスコード、`~/.codex/auth.json` の中身を聞いたり表示したりしない。
4. **1回の依頼で呼ぶのは原則1回（多くても2回）。** 自動で何度も往復させない。上限に達したら再試行しない。クレジットの購入や自動リロードを勧めない（判断はユーザー本人）。
5. **GPT の意見は参考意見。** 指摘を自動で反映しない。事実関係（料金、日付、法令、数値）の指摘は Claude が確認してから扱う。
6. **モデルは指定しない（既定に任せる）。** ユーザーがモデルを指定したときだけ `--model <slug>` を付ける。使える slug がわからなければ、ユーザーにターミナルで `codex debug models` を実行してもらい確認する。

## 手順

### 1. 対象と観点を決める
- 対象: 作業中のファイル、またはユーザーが貼った文章。長いときは、レビューに必要な部分に絞る（目安: 本文 8,000 字以内）。
- 観点: ユーザーの指定がなければ、種類に応じて次から選ぶ。
  - LP・セールス文: 読者（サロンの見込み客）に刺さるか、ベネフィットの明確さ、不安の解消、CTA、誇大表現や景品表示法・特定商取引法の観点で気になる表現
  - LINE・メール配信文: 冒頭で読む理由が伝わるか、長さ、行動の明確さ、トーンの一貫性、誤解を招く表現
  - 提案資料・企画: 論理の飛躍、前提の弱さ、抜けている選択肢、数字の根拠、反論されそうな点
  - 方針・判断の相談: Claude の案に対する反対意見、見落としているリスク、別案

### 2. 個人情報を伏せる
本文を確認し、絶対ルール1に従って置き換える。置き換えた件数を控えておく（最後に報告する）。

### 3. プロンプトファイルを作る
Write ツールで一時ファイルを作る（このセッションに scratchpad ディレクトリがあればその中、なければ `/tmp/gpt-so-prompt.md`）。プロジェクトのフォルダ内には作らない。次のテンプレートを使う。

```
あなたは日本語の文章と事業企画に強い、率直な編集者・レビュアーです。
以下の【対象】だけを読んで判断してください。ファイルの探索やコマンドの実行は不要です。

【背景】
（例: オンラインサロン「Secret TeaRoom」の運営者が、見込み客向けに送る LINE 配信文。読者は〇〇な30〜40代女性。目的は〇〇）

【見てほしい観点】
- （手順1で決めた観点を箇条書き）

【出力形式】
1. 総評（3行以内）
2. 指摘（重大な順に最大10件）。各件:「該当箇所の引用」→「問題点」→「具体的な改善案」
3. 良い点（3つまで）
4. 判断に自信がない点（あれば）

【対象】
（ここに伏せ字処理済みの本文）
```

### 4. 実行する
Bash ツールで次を実行する。Bash ツールの `timeout` は 600000（10分）を指定する。

```bash
"$HOME/.claude/skills/gpt-second-opinion/run.sh" "<プロンプトファイルの絶対パス>"
```

- モデルを指定されたとき: 末尾に `--model <slug>` を付ける。
- 長い資料で時間がかかりそうなとき: 末尾に `--timeout 540` を付ける（既定は300秒）。

### 5. 終了コードで分岐する

| 終了コード | 意味 | Claude の対応 |
|---|---|---|
| 0 | 成功。標準出力に GPT の回答と回答ファイルのパスが出る | 手順6へ |
| 2 | codex が見つからない | 「Codex CLI が未導入か、場所が見つかりません」と伝え、セットアップ手順（Homebrew なら `brew install --cask codex`）を案内する。ターミナルでは使えるのに Claude から見つからない場合は、ユーザーにターミナルで `which codex` を実行してもらい、表示されたパスを `CODEX_BIN=<パス>` として run.sh の前に付けて再実行する |
| 3 | 未ログイン・認証切れ | 「ご本人がターミナルで `codex login` を実行し、ブラウザで ChatGPT にサインインしてください。終わったら教えてください」と伝えて止まる。代行しない |
| 4 | メール・電話番号らしき文字列を検出して送信を中止 | 該当箇所を伏せ字にしてプロンプトファイルを作り直し、もう一度だけ実行する |
| 5 | 利用上限に達した可能性 | 再試行しない。「ChatGPT プランの Codex 利用枠の上限に達したようです。リセットを待つか、ターミナルで `codex` を起動して `/status` で残量を確認できます」と伝え、GPT なしで Claude の意見だけを示す |
| 6 | タイムアウト | 対象を短くするか観点を絞って、1回だけ再実行してよい。それでもだめなら報告して止まる |
| 1・64 | その他の失敗・引数エラー | 表示されたログ末尾を要約して伝える。ログの中身に認証情報らしきものがあれば表示しない |

### 6. 結果をユーザーに提示する
次の形でまとめる。GPT の回答全文を貼り付けるのではなく、Claude が整理する。

1. **GPT の主な指摘**（重要なものから）と、それぞれに対する **Claude の判断**（採用／一部採用／不採用）と理由
2. **Claude と GPT で意見が分かれた点**（ユーザーが判断すべき点）
3. 採用案を反映した修正案（ユーザーが求めたとき、または修正が小さいとき。ファイルへの反映はユーザーの了承を得てから）
4. 末尾に一行: 「GPT（Codex CLI・既定モデル）に読み取り専用で1回問い合わせ。伏せ字にした個人情報: N 件」

最後に、作ったプロンプトファイルを削除する（`rm <プロンプトファイル>`）。回答ファイルは macOS の一時フォルダ（`$TMPDIR`）にあり、再起動などで自動的に消える。
~~~~

### 3-1b. run.sh 全文（macOS 標準の bash 3.2 で動く書き方）

~~~~bash
#!/bin/bash
# gpt-second-opinion: Claude Code から公式 Codex CLI（ChatGPTログイン）を読み取り専用で1回呼ぶ
# 使い方: run.sh <プロンプトファイル> [--model <slug>] [--timeout <秒>]
# 終了コード: 0=成功 2=codex未インストール 3=未ログイン/認証切れ 4=個人情報らしき文字列を検出
#             5=利用上限到達 6=タイムアウト 64=引数エラー 1=その他
set -u

PROMPT_FILE="${1:-}"
if [ -z "$PROMPT_FILE" ] || [ ! -s "$PROMPT_FILE" ]; then
  echo "[gpt-so] プロンプトファイルを指定してください（空のファイルは不可）" >&2; exit 64
fi
shift
MODEL=""
TIMEOUT_SEC="${GPT_SO_TIMEOUT:-300}"
while [ $# -gt 0 ]; do
  case "$1" in
    --model)   MODEL="${2:-}"; shift 2 ;;
    --timeout) TIMEOUT_SEC="${2:-300}"; shift 2 ;;
    *) echo "[gpt-so] 不明なオプション: $1" >&2; exit 64 ;;
  esac
done

# 1) 個人情報ガード（メールアドレス・電話番号らしき文字列があれば送らない）
if grep -Eq '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}' "$PROMPT_FILE"; then
  echo "[gpt-so] メールアドレスらしき文字列を検出したため送信を中止しました。[メール] などに置き換えてください。" >&2; exit 4
fi
if grep -Eq '0[0-9]{1,4}-[0-9]{1,4}-[0-9]{3,4}|0[789]0[0-9]{8}' "$PROMPT_FILE"; then
  echo "[gpt-so] 電話番号らしき文字列を検出したため送信を中止しました。[電話] などに置き換えてください。" >&2; exit 4
fi

# 2) PATH 対策（Claude Code の Bash はログインシェルの PATH を読まないことがある）
PATH="/opt/homebrew/bin:/usr/local/bin:$HOME/.local/bin:$HOME/.npm-global/bin:$HOME/.volta/bin:$PATH"
for d in "$HOME"/.nvm/versions/node/*/bin; do [ -d "$d" ] && PATH="$d:$PATH"; done
export PATH
CODEX="${CODEX_BIN:-$(command -v codex 2>/dev/null || true)}"
if [ -z "$CODEX" ] || [ ! -x "$CODEX" ]; then
  echo "[gpt-so] codex コマンドが見つかりません。ターミナルで 'brew install --cask codex' 等で導入してください（手順書 §3-2）。" >&2; exit 2
fi
case "$CODEX" in /*) ;; *) CODEX="$(cd "$(dirname "$CODEX")" && pwd)/$(basename "$CODEX")" ;; esac

# 3) ログイン確認（ログイン操作そのものは本人がターミナルで行う）
if ! "$CODEX" login status >/dev/null 2>&1; then
  echo "[gpt-so] Codex にログインしていません。ご本人がターミナルで 'codex login' を実行し、ブラウザで ChatGPT にサインインしてください。" >&2; exit 3
fi

# 4) 空の作業フォルダで実行（プロジェクトや会員データのあるフォルダを作業場所にしない）
WORK="$(mktemp -d "${TMPDIR:-/tmp}/gpt-so.XXXXXX")" || exit 1
cp "$PROMPT_FILE" "$WORK/prompt.md"
OUT="$WORK/answer.md"
LOG="$WORK/codex.log"

run_with_timeout() {
  if command -v timeout >/dev/null 2>&1; then timeout "$TIMEOUT_SEC" "$@"
  elif command -v gtimeout >/dev/null 2>&1; then gtimeout "$TIMEOUT_SEC" "$@"
  else perl -e '$t = shift @ARGV; alarm $t; exec @ARGV or die "exec failed: $!\n"' "$TIMEOUT_SEC" "$@"
  fi
}

ARGS=(exec -s read-only --ephemeral --skip-git-repo-check --color never -C "$WORK" -o "$OUT")
if [ -n "$MODEL" ]; then ARGS+=(-m "$MODEL"); fi
ARGS+=(-)

( cd "$WORK" && run_with_timeout "$CODEX" "${ARGS[@]}" < "$WORK/prompt.md" ) > "$LOG" 2>&1
RC=$?

if [ $RC -eq 0 ] && [ -s "$OUT" ]; then
  echo "[gpt-so] OK  回答ファイル: $OUT"
  echo "----- GPT の回答 -----"
  cat "$OUT"
  exit 0
fi
if [ $RC -eq 124 ] || [ $RC -eq 142 ]; then
  echo "[gpt-so] ${TIMEOUT_SEC}秒でタイムアウトしました。対象を短くするか --timeout を延ばしてください。ログ: $LOG" >&2; exit 6
fi
# 判定はエラー/警告行のみを対象にする（ログには送った本文も記録されるため）
if grep -Ei 'error|warn' "$LOG" | grep -Eiq 'usage limit|rate limit|limit reached|too many requests|429|quota|credits'; then
  echo "[gpt-so] ChatGPT プランの利用上限に達した可能性があります。リセットを待つか、ターミナルで codex を起動して /status で残量を確認してください（クレジットの追加購入はご本人の判断で）。ログ: $LOG" >&2; exit 5
fi
if grep -Ei 'error|warn' "$LOG" | grep -Eiq '401|unauthorized|not logged in|refresh_token|re-?authenticate|login'; then
  echo "[gpt-so] 認証が切れている可能性があります。ご本人がターミナルで 'codex login' をやり直してください。ログ: $LOG" >&2; exit 3
fi
echo "[gpt-so] 失敗しました（終了コード $RC）。ログ末尾:" >&2
tail -n 30 "$LOG" >&2
exit 1
~~~~

---

### 3-2. Mac セットアップ手順（非エンジニア向け・コピペで実行）

**準備**: 「ターミナル」アプリを開く（⌘＋スペースで「ターミナル」と入力して Enter）。以下の灰色の枠を1つずつコピーして貼り付け、Enter を押す。

**手順1. ChatGPT の学習設定を OFF にする（ブラウザで・最初に必ず）**
chatgpt.com にログイン → 左下のアカウント名 → 設定（Settings）→ データコントロール（Data controls）→「すべての人のためにモデルを改善する（Improve the model for everyone）」を OFF。個人プランではこの設定が Codex にも適用される（https://help.openai.com/en/articles/7730893-data-controls-in-chatgpt 、https://help.openai.com/en/articles/11369540-using-codex-with-your-chatgpt-plan 、いずれも検索抜粋）。
あわせて、設定の「使用量（Usage）」でクレジットの **自動リロードが OFF** になっていることを確認する（https://help.openai.com/en/articles/12642688-using-credits-for-flexible-usage-in-chatgpt-personal-plans 、検索抜粋）。

**手順2. Codex CLI を入れる**
まず Homebrew があるか確認:
```bash
command -v brew && echo "Homebrew あり" || echo "Homebrew なし"
```
- 「Homebrew あり」と出たら:
  ```bash
  brew install --cask codex
  ```
- 「Homebrew なし」と出たら（Node.js 不要の公式インストーラー）:
  ```bash
  curl -fsSL https://chatgpt.com/codex/install.sh | sh
  ```
- （Node.js を普段使っている人だけ）`npm install -g @openai/codex` でも可。**`npm install -g codex` は別物なので不可**。

入ったか確認（バージョン番号が出れば OK。「command not found」なら、ターミナルを一度閉じて開き直してからもう一度）:
```bash
codex --version
```
出典: https://github.com/openai/codex/blob/main/README.md （要件: macOS 12 以上、https://github.com/openai/codex/blob/main/docs/install.md ）

**手順3. ChatGPT でログインする（必ずご本人が操作）**
```bash
codex login
```
ブラウザが開くので、普段の ChatGPT アカウントでサインインして許可する。終わったら確認:
```bash
codex login status
```
「Not logged in」と出なければ OK（ログイン済みの場合の表示文言は未確認）。
※ パスワード、ブラウザに出るコード、`~/.codex/auth.json` の中身は、Claude にもチャットにも貼らない（https://developers.openai.com/codex/auth 、検索抜粋）。

**手順4. Skill の2ファイルを置く**
次の2つのブロックをそれぞれ丸ごとコピーして貼り付ける（`<<'EOF'` から最後の `EOF` までを含めて1回で貼る）。

ブロック1（SKILL.md）:
~~~~bash
mkdir -p ~/.claude/skills/gpt-second-opinion
cat > ~/.claude/skills/gpt-second-opinion/SKILL.md <<'EOF'
---
name: gpt-second-opinion
description: OpenAI の GPT（公式 Codex CLI・ChatGPT プランのログイン）に、文章・LP・LINE/メール配信文・提案資料・企画や方針のセカンドオピニオンを読み取り専用で1回だけ求める。「GPTに聞いて」「GPTの意見」「セカンドオピニオン」「Codexにレビューさせて」「別のAIにも見てもらって」と言われたとき、または重要な配信文・LP・提案資料を確定する前に使う。コードの差分レビューは /codex:review（公式プラグイン）を優先する。
---

# GPT セカンドオピニオン

Claude が作業中の文章や方針について、OpenAI の GPT に独立した意見を1回だけ求め、Claude が採否を判断してユーザーに提示する。GPT はユーザーの Mac にある公式 Codex CLI（`codex exec`）を、ユーザー本人の ChatGPT ログインで呼ぶ。API キーは使わない。

実行は同じフォルダの `run.sh` が行う。run.sh は read-only サンドボックス、セッションを保存しない（`--ephemeral`）、空の一時フォルダで実行、最終回答をファイルに出力（`-o`）、タイムアウト、PATH の補正、ログイン確認、メール・電話番号の検出をまとめて処理する。

## 絶対ルール

1. **個人情報を送らない。** 会員・顧客の氏名、メールアドレス、電話番号、LINE の表示名や ID、住所、購入・決済の履歴、個別の相談内容は送信前に置き換える（例: 「会員A」「[メール]」「[電話]」「[住所]」）。会員リスト、CSV、スプレッドシートの行データ、UTAGE や Gmail から取得した生データはそのまま送らない。伏せると成り立たない依頼なら、送る前にユーザーに確認する。
2. **GPT にファイルを書かせない・コマンドを実行させない。** run.sh 以外の方法で codex を呼ばない。`--dangerously-bypass-approvals-and-sandbox`、`--sandbox workspace-write`、`danger-full-access`、`--approve-for-me` は使わない。
3. **ログインを代行しない。** 未ログインや認証切れのときは、ユーザー本人にターミナルで `codex login` を実行してもらう。パスワード、デバイスコード、`~/.codex/auth.json` の中身を聞いたり表示したりしない。
4. **1回の依頼で呼ぶのは原則1回（多くても2回）。** 自動で何度も往復させない。上限に達したら再試行しない。クレジットの購入や自動リロードを勧めない（判断はユーザー本人）。
5. **GPT の意見は参考意見。** 指摘を自動で反映しない。事実関係（料金、日付、法令、数値）の指摘は Claude が確認してから扱う。
6. **モデルは指定しない（既定に任せる）。** ユーザーがモデルを指定したときだけ `--model <slug>` を付ける。使える slug がわからなければ、ユーザーにターミナルで `codex debug models` を実行してもらい確認する。

## 手順

### 1. 対象と観点を決める
- 対象: 作業中のファイル、またはユーザーが貼った文章。長いときは、レビューに必要な部分に絞る（目安: 本文 8,000 字以内）。
- 観点: ユーザーの指定がなければ、種類に応じて次から選ぶ。
  - LP・セールス文: 読者（サロンの見込み客）に刺さるか、ベネフィットの明確さ、不安の解消、CTA、誇大表現や景品表示法・特定商取引法の観点で気になる表現
  - LINE・メール配信文: 冒頭で読む理由が伝わるか、長さ、行動の明確さ、トーンの一貫性、誤解を招く表現
  - 提案資料・企画: 論理の飛躍、前提の弱さ、抜けている選択肢、数字の根拠、反論されそうな点
  - 方針・判断の相談: Claude の案に対する反対意見、見落としているリスク、別案

### 2. 個人情報を伏せる
本文を確認し、絶対ルール1に従って置き換える。置き換えた件数を控えておく（最後に報告する）。

### 3. プロンプトファイルを作る
Write ツールで一時ファイルを作る（このセッションに scratchpad ディレクトリがあればその中、なければ `/tmp/gpt-so-prompt.md`）。プロジェクトのフォルダ内には作らない。次のテンプレートを使う。

```
あなたは日本語の文章と事業企画に強い、率直な編集者・レビュアーです。
以下の【対象】だけを読んで判断してください。ファイルの探索やコマンドの実行は不要です。

【背景】
（例: オンラインサロン「Secret TeaRoom」の運営者が、見込み客向けに送る LINE 配信文。読者は〇〇な30〜40代女性。目的は〇〇）

【見てほしい観点】
- （手順1で決めた観点を箇条書き）

【出力形式】
1. 総評（3行以内）
2. 指摘（重大な順に最大10件）。各件:「該当箇所の引用」→「問題点」→「具体的な改善案」
3. 良い点（3つまで）
4. 判断に自信がない点（あれば）

【対象】
（ここに伏せ字処理済みの本文）
```

### 4. 実行する
Bash ツールで次を実行する。Bash ツールの `timeout` は 600000（10分）を指定する。

```bash
"$HOME/.claude/skills/gpt-second-opinion/run.sh" "<プロンプトファイルの絶対パス>"
```

- モデルを指定されたとき: 末尾に `--model <slug>` を付ける。
- 長い資料で時間がかかりそうなとき: 末尾に `--timeout 540` を付ける（既定は300秒）。

### 5. 終了コードで分岐する

| 終了コード | 意味 | Claude の対応 |
|---|---|---|
| 0 | 成功。標準出力に GPT の回答と回答ファイルのパスが出る | 手順6へ |
| 2 | codex が見つからない | 「Codex CLI が未導入か、場所が見つかりません」と伝え、セットアップ手順（Homebrew なら `brew install --cask codex`）を案内する。ターミナルでは使えるのに Claude から見つからない場合は、ユーザーにターミナルで `which codex` を実行してもらい、表示されたパスを `CODEX_BIN=<パス>` として run.sh の前に付けて再実行する |
| 3 | 未ログイン・認証切れ | 「ご本人がターミナルで `codex login` を実行し、ブラウザで ChatGPT にサインインしてください。終わったら教えてください」と伝えて止まる。代行しない |
| 4 | メール・電話番号らしき文字列を検出して送信を中止 | 該当箇所を伏せ字にしてプロンプトファイルを作り直し、もう一度だけ実行する |
| 5 | 利用上限に達した可能性 | 再試行しない。「ChatGPT プランの Codex 利用枠の上限に達したようです。リセットを待つか、ターミナルで `codex` を起動して `/status` で残量を確認できます」と伝え、GPT なしで Claude の意見だけを示す |
| 6 | タイムアウト | 対象を短くするか観点を絞って、1回だけ再実行してよい。それでもだめなら報告して止まる |
| 1・64 | その他の失敗・引数エラー | 表示されたログ末尾を要約して伝える。ログの中身に認証情報らしきものがあれば表示しない |

### 6. 結果をユーザーに提示する
次の形でまとめる。GPT の回答全文を貼り付けるのではなく、Claude が整理する。

1. **GPT の主な指摘**（重要なものから）と、それぞれに対する **Claude の判断**（採用／一部採用／不採用）と理由
2. **Claude と GPT で意見が分かれた点**（ユーザーが判断すべき点）
3. 採用案を反映した修正案（ユーザーが求めたとき、または修正が小さいとき。ファイルへの反映はユーザーの了承を得てから）
4. 末尾に一行: 「GPT（Codex CLI・既定モデル）に読み取り専用で1回問い合わせ。伏せ字にした個人情報: N 件」

最後に、作ったプロンプトファイルを削除する（`rm <プロンプトファイル>`）。回答ファイルは macOS の一時フォルダ（`$TMPDIR`）にあり、再起動などで自動的に消える。
EOF
~~~~

ブロック2（run.sh）:
~~~~bash
cat > ~/.claude/skills/gpt-second-opinion/run.sh <<'EOF'
#!/bin/bash
# gpt-second-opinion: Claude Code から公式 Codex CLI（ChatGPTログイン）を読み取り専用で1回呼ぶ
# 使い方: run.sh <プロンプトファイル> [--model <slug>] [--timeout <秒>]
# 終了コード: 0=成功 2=codex未インストール 3=未ログイン/認証切れ 4=個人情報らしき文字列を検出
#             5=利用上限到達 6=タイムアウト 64=引数エラー 1=その他
set -u

PROMPT_FILE="${1:-}"
if [ -z "$PROMPT_FILE" ] || [ ! -s "$PROMPT_FILE" ]; then
  echo "[gpt-so] プロンプトファイルを指定してください（空のファイルは不可）" >&2; exit 64
fi
shift
MODEL=""
TIMEOUT_SEC="${GPT_SO_TIMEOUT:-300}"
while [ $# -gt 0 ]; do
  case "$1" in
    --model)   MODEL="${2:-}"; shift 2 ;;
    --timeout) TIMEOUT_SEC="${2:-300}"; shift 2 ;;
    *) echo "[gpt-so] 不明なオプション: $1" >&2; exit 64 ;;
  esac
done

# 1) 個人情報ガード（メールアドレス・電話番号らしき文字列があれば送らない）
if grep -Eq '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}' "$PROMPT_FILE"; then
  echo "[gpt-so] メールアドレスらしき文字列を検出したため送信を中止しました。[メール] などに置き換えてください。" >&2; exit 4
fi
if grep -Eq '0[0-9]{1,4}-[0-9]{1,4}-[0-9]{3,4}|0[789]0[0-9]{8}' "$PROMPT_FILE"; then
  echo "[gpt-so] 電話番号らしき文字列を検出したため送信を中止しました。[電話] などに置き換えてください。" >&2; exit 4
fi

# 2) PATH 対策（Claude Code の Bash はログインシェルの PATH を読まないことがある）
PATH="/opt/homebrew/bin:/usr/local/bin:$HOME/.local/bin:$HOME/.npm-global/bin:$HOME/.volta/bin:$PATH"
for d in "$HOME"/.nvm/versions/node/*/bin; do [ -d "$d" ] && PATH="$d:$PATH"; done
export PATH
CODEX="${CODEX_BIN:-$(command -v codex 2>/dev/null || true)}"
if [ -z "$CODEX" ] || [ ! -x "$CODEX" ]; then
  echo "[gpt-so] codex コマンドが見つかりません。ターミナルで 'brew install --cask codex' 等で導入してください（手順書 §3-2）。" >&2; exit 2
fi
case "$CODEX" in /*) ;; *) CODEX="$(cd "$(dirname "$CODEX")" && pwd)/$(basename "$CODEX")" ;; esac

# 3) ログイン確認（ログイン操作そのものは本人がターミナルで行う）
if ! "$CODEX" login status >/dev/null 2>&1; then
  echo "[gpt-so] Codex にログインしていません。ご本人がターミナルで 'codex login' を実行し、ブラウザで ChatGPT にサインインしてください。" >&2; exit 3
fi

# 4) 空の作業フォルダで実行（プロジェクトや会員データのあるフォルダを作業場所にしない）
WORK="$(mktemp -d "${TMPDIR:-/tmp}/gpt-so.XXXXXX")" || exit 1
cp "$PROMPT_FILE" "$WORK/prompt.md"
OUT="$WORK/answer.md"
LOG="$WORK/codex.log"

run_with_timeout() {
  if command -v timeout >/dev/null 2>&1; then timeout "$TIMEOUT_SEC" "$@"
  elif command -v gtimeout >/dev/null 2>&1; then gtimeout "$TIMEOUT_SEC" "$@"
  else perl -e '$t = shift @ARGV; alarm $t; exec @ARGV or die "exec failed: $!\n"' "$TIMEOUT_SEC" "$@"
  fi
}

ARGS=(exec -s read-only --ephemeral --skip-git-repo-check --color never -C "$WORK" -o "$OUT")
if [ -n "$MODEL" ]; then ARGS+=(-m "$MODEL"); fi
ARGS+=(-)

( cd "$WORK" && run_with_timeout "$CODEX" "${ARGS[@]}" < "$WORK/prompt.md" ) > "$LOG" 2>&1
RC=$?

if [ $RC -eq 0 ] && [ -s "$OUT" ]; then
  echo "[gpt-so] OK  回答ファイル: $OUT"
  echo "----- GPT の回答 -----"
  cat "$OUT"
  exit 0
fi
if [ $RC -eq 124 ] || [ $RC -eq 142 ]; then
  echo "[gpt-so] ${TIMEOUT_SEC}秒でタイムアウトしました。対象を短くするか --timeout を延ばしてください。ログ: $LOG" >&2; exit 6
fi
# 判定はエラー/警告行のみを対象にする（ログには送った本文も記録されるため）
if grep -Ei 'error|warn' "$LOG" | grep -Eiq 'usage limit|rate limit|limit reached|too many requests|429|quota|credits'; then
  echo "[gpt-so] ChatGPT プランの利用上限に達した可能性があります。リセットを待つか、ターミナルで codex を起動して /status で残量を確認してください（クレジットの追加購入はご本人の判断で）。ログ: $LOG" >&2; exit 5
fi
if grep -Ei 'error|warn' "$LOG" | grep -Eiq '401|unauthorized|not logged in|refresh_token|re-?authenticate|login'; then
  echo "[gpt-so] 認証が切れている可能性があります。ご本人がターミナルで 'codex login' をやり直してください。ログ: $LOG" >&2; exit 3
fi
echo "[gpt-so] 失敗しました（終了コード $RC）。ログ末尾:" >&2
tail -n 30 "$LOG" >&2
exit 1
EOF
chmod +x ~/.claude/skills/gpt-second-opinion/run.sh
echo "設置完了"
~~~~

（貼り付けが難しければ、Mac の Claude Code に「このファイルの §3-1a と §3-1b の内容で `~/.claude/skills/gpt-second-opinion/` に SKILL.md と run.sh を作り、run.sh に実行権限を付けて」と頼んでもよい。ログイン以外はファイル作成だけなので代行して問題ない。）

### 3-3. 動作確認

**確認1. ターミナルで直接（Claude を通さずに）**
```bash
printf 'これは接続テストです。「接続OK」とだけ答えてください。\n' > /tmp/gpt-so-test.md
~/.claude/skills/gpt-second-opinion/run.sh /tmp/gpt-so-test.md; echo "終了コード: $?"
```
期待: 「----- GPT の回答 -----」の下に「接続OK」、終了コード 0。
- 終了コード 2 → 手順2をやり直す。3 → 手順3をやり直す。6 → ネットワークを確認して再実行。

**確認2. 個人情報ガード**
```bash
printf 'テスト sample@example.com\n' > /tmp/gpt-so-test2.md
~/.claude/skills/gpt-second-opinion/run.sh /tmp/gpt-so-test2.md; echo "終了コード: $?"
rm -f /tmp/gpt-so-test.md /tmp/gpt-so-test2.md
```
期待: 「メールアドレスらしき文字列を検出したため送信を中止しました」、終了コード 4（GPT には何も送られない）。

**確認3. Claude Code から**
Claude Code を新しく起動し（Skill は起動時に読み込まれる）、短い文章を用意して次のように頼む:
> 「次の LINE 配信文を GPT にセカンドオピニオンしてもらって。観点は読みやすさと行動のわかりやすさ。（本文）」

期待: Claude が run.sh を実行し（初回は Bash 実行の許可を求められるので許可する）、GPT の指摘と Claude の採否・理由が返る。末尾に「GPT に読み取り専用で1回問い合わせ。伏せ字にした個人情報: N 件」が付く。
- Skill が使われない場合は「gpt-second-opinion スキルを使って」と名前で頼む。
- 「codex が見つからない（終了コード 2）」がターミナルでは起きず Claude からだけ起きる場合: ターミナルで `which codex` を実行し、出たパスを Claude に伝える（Claude が `CODEX_BIN=<パス>` を付けて実行する）。

**確認4（任意）. 残量の確認方法**
ターミナルで `codex` を起動し、`/status` と入力すると利用枠の残量が見られる（https://help.openai.com/en/articles/11369540-codex-usage-limits 、検索抜粋）。終了は `/exit` または Ctrl+C。

**Cowork での確認（任意・未確認事項）**: Cowork で同じ依頼をして、Skill が見えるか、run.sh が Mac の codex とログイン状態にアクセスできるかを試す。動かなければ Claude Code（ターミナル／Desktop の Code タブ）で使う運用にする（C5）。

### 3-4. 公式プラグイン codex-plugin-cc を併用する場合（後日・コードレビュー用）

出典: https://github.com/openai/codex-plugin-cc （README を本文確認）。Codex CLI のログイン状態（`~/.codex`）をそのまま使うので、手順3が済んでいれば追加のログインは不要のはず。

Mac の Claude Code（ターミナル版）で1行ずつ入力:
```
/plugin marketplace add openai/codex-plugin-cc
/plugin install codex@openai-codex
/reload-plugins
/codex:setup
```
`/codex:setup` で Codex の導入とログインの状態が確認される。未ログインと出たら、ご本人が `!codex login` を実行する。

使い分け:
| やりたいこと | 使うもの |
|---|---|
| 文章・LP・配信文・提案資料・方針へのセカンドオピニオン | **自作 Skill**（「GPT にセカンドオピニオンして」） |
| HTML リポジトリなどコード変更のレビュー | `/codex:review --background` → `/codex:status` → `/codex:result` |
| 設計や前提を疑う反論型レビュー（観点を指定） | `/codex:adversarial-review "<観点>"` |

使わない・有効にしないもの:
- `/codex:setup --enable-review-gate`（Claude の応答のたびに Codex がレビューする。README 自身が「usage limits を急速に消費し得る」と警告。issue #790 では同じ指摘で停止がブロックされ続ける報告）。
- `/codex:rescue`（既定で書き込み可能な委任になるという報告、issue #798）。レビュー目的では使わない。
- 既知の不具合（2026-10-22 時点で open）: ハング（#793, #781）、refresh token の再利用エラー（#789）、broker プロセスのリーク（#801 ほか）。プラグインと自作 Skill は同じ Codex の認証を共有するので、どちらかで認証エラーが出たら `codex login` をやり直す。
- クラウド（claude.ai/code）では `/plugin` が使えない（https://code.claude.com/docs/en/claude-code-on-the-web ）。

---

## 4. ユーザーに判断を仰ぐ項目（3つ）

1. **現在の ChatGPT のプランはどれか（Go / Plus / Pro / Business）。学習 OFF にしてよいか。**
   Plus 以上なら推奨案はそのまま使える。Go は CLI 対応やモデルの範囲が **未確認**（C4）。Business は既定で学習に使われない。
2. **会員・顧客に関する情報の扱い。** 推奨の既定は「個人を特定できる情報は一切送らず、伏せ字にしたうえで文章だけ送る」。匿名化した個別の相談内容（例: 「会員A の退会理由」）まで送ってよいか、それとも会員に関わる内容は GPT に送らないか。
3. **今後、公式プラグイン（コードレビュー）や API キー（クラウド・Cowork から使う／画像を多く作る）を追加する予定があるか。** ある場合、API の月額予算の上限（目安: テキスト中心なら月 $20〜40 程度、03a §3）をどこに置くか。

---

## 出典（主要なもの。詳細は各リサーチファイル）
- Codex CLI README / install: https://github.com/openai/codex/blob/main/README.md 、https://github.com/openai/codex/blob/main/docs/install.md
- codex-plugin-cc README / issues: https://github.com/openai/codex-plugin-cc 、https://github.com/openai/codex-plugin-cc/issues
- `codex mcp-server` 削除: https://x.com/CodexReleases/status/2097817398040551429 、https://www.developersdigest.tech/blog/codex-mcp-server-removed 、https://codex.danielvaughan.com/2026/08/30/codex-mcp-server-deprecated-migration-app-server-agents-sdk/
- 認証・CI: https://developers.openai.com/codex/auth 、https://developers.openai.com/codex/auth/ci-cd-auth （検索抜粋）
- 料金・上限: https://developers.openai.com/codex/pricing 、https://help.openai.com/en/articles/11369540-using-codex-with-your-chatgpt-plan （検索抜粋）
- 画像生成: https://developers.openai.com/codex/image-generation （検索抜粋）
- 規約: https://openai.com/policies/terms-of-use/ 、https://openai.com/policies/sign-in-with-chatgpt-terms/ （検索抜粋）
- データ管理: https://help.openai.com/en/articles/7730893-data-controls-in-chatgpt （検索抜粋）
- Claude Code クラウド: https://code.claude.com/docs/en/cloud-environments 、https://code.claude.com/docs/en/claude-code-on-the-web
