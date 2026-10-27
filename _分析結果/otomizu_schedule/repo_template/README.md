# otomizu-schedule

OTOMIZU に関わる個人事業主が、互いのスケジュールを把握するための Web アプリ。

- 公開：Netlify
- データ・ログイン：Supabase（Postgres + Auth + RLS）
- 入力方式：各自がアプリに予定を入力する

## 構成

| パス | 内容 |
|---|---|
| `supabase/migrations/` | DB スキーマ（叩き台） |
| `docs/環境設定.md` | Claude Code クラウド環境の設定値 |
| `setup.sh` | クラウド環境のセットアップスクリプト |
| `CLAUDE.md` | Claude 向け作業ルール |
