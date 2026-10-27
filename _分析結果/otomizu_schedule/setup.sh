#!/bin/bash
# OTOMIZU スケジュール管理 — クラウド環境セットアップスクリプト
# 環境設定の「セットアップスクリプト」欄に貼り付け（またはこのファイルを選択）
set -e

# Netlify CLI（npm）
npm install -g netlify-cli >/dev/null 2>&1 &

# Supabase CLI（npm -g 非対応のため GitHub Releases のバイナリを導入）
(curl -fsSL https://github.com/supabase/cli/releases/latest/download/supabase_linux_amd64.tar.gz \
  | tar -xz -C /usr/local/bin supabase) &

wait
echo "setup done: $(netlify --version 2>/dev/null) / supabase $(supabase --version 2>/dev/null)"
