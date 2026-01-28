# パイロットテスト ログアーキテクチャ改善

## 現状の課題

1. **ログの散在**: `/tmp/pilot_*.log` に分散、テスト後に消失
2. **成功時のログ削除**: デバッグに必要なログが失われる
3. **時系列追跡困難**: 各コンポーネントのログが分離
4. **最新ログへのアクセス**: 毎回タイムスタンプ付きディレクトリを探す必要

## 改善後の構成

```
web-ui/e2e/pilot/
└── results/
    └── hello-world/
        ├── latest -> 2026-01-28T10-30-00_baseline/  # シンボリックリンク
        └── 2026-01-28T10-30-00_baseline/
            ├── result.yaml          # テスト結果サマリ
            ├── result.json          # 機械可読形式
            ├── events.jsonl         # テストイベント時系列
            ├── agent-logs/          # エージェント実行ログ
            │   ├── pilot-manager/
            │   ├── pilot-worker-dev/
            │   └── pilot-worker-review/
            └── logs/                # ★新規: コンポーネントログ集約
                ├── combined.log     # 全ログ統合（タイムスタンプソート）
                ├── mcp-server.log   # MCPサーバー
                ├── rest-server.log  # RESTサーバー
                ├── coordinator.log  # コーディネーター
                ├── playwright.log   # Playwrightテスト
                ├── vite.log         # Vite Dev Server
                └── db-snapshot.sql  # テスト終了時のDBダンプ
```

## 実装変更点

### 1. run-pilot.sh の修正

```bash
# Step 0: 結果ディレクトリの作成（テスト開始時）
RESULT_TIMESTAMP=$(date '+%Y-%m-%dT%H-%M-%S')
RESULT_DIR="$SCRIPT_DIR/results/$SCENARIO/${RESULT_TIMESTAMP}_${VARIATION}"
LOG_DIR="$RESULT_DIR/logs"
mkdir -p "$LOG_DIR"

# 各サーバーのログ出力先を変更
AIAGENTPM_DB_PATH="$TEST_DB_PATH" "$MCP_SERVER_BIN" daemon \
  --socket-path "$MCP_SOCKET_PATH" --foreground > "$LOG_DIR/mcp-server.log" 2>&1 &

AIAGENTPM_DB_PATH="$TEST_DB_PATH" AIAGENTPM_WEBSERVER_PORT="$REST_PORT" \
  "$REST_SERVER_BIN" > "$LOG_DIR/rest-server.log" 2>&1 &

# coordinator の log_directory も結果ディレクトリを指定
cat > /tmp/coordinator_pilot_config.yaml << EOF
log_directory: $RESULT_DIR/agent-logs
EOF

$PYTHON -m aiagent_runner --coordinator -c /tmp/coordinator_pilot_config.yaml -v \
  > "$LOG_DIR/coordinator.log" 2>&1 &

# Vite
npm run dev -- --port "$WEB_UI_PORT" > "$LOG_DIR/vite.log" 2>&1 &

# Playwright
npx playwright test ... 2>&1 | tee "$LOG_DIR/playwright.log"
```

### 2. テスト終了時の処理

```bash
# cleanup 関数内
collect_logs() {
  # DBスナップショット
  sqlite3 "$TEST_DB_PATH" ".dump" > "$LOG_DIR/db-snapshot.sql"

  # 統合ログ生成（タイムスタンプでソート）
  cat "$LOG_DIR"/*.log | sort > "$LOG_DIR/combined.log"

  # latest シンボリックリンク更新
  ln -sfn "$RESULT_DIR" "$SCRIPT_DIR/results/$SCENARIO/latest"

  echo "Logs saved to: $RESULT_DIR"
}

cleanup() {
  collect_logs
  # サーバー停止処理...

  # /tmp のファイルは削除してOK（結果ディレクトリに保存済み）
  rm -f /tmp/coordinator_pilot_config.yaml
}
```

### 3. 古いログの自動削除（オプション）

```bash
# 最新N件のみ保持
MAX_RESULTS=5
cleanup_old_results() {
  cd "$SCRIPT_DIR/results/$SCENARIO"
  ls -1d */ | head -n -$MAX_RESULTS | xargs -r rm -rf
}
```

## クイックアクセスコマンド

```bash
# 最新のログを確認
cat web-ui/e2e/pilot/results/hello-world/latest/logs/combined.log

# 最新のMCPサーバーログ
cat web-ui/e2e/pilot/results/hello-world/latest/logs/mcp-server.log

# 最新のコーディネーターログ
cat web-ui/e2e/pilot/results/hello-world/latest/logs/coordinator.log

# 最新のDBスナップショット
sqlite3 web-ui/e2e/pilot/results/hello-world/latest/logs/db-snapshot.sql ".read"

# エラー検索
grep -i error web-ui/e2e/pilot/results/hello-world/latest/logs/*.log
```

## combined.log の形式

各ログファイルにプレフィックスを付けて統合:

```
[2026-01-28T10:30:01] [MCP] Starting MCP server...
[2026-01-28T10:30:01] [REST] Server listening on :8085
[2026-01-28T10:30:02] [COORD] Polling agents...
[2026-01-28T10:30:03] [MCP] getAgentAction: pilot-manager...
[2026-01-28T10:30:05] [COORD] Starting pilot-manager session
[2026-01-28T10:30:10] [PLAY] Chat session is ready
```

### 統合ログ生成スクリプト

```bash
#!/bin/bash
# generate-combined-log.sh
LOG_DIR="$1"

(
  sed 's/^/[MCP] /' "$LOG_DIR/mcp-server.log"
  sed 's/^/[REST] /' "$LOG_DIR/rest-server.log"
  sed 's/^/[COORD] /' "$LOG_DIR/coordinator.log"
  sed 's/^/[PLAY] /' "$LOG_DIR/playwright.log"
  sed 's/^/[VITE] /' "$LOG_DIR/vite.log"
) | sort > "$LOG_DIR/combined.log"
```

## gitignore 設定

```gitignore
# web-ui/e2e/pilot/.gitignore
results/*/logs/
results/*/latest
!results/.gitkeep
```

## 移行手順

1. `run-pilot.sh` を修正
2. `.gitignore` を更新
3. 既存の `/tmp/pilot_*.log` 依存を削除

## 期待される効果

1. **ログの永続化**: テスト結果と一緒にログが保存される
2. **簡単なアクセス**: `latest/` で常に最新を参照可能
3. **時系列追跡**: `combined.log` で全コンポーネントを統合
4. **DBスナップショット**: テスト終了時の状態を完全に保存
5. **クリーンな/tmp**: 一時ファイルは結果ディレクトリにコピー後削除
