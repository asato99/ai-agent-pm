#!/bin/bash
#
# Experiment Test Runner
#
# パイロットインフラを再利用しつつ、実験用シナリオを実行
# run-pilot.sh と同じ構造だが experiments/ ディレクトリを参照
#

set -e

# 色付き出力
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# パス設定
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
E2E_DIR="$(dirname "$SCRIPT_DIR")"
WEB_UI_DIR="$(dirname "$E2E_DIR")"
PROJECT_ROOT="$(dirname "$WEB_UI_DIR")"

# デフォルト値
SCENARIO="hello-world"
VARIATION="baseline"
SKIP_SERVER_START=false
VERBOSE=false
HEADED=true
RECORD=false

# テスト設定
TEST_DB_PATH="/tmp/AIAgentPM_Pilot.db"
MCP_SOCKET_PATH="/tmp/aiagentpm_pilot.sock"
REST_PORT="8085"
WEB_UI_PORT="5173"

export MCP_COORDINATOR_TOKEN="test_coordinator_token_pilot"

# PID管理
COORDINATOR_PID=""
MCP_PID=""
REST_PID=""
WEB_UI_PID=""
FFMPEG_PID=""
TEST_PASSED=false

# 結果・ログディレクトリ（テスト開始時に設定）
RESULT_DIR=""
LOG_DIR=""

# 使用方法
usage() {
  cat <<EOF
Usage: $0 [options]

Options:
  -s, --scenario NAME     シナリオ名 (default: hello-world)
  -v, --variation NAME    バリエーション名 (default: baseline)
  --skip-server           サーバー起動をスキップ（すでに起動している場合）
  --headless              ブラウザを非表示で実行
  --record                動画記録を有効化（Playwright + ffmpeg）
  --verbose               詳細出力
  -h, --help              ヘルプ表示

Note: デフォルトはブラウザ表示（headed）、動画記録OFFです

Examples:
  $0                                    # baseline バリエーションで実行
  $0 -v explicit-flow                   # explicit-flow バリエーションで実行
  $0 -s hello-world -v baseline         # シナリオとバリエーションを明示指定
  $0 --skip-server -v explicit-flow     # サーバー起動をスキップして実行
EOF
  exit 0
}

collect_logs() {
  if [ -z "$LOG_DIR" ] || [ ! -d "$LOG_DIR" ]; then
    return
  fi

  echo -e "${BLUE}Collecting logs to: $RESULT_DIR${NC}"

  # DBスナップショット
  if [ -f "$TEST_DB_PATH" ]; then
    sqlite3 "$TEST_DB_PATH" ".dump" > "$LOG_DIR/db-snapshot.sql" 2>/dev/null || true
  fi

  # 画面録画ファイル収集（test-results/experimentsから最新の動画を1本コピー）
  VIDEO_FILE=$(find "$WEB_UI_DIR/test-results/experiments" -name "*.webm" -type f 2>/dev/null | head -1)
  if [ -n "$VIDEO_FILE" ]; then
    cp "$VIDEO_FILE" "$LOG_DIR/recording_playwright.webm"
    echo -e "${GREEN}✓ Playwright video saved: recording_playwright.webm${NC}"
  fi

  # ffmpeg録画ファイル確認
  if [ -f "$LOG_DIR/screen_recording.mp4" ]; then
    FFMPEG_SIZE=$(du -h "$LOG_DIR/screen_recording.mp4" | cut -f1)
    echo -e "${GREEN}✓ ffmpeg recording saved: screen_recording.mp4 ($FFMPEG_SIZE)${NC}"
  fi

  # 成果物を保存（作業ディレクトリの内容をコピー）
  if [ -n "$PILOT_WORKING_DIR" ] && [ -d "$PILOT_WORKING_DIR" ]; then
    ARTIFACTS_DIR="$RESULT_DIR/artifacts"
    mkdir -p "$ARTIFACTS_DIR"
    cp -R "$PILOT_WORKING_DIR"/. "$ARTIFACTS_DIR/" 2>/dev/null || true
    ARTIFACT_COUNT=$(find "$ARTIFACTS_DIR" -type f 2>/dev/null | wc -l | tr -d ' ')
    echo -e "${GREEN}✓ Artifacts saved: $ARTIFACT_COUNT files${NC}"
  fi

  # 統合ログ生成（プレフィックス付き）
  {
    [ -f "$LOG_DIR/mcp-server.log" ] && sed 's/^/[MCP] /' "$LOG_DIR/mcp-server.log"
    [ -f "$LOG_DIR/rest-server.log" ] && sed 's/^/[REST] /' "$LOG_DIR/rest-server.log"
    [ -f "$LOG_DIR/coordinator.log" ] && sed 's/^/[COORD] /' "$LOG_DIR/coordinator.log"
    [ -f "$LOG_DIR/playwright.log" ] && sed 's/^/[PLAY] /' "$LOG_DIR/playwright.log"
    [ -f "$LOG_DIR/vite.log" ] && sed 's/^/[VITE] /' "$LOG_DIR/vite.log"
  } | sort > "$LOG_DIR/combined.log" 2>/dev/null || true

  # latest シンボリックリンク更新
  LATEST_LINK="$SCRIPT_DIR/results/$SCENARIO/latest"
  rm -f "$LATEST_LINK"
  ln -s "$(basename "$RESULT_DIR")" "$LATEST_LINK"

  echo -e "${GREEN}✓ Logs saved${NC}"
  echo "  Combined log: $LOG_DIR/combined.log"
  echo "  Latest link:  $LATEST_LINK"
}

cleanup() {
  echo ""
  echo -e "${YELLOW}Cleanup${NC}"

  # ffmpeg録画停止（シグナルで正常終了させる）
  if [ -n "$FFMPEG_PID" ] && kill -0 "$FFMPEG_PID" 2>/dev/null; then
    echo -e "${BLUE}Stopping ffmpeg recording...${NC}"
    kill -INT "$FFMPEG_PID" 2>/dev/null
    # ffmpegが正常終了するまで待機（最大10秒）
    for i in {1..10}; do
      kill -0 "$FFMPEG_PID" 2>/dev/null || break
      sleep 1
    done
    kill -9 "$FFMPEG_PID" 2>/dev/null || true
    echo -e "${GREEN}✓ ffmpeg recording stopped${NC}"
  fi

  # ログ収集（サーバー停止前に実行）
  collect_logs

  [ -n "$WEB_UI_PID" ] && kill -0 "$WEB_UI_PID" 2>/dev/null && kill "$WEB_UI_PID" 2>/dev/null
  [ -n "$COORDINATOR_PID" ] && kill -0 "$COORDINATOR_PID" 2>/dev/null && kill "$COORDINATOR_PID" 2>/dev/null
  [ -n "$REST_PID" ] && kill -0 "$REST_PID" 2>/dev/null && kill "$REST_PID" 2>/dev/null
  [ -n "$MCP_PID" ] && kill -0 "$MCP_PID" 2>/dev/null && kill "$MCP_PID" 2>/dev/null

  rm -f "$MCP_SOCKET_PATH"

  # 一時ファイルは常にクリーンアップ（ログは結果ディレクトリに保存済み）
  rm -f /tmp/coordinator_pilot_config.yaml
  rm -rf /tmp/coordinator_logs_pilot
  rm -rf /tmp/pilot_work/.aiagent

  if [ "$TEST_PASSED" == "true" ]; then
    rm -f "$TEST_DB_PATH" "$TEST_DB_PATH-shm" "$TEST_DB_PATH-wal"
  fi
}

trap cleanup EXIT

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
    --headless)
      HEADED=false
      shift
      ;;
    --record)
      RECORD=true
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
  echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
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

echo "=========================================="
echo -e "${BLUE}Experiment Test Runner${NC}"
echo -e "${BLUE}Scenario: $SCENARIO / Variation: $VARIATION${NC}"
echo "=========================================="
echo ""

# Step 1: 環境準備
echo -e "${YELLOW}Step 1: Preparing environment${NC}"
ps aux | grep -E "(mcp-server-pm|rest-server-pm)" | grep -v grep | awk '{print $2}' | xargs -I {} kill -9 {} 2>/dev/null || true
# コーディネーターの強制終了とロックファイル削除
ps aux | grep "aiagent_runner.*coordinator" | grep -v grep | awk '{print $2}' | xargs -I {} kill -9 {} 2>/dev/null || true
rm -f /tmp/aiagent-runner-*/coordinator-*.lock 2>/dev/null || true
rm -f "$TEST_DB_PATH" "$TEST_DB_PATH-shm" "$TEST_DB_PATH-wal" "$MCP_SOCKET_PATH"
mkdir -p /tmp/pilot_work

# 結果ディレクトリ作成
# UTC時刻を使用（ResultRecorder.tsのtoISOString()と一致させる）
RESULT_TIMESTAMP=$(date -u '+%Y-%m-%dT%H-%M-%S')
RESULT_DIR="$SCRIPT_DIR/results/$SCENARIO/${RESULT_TIMESTAMP}_${VARIATION}"
LOG_DIR="$RESULT_DIR/logs"
mkdir -p "$LOG_DIR"
mkdir -p "$RESULT_DIR/agent-logs"
echo "Results: $RESULT_DIR"

# 作業ディレクトリをクリーンアップ（成果物含む）
PILOT_WORKING_DIR=$(cd "$SCRIPT_DIR" && npx tsx -e "
import * as yaml from 'js-yaml';
import * as fs from 'fs';
const s = yaml.load(fs.readFileSync('$SCENARIO_YAML', 'utf8'));
console.log(s.project.working_directory);
" 2>/dev/null || echo "")
if [ -n "$PILOT_WORKING_DIR" ] && [ -d "$PILOT_WORKING_DIR" ]; then
  # 作業ディレクトリ全体をクリア（initial_filesはseed-generatorで再作成される）
  rm -rf "$PILOT_WORKING_DIR"
  echo "Cleaned: $PILOT_WORKING_DIR (全体)"
fi
mkdir -p "$PILOT_WORKING_DIR"

echo "DB: $TEST_DB_PATH"
echo ""

# Step 2: Seed SQL 生成
echo -e "${YELLOW}Step 2: Generating seed SQL${NC}"
mkdir -p "$SCRIPT_DIR/generated"
cd "$WEB_UI_DIR"
npx tsx "$SCRIPT_DIR/lib/seed-generator.ts" "$SCENARIO_YAML" "$VARIATION_YAML" > "$SEED_SQL"
echo -e "${GREEN}✓ Generated: $SEED_SQL${NC}"
echo ""

# Step 3: サーバーバイナリ確認
echo -e "${YELLOW}Step 3: Checking server binaries${NC}"
cd "$PROJECT_ROOT"

DERIVED_DATA_DIR=$(find ~/Library/Developer/Xcode/DerivedData -maxdepth 1 -name "AIAgentPM-*" -type d 2>/dev/null | head -1)
if [ -n "$DERIVED_DATA_DIR" ] && [ -x "$DERIVED_DATA_DIR/Build/Products/Debug/mcp-server-pm" ]; then
  MCP_SERVER_BIN="$DERIVED_DATA_DIR/Build/Products/Debug/mcp-server-pm"
  REST_SERVER_BIN="$DERIVED_DATA_DIR/Build/Products/Debug/rest-server-pm"
elif [ -x ".build/release/mcp-server-pm" ]; then
  MCP_SERVER_BIN=".build/release/mcp-server-pm"
  REST_SERVER_BIN=".build/release/rest-server-pm"
else
  MCP_SERVER_BIN=""
  REST_SERVER_BIN=""
fi

if [ -x "$MCP_SERVER_BIN" ] && [ -x "$REST_SERVER_BIN" ]; then
  echo -e "${GREEN}✓ Server binaries found${NC}"
  log_verbose "  MCP: $MCP_SERVER_BIN"
  log_verbose "  REST: $REST_SERVER_BIN"
else
  echo -e "${YELLOW}Building servers...${NC}"
  if [ -f "project.yml" ]; then
    xcodebuild -scheme MCPServer -configuration Debug 2>&1 | tail -5
    xcodebuild -scheme RESTServer -configuration Debug 2>&1 | tail -5
    DERIVED_DATA_DIR=$(find ~/Library/Developer/Xcode/DerivedData -maxdepth 1 -name "AIAgentPM-*" -type d 2>/dev/null | head -1)
    MCP_SERVER_BIN="$DERIVED_DATA_DIR/Build/Products/Debug/mcp-server-pm"
    REST_SERVER_BIN="$DERIVED_DATA_DIR/Build/Products/Debug/rest-server-pm"
  else
    swift build -c release --product mcp-server-pm 2>&1 | tail -2
    swift build -c release --product rest-server-pm 2>&1 | tail -2
    MCP_SERVER_BIN=".build/release/mcp-server-pm"
    REST_SERVER_BIN=".build/release/rest-server-pm"
  fi
fi
echo ""

# Step 4: DB初期化
echo -e "${YELLOW}Step 4: Initializing database${NC}"
# MCPサーバーのdaemonコマンドでスキーマを自動初期化
AIAGENTPM_DB_PATH="$TEST_DB_PATH" "$MCP_SERVER_BIN" daemon \
  --socket-path "$MCP_SOCKET_PATH" --foreground > /tmp/pilot_mcp_init.log 2>&1 &
INIT_PID=$!
sleep 3
kill "$INIT_PID" 2>/dev/null || true
rm -f "$MCP_SOCKET_PATH"

# シード適用
sqlite3 "$TEST_DB_PATH" < "$SEED_SQL"
echo -e "${GREEN}✓ Database initialized${NC}"
echo ""

if [ "$SKIP_SERVER_START" = true ]; then
  echo -e "${YELLOW}Skipping server startup (--skip-server)${NC}"
  echo "Please ensure servers are running manually."
  exit 0
fi

# Step 5: サーバー起動
echo -e "${YELLOW}Step 5: Starting servers${NC}"

AIAGENTPM_DB_PATH="$TEST_DB_PATH" "$MCP_SERVER_BIN" daemon \
  --socket-path "$MCP_SOCKET_PATH" --foreground > "$LOG_DIR/mcp-server.log" 2>&1 &
MCP_PID=$!

for i in {1..10}; do [ -S "$MCP_SOCKET_PATH" ] && break; sleep 0.5; done
echo -e "${GREEN}✓ MCP server running${NC}"

AIAGENTPM_DB_PATH="$TEST_DB_PATH" AIAGENTPM_WEBSERVER_PORT="$REST_PORT" \
  "$REST_SERVER_BIN" > "$LOG_DIR/rest-server.log" 2>&1 &
REST_PID=$!

for i in {1..10}; do curl -s "http://localhost:$REST_PORT/health" > /dev/null 2>&1 && break; sleep 0.5; done
echo -e "${GREEN}✓ REST server running at :$REST_PORT${NC}"
echo ""

# Step 6: Coordinator起動
echo -e "${YELLOW}Step 6: Starting Coordinator${NC}"

RUNNER_DIR="$PROJECT_ROOT/runner"
PYTHON="${RUNNER_DIR}/.venv/bin/python"
[ ! -x "$PYTHON" ] && PYTHON="python3"

# バリエーションからエージェントIDを取得（web-ui ディレクトリで実行してnode_modulesにアクセス）
cd "$WEB_UI_DIR"
AGENT_IDS=$(npx tsx -e "
import * as yaml from 'js-yaml';
import * as fs from 'fs';
const v = yaml.load(fs.readFileSync('$VARIATION_YAML', 'utf8'));
const aiAgents = Object.values(v.agents).filter(a => a.type === 'ai');
console.log(aiAgents.map(a => a.id).join(' '));
")

# Coordinator設定ファイル生成
cat > /tmp/coordinator_pilot_config.yaml << EOF
polling_interval: 2
max_concurrent: 3
coordinator_token: ${MCP_COORDINATOR_TOKEN}
mcp_socket_path: $MCP_SOCKET_PATH
ai_providers:
  claude:
    cli_command: claude
    cli_args: ["--dangerously-skip-permissions", "--max-turns", "300"]
  gemini:
    cli_command: gemini
    cli_args: ["-y"]
agents:
EOF

for AGENT_ID in $AGENT_IDS; do
  cat >> /tmp/coordinator_pilot_config.yaml << EOF
  $AGENT_ID:
    passkey: test-passkey
EOF
done

cat >> /tmp/coordinator_pilot_config.yaml << EOF
log_directory: $RESULT_DIR/agent-logs
log_upload:
  enabled: true
EOF

# Claude Code のネスト検出を回避（Claude Code セッション内から実行した場合）
unset CLAUDECODE CLAUDE_CODE_SSE_PORT CLAUDE_CODE_ENTRYPOINT

AIAGENTPM_WEBSERVER_PORT="$REST_PORT" $PYTHON -m aiagent_runner --coordinator -c /tmp/coordinator_pilot_config.yaml -v > "$LOG_DIR/coordinator.log" 2>&1 &
COORDINATOR_PID=$!
sleep 2
echo -e "${GREEN}✓ Coordinator running${NC}"
echo ""

# Step 7: Web UI起動
echo -e "${YELLOW}Step 7: Starting Web UI${NC}"
cd "$WEB_UI_DIR"

AIAGENTPM_WEBSERVER_PORT="$REST_PORT" npm run dev -- --port "$WEB_UI_PORT" > "$LOG_DIR/vite.log" 2>&1 &
WEB_UI_PID=$!

for i in {1..20}; do curl -s "http://localhost:$WEB_UI_PORT" > /dev/null 2>&1 && break; sleep 1; done
echo -e "${GREEN}✓ Web UI running at :$WEB_UI_PORT${NC}"
echo ""

# Step 7.5: ffmpeg画面録画（--record オプション時のみ）
if [ "$RECORD" = true ]; then
  echo -e "${YELLOW}Step 7.5: Starting ffmpeg screen recording${NC}"
  FFMPEG_RECORDING="$LOG_DIR/screen_recording.mp4"
  if command -v ffmpeg &> /dev/null; then
    ffmpeg -f avfoundation -framerate 5 -capture_cursor 1 -i "0:none" \
      -c:v libx264 -preset ultrafast -crf 28 \
      -pix_fmt yuv420p \
      -movflags frag_keyframe+empty_moov \
      "$FFMPEG_RECORDING" > "$LOG_DIR/ffmpeg.log" 2>&1 &
    FFMPEG_PID=$!
    sleep 2
    if kill -0 "$FFMPEG_PID" 2>/dev/null; then
      echo -e "${GREEN}✓ ffmpeg recording started (PID: $FFMPEG_PID)${NC}"
    else
      echo -e "${YELLOW}⚠ ffmpeg failed to start (continuing without screen recording)${NC}"
      FFMPEG_PID=""
    fi
  else
    echo -e "${YELLOW}⚠ ffmpeg not found (skipping screen recording)${NC}"
  fi
  echo ""
else
  echo -e "${YELLOW}Step 7.5: Screen recording skipped (use --record to enable)${NC}"
  echo ""
fi

# Step 8: Playwrightテスト実行
echo -e "${YELLOW}Step 8: Running Playwright test${NC}"

cd "$E2E_DIR"

export PILOT_SCENARIO="$SCENARIO"
export PILOT_VARIATION="$VARIATION"
export PILOT_BASE_DIR="$SCRIPT_DIR"
export INTEGRATION_WEB_URL="http://localhost:$WEB_UI_PORT"
export INTEGRATION_WITH_COORDINATOR="true"
export AIAGENTPM_WEBSERVER_PORT="$REST_PORT"

# 結果ディレクトリを環境変数で渡す
export PILOT_RESULT_DIR="$RESULT_DIR"

# Headed mode
if [ "$HEADED" = true ]; then
  export PILOT_HEADED="true"
fi

# Record mode
if [ "$RECORD" = true ]; then
  export PILOT_RECORD="true"
fi

set -o pipefail
npx playwright test experiments/tests/scenario.spec.ts \
  --config=experiments/playwright.experiment.config.ts \
  --reporter=list \
  --timeout=300000 \
  2>&1 | tee "$LOG_DIR/playwright.log"

PLAYWRIGHT_EXIT=${PIPESTATUS[0]}
set +o pipefail
echo ""

# Step 9: 結果検証
echo -e "${YELLOW}Step 9: Verifying results${NC}"
echo "=== Tasks ==="
sqlite3 "$TEST_DB_PATH" "SELECT id, title, status, assignee_id FROM tasks WHERE project_id = 'pilot-hello';" 2>/dev/null || true
echo ""

# 成果物確認
echo "=== Artifacts ==="
cd "$WEB_UI_DIR"
WORKING_DIR=$(npx tsx -e "
import * as yaml from 'js-yaml';
import * as fs from 'fs';
const s = yaml.load(fs.readFileSync('$SCENARIO_YAML', 'utf8'));
console.log(s.project.working_directory);
")

if [ -f "$WORKING_DIR/hello.py" ]; then
  echo -e "${GREEN}✓ hello.py exists${NC}"
  echo "Content:"
  cat "$WORKING_DIR/hello.py"
  echo ""
  echo "Execution:"
  python3 "$WORKING_DIR/hello.py" 2>&1 || true
else
  echo -e "${RED}✗ hello.py not found${NC}"
fi
echo ""

# 結果判定
if [ $PLAYWRIGHT_EXIT -eq 0 ]; then
  TEST_PASSED=true
  echo -e "${GREEN}========================================${NC}"
  echo -e "${GREEN}Experiment PASSED: $SCENARIO / $VARIATION${NC}"
  echo -e "${GREEN}========================================${NC}"
  echo "Logs: $LOG_DIR"
  exit 0
else
  echo -e "${RED}========================================${NC}"
  echo -e "${RED}Experiment FAILED: $SCENARIO / $VARIATION${NC}"
  echo -e "${RED}========================================${NC}"
  echo ""
  echo "Logs: $LOG_DIR"
  echo "Quick access:"
  echo "  cat $LOG_DIR/combined.log           # 統合ログ"
  echo "  cat $LOG_DIR/mcp-server.log         # MCPサーバー"
  echo "  cat $LOG_DIR/coordinator.log        # コーディネーター"
  echo "  sqlite3 $LOG_DIR/db-snapshot.sql    # DBスナップショット"
  exit 1
fi
