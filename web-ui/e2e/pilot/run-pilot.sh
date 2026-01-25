#!/bin/bash
#
# Pilot Test Runner
#
# バリエーションを指定してパイロットテストを実行
#

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
E2E_DIR="$(dirname "$SCRIPT_DIR")"
WEB_UI_DIR="$(dirname "$E2E_DIR")"
PROJECT_ROOT="$(dirname "$WEB_UI_DIR")"

# デフォルト値
SCENARIO="hello-world"
VARIATION="baseline"
SKIP_SERVER_START=false
VERBOSE=false

# 使用方法
usage() {
  cat <<EOF
Usage: $0 [options]

Options:
  -s, --scenario NAME     シナリオ名 (default: hello-world)
  -v, --variation NAME    バリエーション名 (default: baseline)
  --skip-server           サーバー起動をスキップ（すでに起動している場合）
  --verbose               詳細出力
  -h, --help              ヘルプ表示

Examples:
  $0                                    # baseline バリエーションで実行
  $0 -v explicit-flow                   # explicit-flow バリエーションで実行
  $0 -s hello-world -v baseline         # シナリオとバリエーションを明示指定
  $0 --skip-server -v explicit-flow     # サーバー起動をスキップして実行
EOF
  exit 0
}

# 引数解析
while [[ $# -gt 0 ]]; do
  case $1 in
    -s|--scenario)
      SCENARIO="$2"
      shift 2
      ;;
    -v|--variation)
      VARIATION="$2"
      shift 2
      ;;
    --skip-server)
      SKIP_SERVER_START=true
      shift
      ;;
    --verbose)
      VERBOSE=true
      shift
      ;;
    -h|--help)
      usage
      ;;
    *)
      echo "Unknown option: $1"
      usage
      ;;
  esac
done

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

log_verbose() {
  if [ "$VERBOSE" = true ]; then
    log "$1"
  fi
}

# パス設定
SCENARIO_DIR="$SCRIPT_DIR/scenarios/$SCENARIO"
SCENARIO_YAML="$SCENARIO_DIR/scenario.yaml"
VARIATION_YAML="$SCENARIO_DIR/variations/${VARIATION}.yaml"
SEED_SQL="$SCRIPT_DIR/generated/seed-${SCENARIO}-${VARIATION}.sql"

# 検証
if [ ! -f "$SCENARIO_YAML" ]; then
  echo "Error: Scenario not found: $SCENARIO_YAML"
  exit 1
fi

if [ ! -f "$VARIATION_YAML" ]; then
  echo "Error: Variation not found: $VARIATION_YAML"
  echo "Available variations:"
  ls "$SCENARIO_DIR/variations/"*.yaml 2>/dev/null | xargs -n1 basename | sed 's/.yaml$//'
  exit 1
fi

log "=== Pilot Test Runner ==="
log "Scenario: $SCENARIO"
log "Variation: $VARIATION"

# 1. Seed SQL 生成
log "Generating seed SQL..."
mkdir -p "$SCRIPT_DIR/generated"

cd "$SCRIPT_DIR"
npx tsx lib/seed-generator.ts "$SCENARIO_YAML" "$VARIATION_YAML" > "$SEED_SQL"

log_verbose "Generated: $SEED_SQL"

# 2. データベース初期化
log "Initializing database..."
DB_PATH="$PROJECT_ROOT/data/test.db"

if [ -f "$DB_PATH" ]; then
  log_verbose "Removing existing database..."
  rm -f "$DB_PATH"
fi

# スキーマ適用
sqlite3 "$DB_PATH" < "$PROJECT_ROOT/data/schema.sql"

# シード適用
sqlite3 "$DB_PATH" < "$SEED_SQL"

log_verbose "Database initialized: $DB_PATH"

# 3. サーバー起動（オプション）
if [ "$SKIP_SERVER_START" = false ]; then
  log "Starting servers..."

  # 既存プロセスを停止
  pkill -f "node.*rest-server" || true
  pkill -f "node.*mcp-server" || true
  sleep 1

  # REST サーバー起動
  cd "$WEB_UI_DIR"
  npm run dev:rest > /tmp/pilot-rest.log 2>&1 &
  REST_PID=$!
  log_verbose "REST server PID: $REST_PID"

  # MCP サーバー起動（WebSocket）
  npm run dev:mcp > /tmp/pilot-mcp.log 2>&1 &
  MCP_PID=$!
  log_verbose "MCP server PID: $MCP_PID"

  # 起動待機
  log "Waiting for servers to start..."
  sleep 3

  # ヘルスチェック
  if ! curl -s http://localhost:3001/api/health > /dev/null 2>&1; then
    echo "Error: REST server failed to start"
    cat /tmp/pilot-rest.log
    exit 1
  fi

  log_verbose "Servers are running"
fi

# 4. Playwright テスト実行
log "Running Playwright test..."

cd "$E2E_DIR"

# 環境変数でバリエーション情報を渡す
export PILOT_SCENARIO="$SCENARIO"
export PILOT_VARIATION="$VARIATION"
export PILOT_BASE_DIR="$SCRIPT_DIR"

# Playwright 実行
npx playwright test pilot/tests/pilot.spec.ts --reporter=list

TEST_EXIT_CODE=$?

# 5. クリーンアップ
if [ "$SKIP_SERVER_START" = false ]; then
  log "Stopping servers..."
  kill $REST_PID 2>/dev/null || true
  kill $MCP_PID 2>/dev/null || true
fi

# 6. 結果サマリー
log "=== Test Result ==="
if [ $TEST_EXIT_CODE -eq 0 ]; then
  log "✅ PASSED: $SCENARIO / $VARIATION"
else
  log "❌ FAILED: $SCENARIO / $VARIATION"
fi

# 結果ディレクトリを表示
LATEST_RESULT=$(ls -dt "$SCRIPT_DIR/results/$SCENARIO"/*_${VARIATION} 2>/dev/null | head -1)
if [ -n "$LATEST_RESULT" ]; then
  log "Results: $LATEST_RESULT"
fi

exit $TEST_EXIT_CODE
