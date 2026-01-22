#!/bin/bash
# UC010 Web UI Integration Test - Task Interrupt Flow
# タスク中断フローの統合テスト（異常系）
#
# フロー:
#   1. テスト環境準備
#   2. MCP + RESTサーバー起動
#   3. Coordinator起動
#   4. Web UI起動
#   5. Playwrightテスト実行
#   6. 結果検証

set -e

# 色付き出力
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# パス設定 (絶対パスに変換)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WEB_UI_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

# テスト設定
TEST_DB_PATH="/tmp/AIAgentPM_UC010_WebUI.db"
MCP_SOCKET_PATH="/tmp/aiagentpm_uc010_webui.sock"
REST_PORT="8084"
WEB_UI_PORT="5173"  # Must be 5173 for CORS (allowed origins in REST server)

export MCP_COORDINATOR_TOKEN="test_coordinator_token_uc010_webui"

COORDINATOR_PID=""
MCP_PID=""
REST_PID=""
WEB_UI_PID=""
TEST_PASSED=false

cleanup() {
    echo ""
    echo -e "${YELLOW}Cleanup${NC}"

    [ -n "$WEB_UI_PID" ] && kill -0 "$WEB_UI_PID" 2>/dev/null && kill "$WEB_UI_PID" 2>/dev/null
    [ -n "$COORDINATOR_PID" ] && kill -0 "$COORDINATOR_PID" 2>/dev/null && kill "$COORDINATOR_PID" 2>/dev/null
    [ -n "$REST_PID" ] && kill -0 "$REST_PID" 2>/dev/null && kill "$REST_PID" 2>/dev/null
    [ -n "$MCP_PID" ] && kill -0 "$MCP_PID" 2>/dev/null && kill "$MCP_PID" 2>/dev/null

    rm -f "$MCP_SOCKET_PATH"

    if [ "$TEST_PASSED" == "true" ]; then
        rm -f /tmp/uc010_webui_*.log
        rm -f /tmp/coordinator_uc010_webui_config.yaml
        rm -rf /tmp/coordinator_logs_uc010_webui
        rm -f "$TEST_DB_PATH" "$TEST_DB_PATH-shm" "$TEST_DB_PATH-wal"
    else
        echo "Logs preserved: /tmp/uc010_webui_*.log"
    fi
}

trap cleanup EXIT

echo "=========================================="
echo -e "${BLUE}UC010 Web UI Integration Test${NC}"
echo -e "${BLUE}(Task Interrupt Flow)${NC}"
echo "=========================================="
echo ""

# Step 1: 環境準備
echo -e "${YELLOW}Step 1: Preparing environment${NC}"
ps aux | grep -E "(mcp-server-pm|rest-server-pm)" | grep -v grep | awk '{print $2}' | xargs -I {} kill -9 {} 2>/dev/null || true
rm -f "$TEST_DB_PATH" "$TEST_DB_PATH-shm" "$TEST_DB_PATH-wal" "$MCP_SOCKET_PATH"
mkdir -p /tmp/uc010_webui_work
echo "DB: $TEST_DB_PATH"
echo ""

# Step 2: ビルド確認
echo -e "${YELLOW}Step 2: Checking server binaries${NC}"
cd "$PROJECT_ROOT"
if [ -x ".build/release/mcp-server-pm" ] && [ -x ".build/release/rest-server-pm" ]; then
    echo -e "${GREEN}✓ Server binaries found${NC}"
else
    echo -e "${YELLOW}Building servers...${NC}"
    if [ -f "project.yml" ]; then
        xcodebuild -scheme AIAgentPM -configuration Release build 2>&1 | tail -5
    else
        swift build -c release --product mcp-server-pm 2>&1 | tail -2
        swift build -c release --product rest-server-pm 2>&1 | tail -2
    fi
fi
echo ""

# Step 3: DB初期化
echo -e "${YELLOW}Step 3: Initializing database${NC}"
AIAGENTPM_DB_PATH="$TEST_DB_PATH" "$PROJECT_ROOT/.build/release/mcp-server-pm" setup 2>/dev/null || \
    timeout 2 bash -c "AIAGENTPM_DB_PATH='$TEST_DB_PATH' '$PROJECT_ROOT/.build/release/mcp-server-pm' serve" 2>/dev/null || true

SQL_FILE="$SCRIPT_DIR/setup/seed-integration-data.sql"
[ -f "$SQL_FILE" ] && sqlite3 "$TEST_DB_PATH" < "$SQL_FILE"
echo "Database initialized"
echo ""

# Step 4: サーバー起動
echo -e "${YELLOW}Step 4: Starting servers${NC}"

AIAGENTPM_DB_PATH="$TEST_DB_PATH" "$PROJECT_ROOT/.build/release/mcp-server-pm" daemon \
    --socket-path "$MCP_SOCKET_PATH" --foreground > /tmp/uc010_webui_mcp.log 2>&1 &
MCP_PID=$!

for i in {1..10}; do [ -S "$MCP_SOCKET_PATH" ] && break; sleep 0.5; done
echo -e "${GREEN}✓ MCP server running${NC}"

AIAGENTPM_DB_PATH="$TEST_DB_PATH" AIAGENTPM_WEBSERVER_PORT="$REST_PORT" \
    "$PROJECT_ROOT/.build/release/rest-server-pm" > /tmp/uc010_webui_rest.log 2>&1 &
REST_PID=$!

for i in {1..10}; do curl -s "http://localhost:$REST_PORT/health" > /dev/null 2>&1 && break; sleep 0.5; done
echo -e "${GREEN}✓ REST server running at :$REST_PORT${NC}"
echo ""

# Step 5: Coordinator起動
echo -e "${YELLOW}Step 5: Starting Coordinator${NC}"

RUNNER_DIR="$PROJECT_ROOT/runner"
PYTHON="${RUNNER_DIR}/.venv/bin/python"
[ ! -x "$PYTHON" ] && PYTHON="python3"

cat > /tmp/coordinator_uc010_webui_config.yaml << EOF
polling_interval: 2
max_concurrent: 1
coordinator_token: ${MCP_COORDINATOR_TOKEN}
mcp_socket_path: $MCP_SOCKET_PATH
ai_providers:
  claude:
    cli_command: claude
    cli_args: ["--dangerously-skip-permissions", "--max-turns", "100"]
agents:
  integ-worker:
    passkey: test-passkey
log_directory: /tmp/coordinator_logs_uc010_webui
EOF

mkdir -p /tmp/coordinator_logs_uc010_webui
$PYTHON -m aiagent_runner --coordinator -c /tmp/coordinator_uc010_webui_config.yaml -v > /tmp/uc010_webui_coordinator.log 2>&1 &
COORDINATOR_PID=$!
sleep 2
echo -e "${GREEN}✓ Coordinator running${NC}"
echo ""

# Step 6: Web UI起動
echo -e "${YELLOW}Step 6: Starting Web UI${NC}"
cd "$WEB_UI_ROOT"

AIAGENTPM_WEBSERVER_PORT="$REST_PORT" npm run dev -- --port "$WEB_UI_PORT" > /tmp/uc010_webui_vite.log 2>&1 &
WEB_UI_PID=$!

for i in {1..20}; do curl -s "http://localhost:$WEB_UI_PORT" > /dev/null 2>&1 && break; sleep 1; done
echo -e "${GREEN}✓ Web UI running at :$WEB_UI_PORT${NC}"
echo ""

# Step 7: Playwrightテスト実行
echo -e "${YELLOW}Step 7: Running Playwright tests${NC}"

INTEGRATION_WEB_URL="http://localhost:$WEB_UI_PORT" \
INTEGRATION_WITH_COORDINATOR="true" \
AIAGENTPM_WEBSERVER_PORT="$REST_PORT" \
npx playwright test \
    --config=e2e/integration/playwright.integration.config.ts \
    task-interrupt.spec.ts \
    2>&1 | tee /tmp/uc010_webui_playwright.log | grep -E "(✓|✗|passed|failed|Polling|SUCCESS|INFO)" || true

echo ""

# Step 8: 結果検証
echo -e "${YELLOW}Step 8: Verifying results${NC}"
echo "=== Tasks ==="
sqlite3 "$TEST_DB_PATH" "SELECT id, title, status FROM tasks WHERE id LIKE 'integ-%';"
echo ""
echo "=== Execution Logs ==="
sqlite3 "$TEST_DB_PATH" "SELECT COUNT(*) as count FROM execution_logs;" 2>/dev/null
echo ""

# 結果判定
if grep -q "passed" /tmp/uc010_webui_playwright.log && ! grep -q "failed" /tmp/uc010_webui_playwright.log; then
    TEST_PASSED=true
    echo -e "${GREEN}UC010 Web UI Integration Test: PASSED${NC}"
    exit 0
else
    echo -e "${RED}UC010 Web UI Integration Test: FAILED${NC}"
    echo "Logs: /tmp/uc010_webui_*.log"
    exit 1
fi
