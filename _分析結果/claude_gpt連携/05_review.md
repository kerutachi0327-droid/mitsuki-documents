# 05 レビュー＆検証：Claude Code → GPT 連携（04_strategy と skilltest/）

作成日: 2026-10-22／担当: レビュー＆検証
対象: 00_material.md、03a/03b/03c、04_strategy.md、skilltest/SKILL.md・run.sh
検証環境: このクラウド環境（Linux、GNU bash 5.2、@openai/codex 0.163.0 を npm 導入）。OpenAI 系ドメインは 403 なので、**ログインと実際の推論は一度も通していない**。

表記: **[事実]** 実機または出典で確認できたこと／**[示唆]** 事実からの判断／**[未確認]** 確認できなかったこと

---

## 1. 検証結果の一覧

| # | 項目 | 判定 | 根拠 |
|---|---|---|---|
| 1-1 | run.sh の構文（`bash -n`）・shellcheck 0.11.0 | **合格**（修正前も修正後も警告0件） | ローカル実行 |
| 1-2 | `codex exec` のフラグが 0.163.0 に実在するか | **合格** | `codex exec --help`。`-s read-only`／`--ephemeral`／`--skip-git-repo-check`／`--color never`／`-C`／`-o`／`-m`／`-`（stdin）はすべて実在。SKILL の禁止フラグ `--approve-for-me`／`--dangerously-bypass-approvals-and-sandbox` も実在 |
| 1-3 | 引数処理 | **要修正 → 修正済み** | `--model` や `--timeout` を値なしで渡すと `shift 2` が失敗して**無限ループ**（5秒の外部タイムアウトで停止を確認）。`--timeout abc` は GNU では終了コード125で「その他の失敗」、perl 版では `alarm 0` で**タイムアウトが効かなくなる**。ディレクトリを渡すと grep エラーのまま先へ進む |
| 1-4 | 未ログイン時の挙動 | **合格** | 実 codex の `codex login status` は未ログインで `Not logged in`／終了コード1 → run.sh は 3 を返す（スタブでも確認） |
| 1-5 | 個人情報検出 | **要修正 → 修正済み**（残存リスクあり） | 修正前は `+81 90-…`、`090 1234 5678`（空白区切り）、全角の `０９０－１２３４－５６７８`、括弧付き `090(1234)5678`、全角メール `ＡＢＣ＠ｅｘａｍｐｌｅ．ｃｏｍ` を**素通し**、`01-01-2026`（日付）を誤検出。修正後はこれらを検出し、日付・`10000000円`・`2026-10-22`・郵便番号・ISBN は通す（§2 の表） |
| 1-6 | タイムアウト | **要修正 → 修正済み** | **npm 版 codex（node のラッパーが本体を子プロセスで起動）では、perl の `alarm` 方式がラッパーだけを止め、本体 codex が残り続ける**ことを実 codex で確認。macOS は標準で `timeout` が無いので、npm で入れた Mac ではこの経路になる。修正後はプロセスグループごと TERM→KILL し、残留0を確認。GNU `timeout` 経路は修正前から残留0 |
| 1-7 | 終了コード（スタブで模擬） | **合格（修正後）** | 0 成功／2 codex なし／3 未ログイン・認証切れ／4 個人情報／5 上限／6 タイムアウト／64 引数／1 その他、をすべて再現。修正前は「認証切れ」と「`ERROR:` の付かない上限メッセージ」を 1（その他）と誤判定 |
| 1-8 | 上限・認証切れの検出文言 | **一部確認（推定を含む）** | codex 本体のバイナリ内の文字列に `You've hit your usage limit. Visit https://chatgpt.com/settings/usage to purchase more credits` などと、`Your access token could not be refreshed. Please log out and sign in again.` があることを確認。修正前の正規表現は後者に一致しなかった。**exec の出力でこれらが実際にどの形で出るか（`ERROR:` が付くか）は未確認** |
| 1-9 | macOS 互換（bash 3.2／BSD） | **未検証（静的レビューのみ）** | bash 3.2 のソースは取得が 403 で、実行確認できず。使っている構文（配列と `+=`、`case`、`trap EXIT`、`command -v`、`mktemp -d テンプレート`、`grep -E/-F/-x/-f`、`tail -n`、perl の `fork`・`setpgrp`・`Unicode::Normalize`）は bash 3.2・BSD・macOS 同梱 perl の範囲と判断。`[[ ]]`・連想配列・`${var,,}`・`mapfile` は使っていない |
| 2-1 | SKILL.md の frontmatter | **合格** | YAML として読める（`name`、`description` のみ）。description は255字で、公式の上限（description と when_to_use の合計 1,536 字で切り詰め）内。Personal skill の置き場所 `~/.claude/skills/<name>/SKILL.md` も公式どおり（https://code.claude.com/docs/en/skills ） |
| 2-2 | SKILL.md の指示 | **要修正 → 修正済み**（軽微） | §3 の「修正した点」を参照。`codex debug models` は JSON を大量に出すだけで非エンジニア向きでない、など |
| 3 | 事実主張 | **一部合格**（§4 に未裏付けの一覧） | モデル名と `mcp-server` 廃止は CLI 同梱データで裏付けあり。料金・上限の数値は検索抜粋のみ |
| 4 | Mac 手順 | **合格（1点注意）** | Homebrew cask `codex` は 0.163.0・`bin/codex`（ネイティブ）を配布、install.sh の置き場所は `~/.local/bin`、npm は `@openai/codex`。**ただし 04 §3-1／§3-2 に埋め込まれた SKILL.md と run.sh は修正前の版**（§5 参照） |
| 5 | 推奨の妥当性 | **妥当** | B（自作 Skill ＋ `codex exec`）を先に入れる段階導入に同意。注意点は §6 |
| — | 成功系（ログイン後の実際の回答）・上限到達・認証切れの実メッセージ | **未検証** | このクラウド環境ではネットワーク拒否のため。Mac での確認1（04 §3-3）が最初の実地テストになる |

---

## 2. 実地テストの記録（修正後の run.sh）

テストの方法: PATH の先頭にスタブの `codex`（引数・作業フォルダを記録し、環境変数で成功／上限／認証切れ／500エラー／空回答／ハング／ラッパー型ハングを模擬）を置いて実行。タイムアウトと残留プロセスは**本物の codex 0.163.0**（未ログインでネットワーク待ちになる性質を利用）でも確認した。

| ケース | 修正前 | 修正後 |
|---|---|---|
| 引数なし／空ファイル／存在しないファイル | 64 | 64 |
| ディレクトリを渡す | 1（grep エラー後に先へ進む） | 64 |
| `--model`（値なし） | **無限ループ** | 64 |
| `--timeout`（値なし） | **無限ループ** | 64 |
| `--timeout abc`／`--timeout 0` | 1（125）／タイムアウト無効 | 64 |
| メール `a.b+c@example.co.jp` | 4 | 4 |
| `090-1234-5678`／`09012345678`／`03-1234-5678`／`0120-123-456` | 4 | 4 |
| `+81 90-1234-5678`／`+81-3-1234-5678` | 0（素通し） | 4 |
| `090 1234 5678`／`090(1234)5678`／`(03) 1234-5678` | 0（素通し） | 4 |
| 全角 `０９０－１２３４－５６７８`／`０３（１２３４）５６７８`／`090ー1234ー5678` | 0（素通し） | 4 |
| 全角メール `ＡＢＣ＠ｅｘａｍｐｌｅ．ｃｏｍ` | 0（素通し） | 4 |
| `01-01-2026`（日付） | 4（誤検出） | 0 |
| `2026-10-22`／`10000000円`／`150-0001`／ISBN | 0 | 0 |
| `注文番号 0123456789`（0始まり10桁） | 0 | 4（誤検出。SKILL に明記） |
| `+81 (0)3-1234-5678` | 0 | 0（**未対応**、残存リスク） |
| perl が壊れている場合のメール | — | 4（grep の判定に落ちる） |
| codex なし | 2 | 2 |
| `CODEX_BIN` に相対パス | 0 | 0 |
| 未ログイン | 3 | 3 |
| 成功 | 0 | 0（成功時はログを削除） |
| 終了0だが回答が空 | 1 | 1（「回答が空」と表示） |
| 上限（`ERROR: You've hit your usage limit…`） | 5 | 5 |
| 上限（`ERROR:` なし） | 1 | 5 |
| 認証切れ（`Your access token could not be refreshed…`） | 1 | 3 |
| 500 エラー（本文に「ログインエラー」「usage limit」を含む） | 1 | 1（本文の行は判定から除外） |
| ハング・GNU `timeout` | 6（3秒） | 6（3秒） |
| ハング・perl（`timeout` の無い PATH） | 6 | 6（約8秒＝3秒＋終了待ち5秒） |
| **本物の npm 版 codex を perl 方式で打ち切り** | **6 だが本体 codex が残留**（直接実行で確認） | 6、残留0 |
| 本物の codex を GNU `timeout` で打ち切り | 6、残留0 | 6、残留0 |
| 制限オプション名が使えない codex（模擬） | — | 制限なしで1回だけ再実行して 0 |

実 codex の起動バナーで `model: gpt-6.1-sol`／`approval: never`／`sandbox: read-only` を確認。ログには送った本文が `user` の後にそのまま記録される（→ 判定から本文の行を除外する修正の根拠）。

---

## 3. 修正した点

### run.sh（修正前の版は /tmp/claude-0/-home-user-mitsuki-documents/685c9731-5707-5450-b351-0f3964f7ac3d/scratchpad/run.sh.orig に保存）
1. **引数の検証**: `--model`／`--timeout` の値なしを 64 で止める（無限ループの解消）。`--timeout` は 1〜3600 の整数のみ。プロンプトファイルは「存在する・読める・空でない通常ファイル」に限定。
2. **個人情報ガードを perl に変更**: NFKC で全角を半角にしてから判定。電話番号は `+81`、空白・括弧・長音符・各種ダッシュ区切りに対応し、数字が 10〜12 桁のときだけ検出（日付の誤検出を解消）。前後が数字の場合は一致させない（金額の誤検出を防止）。perl が無い・失敗したときは素通しせず、従来の grep 判定に落とす。
3. **タイムアウトの perl 代替を作り直し**: 子をプロセスグループにして、時間切れで TERM、5秒後に KILL。npm 版 codex の本体が残る問題を解消。GNU `timeout`／`gtimeout` にも `-k 10`（10秒後に KILL）を追加し、終了コード 137 もタイムアウトとして扱う。
4. **上限・認証切れの判定**: codex 本体に含まれる文言（`hit your usage limit`、`purchase more credits`、`access token could not be refreshed`、`sign in again`、`refresh_token_reused` など）を追加。判定前に、ログから**送った本文と同じ行を除外**して誤判定を防ぐ。
5. **GPT 側の機能を既定で停止**: `--disable shell_tool --disable unified_exec --disable apps --disable browser_use --disable computer_use`。read-only でもディスクの読み取りはできるため、レビュー対象の文章に「ファイルを読め」という指示が紛れ込んでも、GPT がコマンドを実行してローカルのファイル（会員 CSV など）を読めないようにする。機能名は 0.163.0 の `codex features list` で実在を確認し、本物の codex がこの指定で起動することも確認。将来その機能名が無くなって起動時に失敗した場合は、制限なしで1回だけ自動で再実行する（起動時の失敗なので本文は未送信）。`GPT_SO_HARDEN=0` で無効化できる。
6. **後片付け**: 作業フォルダにコピーした本文（prompt.md）は終了時に必ず削除。成功時はログも削除（回答は残す）。
7. エラーメッセージの「手順書 §3-2」（ユーザーの手元に無い）を削除。

### SKILL.md（修正前の版は /tmp/claude-0/-home-user-mitsuki-documents/685c9731-5707-5450-b351-0f3964f7ac3d/scratchpad/SKILL.md.orig）
1. 実行パスを公式の変数 `${CLAUDE_SKILL_DIR}/run.sh` に変更（https://code.claude.com/docs/en/skills ）。古い版で置き換わらない場合の代わりとして `$HOME/.claude/skills/gpt-second-opinion/run.sh` も残した。
2. description の「コードの差分レビューは /codex:review を優先」を「公式プラグインを導入済みなら」に限定（未導入のまま Claude が存在しないコマンドを試すのを防ぐ）。
3. モデル確認の方法を `codex debug models`（JSON の大量出力）から、`codex` を起動して `/model`（モデル選択画面。0.163.0 のバイナリ内に存在を確認）に変更。
4. `--timeout` の範囲（1〜3600秒、Bash ツールの上限10分に合わせて 540 まで）を明記。
5. 終了コード4: 全角や +81 も検出すること、0始まり10〜12桁の番号を誤検出し得ること、事業者自身の公開連絡先も伏せてよいことを追記。
6. 終了コード1・64: 64 は引数を直して1回だけ再実行可。tool／feature 関連のエラーのときだけ `GPT_SO_HARDEN=0` で1回だけ再実行可（ユーザーに一言伝える）。
7. 後片付け: 「回答ファイルは再起動などで自動的に消える」（根拠なし）を削除し、プロンプトファイルと作業フォルダ（`gpt-so.XXXXXX`）を Claude が削除する手順に変更。

### 触っていないもの
- skilltest/fakecodex は検証用のスタブ（このクラウド環境の絶対パスを含む）。**ユーザーの Mac には置かない**。
- 04_strategy.md 本体は修正していない（§5）。

---

## 4. 事実主張の裏付け

### 裏付けあり
| 主張 | 裏付け |
|---|---|
| モデル名 `gpt-6.1-sol`（既定候補）、`gpt-6-astra`／`gpt-6-sol`／`gpt-6-luna`／`gpt-5.6-*`／`gpt-5.5` | `codex debug models --bundled` の slug と priority（gpt-6.1-sol が priority 1）。未ログインでも起動バナーに `model: gpt-6.1-sol` |
| `codex mcp-server` は 0.163.0 に無い | `codex help mcp-server` → `unrecognized subcommand`。`codex mcp-server` を実行すると対話モードへのプロンプト扱いになり `stdin is not a terminal` で失敗（＝古い記事の `claude mcp add codex -- codex mcp-server` は動かない）。トップレベルの一覧にも無い |
| `codex mcp` は外部 MCP を使う側 | `codex --help`:「Manage external MCP servers for Codex」 |
| `codex login status` 未ログインで終了コード1 | ローカル実行 |
| `/status`・`/model` は Codex の TUI にある | バイナリ内の文字列（`/model - choose what model and reasoning effort to use`、`show current session configuration and token usage`） |
| 画像生成機能が有効 | `codex features list`: `image_generation stable true`（使い方・消費量は未確認） |
| インストール3方式・`brew install --cask codex`・`npm install -g @openai/codex` | https://github.com/openai/codex/blob/main/README.md 、Homebrew cask 定義 https://raw.githubusercontent.com/Homebrew/homebrew-cask/main/Casks/c/codex.rb （version 0.163.0、`binary "bin/codex"`） |
| install.sh の置き場所 `~/.local/bin` | https://raw.githubusercontent.com/openai/codex/main/scripts/install/install.sh （`BIN_DIR="${CODEX_INSTALL_DIR:-$HOME/.local/bin}"`）。run.sh の PATH 補正に含まれている |
| codex-plugin-cc の導入4コマンド、ChatGPT サブスク（Free 含む）対応、review gate の警告、`/codex:review` は観点を受け付けない | https://raw.githubusercontent.com/openai/codex-plugin-cc/main/README.md |
| クラウドでは `/plugin` が使えない | https://code.claude.com/docs/en/claude-code-on-the-web （"Commands that only run in the terminal interface, such as `/plugin` or `/resume`, aren't available."） |
| Skill の置き場所・ライブリロード・`${CLAUDE_SKILL_DIR}` | https://code.claude.com/docs/en/skills |

### 裏付けが不十分（検索抜粋・二次情報のみ、または未確認）
1. **プラン別の上限の数値**（Plus の GPT-6.1 Sol 15〜160／5時間 など）: 03a・03c とも検索抜粋のみ。今回の検索（2026-10-22）では GPT-6.1 Sol の上限を示す結果が出ず、旧モデルの数値が出典ごとに食い違っていた。**未確認**。
2. **API 料金**（gpt-6.1-sol $2/$10、astra $10/$50、luna $0.10/$0.50、GPT Image 2 $0.053/枚など）と、それに基づく月額試算: 検索抜粋のみ。**未確認**。
3. **`mcp-server` 削除の時期・経緯**（0.154.0、PR #42993、2026-09-05）: 二次情報（https://www.developersdigest.tech/blog/codex-mcp-server-removed 、https://codex.danielvaughan.com/2026/08/30/codex-mcp-server-deprecated-migration-app-server-agents-sdk/ ）。GitHub API はこのセッションで使えず、PR は未確認。**「0.163.0 に無い」こと自体は実機で確定**。
4. Codex 内の画像生成が利用枠を3〜5倍消費する、`$imagegen` の使い方、ChatGPT 本体の画像枠とは別: 検索抜粋のみ。
5. 個人プランで「Improve the model for everyone」の OFF が Codex にも適用される: 検索抜粋のみ（要ブラウザで確認）。
6. Go プランで CLI が使えるか、利用できるモデルの範囲: 食い違いあり、**未確認**。
7. Cowork から Skill と Mac の codex が使えるか: **未確認**。
8. `codex login status` のログイン済み時の表示と終了コード（0 になる想定）: **未確認**。
9. codex-plugin-cc の issue 番号（#793、#789、#798 など）と内容: 03b が一覧ページで確認したとする記載のみで、本レビューでは再確認していない。
10. exec で live 検索を使う指定（`-c web_search="live"`）: **未検証**（Skill では使っていないので影響なし）。
11. 04 §3-3「Skill は起動時に読み込まれる」: **不正確**。公式では `~/.claude/skills/` の変更は起動中のセッションでも反映される（起動時にそのフォルダ自体が無かった場合は `/reload-skills`）。新しく起動し直す手順のままでも害はない。

---

## 5. 04_strategy.md について（引き渡し前に必ず対応）

**04 §3-1a・§3-1b と §3-2 手順4のコピペ用ブロックは修正前の版**。そのままユーザーに渡すと、§1 の不具合（値なし引数での無限ループ、npm 版での codex の残留、全角・+81 の素通し、認証切れの誤判定）が残る。ユーザーに渡す手順書・貼り付けブロックは、skilltest/ の修正後の SKILL.md と run.sh から作り直すこと。それ以外の 04 の手順（Homebrew の有無の確認、cask・install.sh・npm の3方式、本人の `codex login`、学習 OFF、自動リロード OFF の確認、プラグインは後日）は正確と判断した。

---

## 6. 残存リスク

1. **成功系は一度も通っていない**: ログイン後に `codex exec` が回答を `-o` のファイルへ書くこと、`--disable shell_tool` などを付けた状態でモデルが普通に答えることは未検証。Mac での確認1（04 §3-3）で必ず確かめる。失敗したら、ログに tool／feature 関連のエラーがあるかを見て `GPT_SO_HARDEN=0` を試す。
2. **上限・認証切れの判定は推定**: 文言はバイナリ内の文字列から取ったが、exec の出力でどの形で出るかは未確認。外れた場合は終了コード 1（その他）になり、ログ末尾が表示されるので、致命的ではない。
3. **個人情報ガードは補助にすぎない**: 氏名、LINE ID、住所、`+81 (0)3-…` 形式、画像中の文字などは検出できない。主たる防御は SKILL の「Claude が送る前に伏せる」ルール。0始まりの注文番号などは誤検出する。
4. **作業フォルダの残り**: 成功時は回答（本文の引用を含み得る）、失敗時はログ（送った本文の表示を含む）が `$TMPDIR/gpt-so.XXXXXX` に残る。削除は SKILL の手順で Claude が行う前提で、Claude が忘れると残る。
5. **ChatGPT の連携アプリ**: `--disable apps` で止めているが、Codex がユーザーの ChatGPT 連携アプリ（Gmail・Drive など）にどこまで触れ得るかは未確認。
6. **bash 3.2／macOS 同梱 perl での実行は静的レビューのみ**（§1 の 1-9）。
7. **バイナリ内に `chatgpt auth token refresh is not supported in exec mode` という文字列がある**: 周辺の文字列から、外部でトークンを管理する方式（chatgptAuthTokens）向けの制限で、通常の `codex login` には関係しないと推定。ただし未確認。約8日ごとのトークン更新後に exec で認証切れが続くようなら、ターミナルで一度 `codex` を起動して更新させる。
8. Codex はエージェントとして動くため、1回あたりの利用枠の消費は API で直接呼ぶより大きくなり得る（03a の指摘どおり。実測なし）。
9. OpenAI の規約上の位置づけは「禁止事項に該当しない」であって、明示的な許可ではない（03c）。

---

## 7. 推奨の妥当性（ユーザー: ChatGPT 有料プランのみ・Mac・非エンジニア寄り）

- [示唆] **B（自作 Skill ＋ `codex exec` 読み取り専用）を今日入れ、A（公式プラグイン）と C（API キー）は必要になったら足す**という 04 の推奨は妥当。理由: (1) 業務の中心は git 管理外の文章で、`/codex:review` は観点を受け付けない（README で確認）。(2) 追加費用なし、本人の公式 CLI を本人のアカウントで使う。(3) `mcp-server` 方式は 0.163.0 で動かないことを実機で確認した。
- [示唆] インストールは **Homebrew cask を第一候補**にするのがよい。ネイティブのバイナリが直接入るので、npm 版にあった「ラッパーだけ止まって本体が残る」問題がそもそも起きにくい（修正後の run.sh はどちらでも対応済み）。
- [示唆] 非エンジニア向けの注意: Claude が run.sh を実行するたびに Bash の許可を求められる。これは「OpenAI に文章を送る直前の確認」として働くので、慣れるまではそのままがよい（§8 の判断項目3）。

---

## 8. ユーザー判断項目（最終版）

1. **ChatGPT のプランはどれか（Go／Plus／Pro／Business）。学習 OFF（「すべての人のためにモデルを改善する」を OFF）にしてよいか。**
   Plus 以上なら推奨案のまま使える。Go は CLI とモデルの範囲が未確認。Business は既定で学習に使われない。
2. **会員・顧客の情報をどこまで送ってよいか。**
   既定は「個人を特定できる情報は送らず、伏せ字にした文章だけ送る」。匿名化した相談内容（例: 「会員A の退会理由」）まで送ってよいか、会員に関わる内容は一切送らないか。
3. **run.sh の実行を毎回確認するか、確認なしにするか。**
   既定（おすすめ）は毎回確認（送信前の最終確認になる）。手間なら SKILL.md の frontmatter に `allowed-tools: Bash(${CLAUDE_SKILL_DIR}/run.sh *)` を足すと確認が出なくなる（公式の書き方: https://code.claude.com/docs/en/skills ）。
4. **今後、公式プラグイン（コードレビュー用）や API キー（クラウド・Cowork から使う、画像を多く作る）を足すか。足すなら API の月額上限をいくらにするか。**
   API の料金は未確認なので、足す時点で公式の料金ページを確認してから上限を決める。

---

## 出典
- Codex CLI README: https://github.com/openai/codex/blob/main/README.md
- Codex install.sh: https://raw.githubusercontent.com/openai/codex/main/scripts/install/install.sh
- Homebrew cask `codex`: https://raw.githubusercontent.com/Homebrew/homebrew-cask/main/Casks/c/codex.rb
- codex-plugin-cc README: https://raw.githubusercontent.com/openai/codex-plugin-cc/main/README.md
- Claude Code Skills: https://code.claude.com/docs/en/skills
- Claude Code クラウド: https://code.claude.com/docs/en/claude-code-on-the-web
- `mcp-server` 削除（二次情報）: https://www.developersdigest.tech/blog/codex-mcp-server-removed 、https://codex.danielvaughan.com/2026/08/30/codex-mcp-server-deprecated-migration-app-server-agents-sdk/
- Codex 料金（公式。本環境から本文は取得不可、検索のみ）: https://developers.openai.com/codex/pricing
- ローカル実機: `@openai/codex` 0.163.0 の `--help`／`exec --help`／`login --help`／`login status`／`debug models --bundled`／`features list`／バイナリ内の文字列（`strings`）
