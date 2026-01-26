#!/bin/bash
# UC019 Web UI Integration Test - Chat and Task Simultaneous Execution
# チャットとタスクの同時実行テスト
#
# Reference: docs/usecase/UC019_ChatTaskSimultaneousExecution.md
#
# フロー:
#   1. テスト環境準備
#   2. MCP + RESTサーバー起動
#   3. Coordinator起動
#   4. Web UI起動
#   5. Playwrightテスト実行
#   6. 結果検証（Chat + Task 両セッションの同時実行確認）
#
# 検証ポイント:
#   - タスクをin_progressに移動してもチャットセッションが維持される
#   - タスク実行中にチャットで進捗確認できる
#   - 両セッションが独立して動作する

set -e

# 色付き出力
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# パス設定 (絶対パスに変換)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WEB_UI_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

# テスト設定
TEST_DB_PATH="/tmp/AIAgentPM_UC019_WebUI.db"
MCP_SOCKET_PATH="/tmp/aiagentpm_uc019_webui.sock"
REST_PORT="8089"
WEB_UI_PORT="5173"  # Must be 5173 for CORS (allowed origins in REST server)

export MCP_COORDINATOR_TOKEN="test_coordinator_token_uc019_webui"

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

    # Kill any gemini/claude processes spawned for this test
    pkill -f "uc019-worker" 2>/dev/null || true

    rm -f "$MCP_SOCKET_PATH"

    if [ "$TEST_PASSED" == "true" ]; then
        rm -f /tmp/uc019_webui_*.log
        rm -f /tmp/coordinator_uc019_webui_config.yaml
        rm -rf /tmp/coordinator_logs_uc019_webui
        rm -f "$TEST_DB_PATH" "$TEST_DB_PATH-shm" "$TEST_DB_PATH-wal"
        rm -rf /tmp/uc019
        echo -e "${GREEN}Test artifacts cleaned up${NC}"
    else
        echo "Logs preserved: /tmp/uc019_webui_*.log"
        echo "DB preserved: $TEST_DB_PATH"
    fi
}

trap cleanup EXIT

echo "=========================================="
echo -e "${BLUE}UC019 Web UI Integration Test${NC}"
echo -e "${CYAN}(Chat and Task Simultaneous Execution)${NC}"
echo "=========================================="
echo ""
echo "Key verification points:"
echo "  1. Chat session maintained when task moves to in_progress"
echo "  2. Chat responses work during task execution"
echo "  3. Both sessions run independently"
echo ""

# Step 1: 環境準備
echo -e "${YELLOW}Step 1: Preparing environment${NC}"
ps aux | grep -E "(mcp-server-pm|rest-server-pm)" | grep -v grep | awk '{print $2}' | xargs -I {} kill -9 {} 2>/dev/null || true
# Kill any processes using the required ports
lsof -ti:$REST_PORT | xargs kill -9 2>/dev/null || true
lsof -ti:$WEB_UI_PORT | xargs kill -9 2>/dev/null || true
rm -f "$TEST_DB_PATH" "$TEST_DB_PATH-shm" "$TEST_DB_PATH-wal" "$MCP_SOCKET_PATH"
mkdir -p /tmp/uc019
mkdir -p /tmp/uc019/.ai-pm/agents/uc019-worker
mkdir -p /tmp/uc019/.ai-pm/agents/uc019-owner
echo "DB: $TEST_DB_PATH"
echo "Working directory: /tmp/uc019"
echo ""

# Step 2: ビルド確認
echo -e "${YELLOW}Step 2: Checking server binaries${NC}"
cd "$PROJECT_ROOT"

# Find binaries in DerivedData (Xcode build) or .build/release (SPM build)
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
    echo "  MCP: $MCP_SERVER_BIN"
    echo "  REST: $REST_SERVER_BIN"
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

# Step 3: DB初期化
echo -e "${YELLOW}Step 3: Initializing database${NC}"
# Use daemon command with AIAGENTPM_DB_PATH to auto-initialize the database
AIAGENTPM_DB_PATH="$TEST_DB_PATH" "$MCP_SERVER_BIN" daemon \
    --socket-path "$MCP_SOCKET_PATH" --foreground > /tmp/uc019_webui_mcp_init.log 2>&1 &
INIT_PID=$!
sleep 3
kill "$INIT_PID" 2>/dev/null || true
rm -f "$MCP_SOCKET_PATH"

# Load UC019 test data
SQL_FILE="$SCRIPT_DIR/setup/seed-uc019-data.sql"
if [ -f "$SQL_FILE" ]; then
    sqlite3 "$TEST_DB_PATH" < "$SQL_FILE"
    echo -e "${GREEN}✓ Test data loaded${NC}"
else
    echo -e "${RED}Error: SQL file not found: $SQL_FILE${NC}"
    exit 1
fi

# Verify data
AGENT_COUNT=$(sqlite3 "$TEST_DB_PATH" "SELECT COUNT(*) FROM agents WHERE id LIKE 'uc019-%';")
echo "  Agents: $AGENT_COUNT"
echo ""

# Step 4: サーバー起動
echo -e "${YELLOW}Step 4: Starting servers${NC}"

AIAGENTPM_DB_PATH="$TEST_DB_PATH" "$MCP_SERVER_BIN" daemon \
    --socket-path "$MCP_SOCKET_PATH" --foreground > /tmp/uc019_webui_mcp.log 2>&1 &
MCP_PID=$!

for i in {1..10}; do [ -S "$MCP_SOCKET_PATH" ] && break; sleep 0.5; done
echo -e "${GREEN}✓ MCP server running${NC}"

AIAGENTPM_DB_PATH="$TEST_DB_PATH" AIAGENTPM_WEBSERVER_PORT="$REST_PORT" \
    "$REST_SERVER_BIN" > /tmp/uc019_webui_rest.log 2>&1 &
REST_PID=$!

for i in {1..10}; do curl -s "http://localhost:$REST_PORT/health" > /dev/null 2>&1 && break; sleep 0.5; done
echo -e "${GREEN}✓ REST server running at :$REST_PORT${NC}"
echo ""

# Step 5: Coordinator起動
echo -e "${YELLOW}Step 5: Starting Coordinator${NC}"

RUNNER_DIR="$PROJECT_ROOT/runner"
PYTHON="${RUNNER_DIR}/.venv/bin/python"
[ ! -x "$PYTHON" ] && PYTHON="python3"

# Check if gemini CLI is available
GEMINI_CLI="gemini"
if ! command -v "$GEMINI_CLI" &> /dev/null; then
    echo -e "${YELLOW}Warning: gemini CLI not found. Using claude instead.${NC}"
    AI_PROVIDER="claude"
    AI_CLI="claude"
    AI_ARGS='["--dangerously-skip-permissions", "--max-turns", "50"]'
else
    AI_PROVIDER="gemini"
    AI_CLI="gemini"
    AI_ARGS='["-y", "--verbose"]'
fi

cat > /tmp/coordinator_uc019_webui_config.yaml << EOF
polling_interval: 2
max_concurrent: 2
coordinator_token: ${MCP_COORDINATOR_TOKEN}
mcp_socket_path: $MCP_SOCKET_PATH
ai_providers:
  ${AI_PROVIDER}:
    cli_command: ${AI_CLI}
    cli_args: ${AI_ARGS}
agents:
  uc019-worker:
    passkey: test-passkey
    ai_type: ${AI_PROVIDER}
log_directory: /tmp/coordinator_logs_uc019_webui
EOF

mkdir -p /tmp/coordinator_logs_uc019_webui
$PYTHON -m aiagent_runner --coordinator -c /tmp/coordinator_uc019_webui_config.yaml -v > /tmp/uc019_webui_coordinator.log 2>&1 &
COORDINATOR_PID=$!
sleep 2
if kill -0 "$COORDINATOR_PID" 2>/dev/null; then
    echo -e "${GREEN}✓ Coordinator running (AI: ${AI_PROVIDER})${NC}"
else
    echo -e "${RED}✗ Coordinator failed to start${NC}"
    cat /tmp/uc019_webui_coordinator.log
    exit 1
fi
echo ""

# Step 6: Web UI起動
echo -e "${YELLOW}Step 6: Starting Web UI${NC}"
cd "$WEB_UI_ROOT"

# vite.config.ts uses AIAGENTPM_WEBSERVER_PORT env var
AIAGENTPM_WEBSERVER_PORT="$REST_PORT" npm run dev -- --port "$WEB_UI_PORT" --strictPort > /tmp/uc019_webui_vite.log 2>&1 &
WEB_UI_PID=$!

for i in {1..20}; do curl -s "http://localhost:$WEB_UI_PORT" > /dev/null 2>&1 && break; sleep 1; done
if curl -s "http://localhost:$WEB_UI_PORT" > /dev/null 2>&1; then
    echo -e "${GREEN}✓ Web UI running at :$WEB_UI_PORT${NC}"
else
    echo -e "${RED}✗ Web UI failed to start${NC}"
    cat /tmp/uc019_webui_vite.log
    exit 1
fi
echo ""

# Step 7: Playwrightテスト実行
echo -e "${YELLOW}Step 7: Running Playwright tests${NC}"
echo ""

INTEGRATION_WEB_URL="http://localhost:$WEB_UI_PORT" \
INTEGRATION_WITH_COORDINATOR="true" \
AIAGENTPM_WEBSERVER_PORT="$REST_PORT" \
npx playwright test \
    --config=e2e/integration/playwright.integration.config.ts \
    chat-task-simultaneous.spec.ts \
    2>&1 | tee /tmp/uc019_webui_playwright.log | grep -E "(✓|✗|passed|failed|UC019|session|chat|task|simultaneous|maintained|in_progress)" || true

echo ""

# Step 8: 結果検証
echo -e "${YELLOW}Step 8: Verifying results${NC}"

echo "=== Agent Sessions ==="
sqlite3 "$TEST_DB_PATH" "SELECT id, agent_id, purpose, state, datetime(created_at, 'localtime') as created FROM agent_sessions WHERE agent_id LIKE 'uc019-%' ORDER BY created_at;" 2>/dev/null || echo "(no sessions)"
echo ""

echo "=== Session Purpose Distribution ==="
sqlite3 "$TEST_DB_PATH" "SELECT purpose, COUNT(*) as count FROM agent_sessions WHERE agent_id LIKE 'uc019-%' GROUP BY purpose;" 2>/dev/null || echo "(no sessions)"
echo ""

echo "=== Tasks Created ==="
sqlite3 "$TEST_DB_PATH" "SELECT id, title, status, assignee_id FROM tasks WHERE project_id = 'uc019-project';" 2>/dev/null || echo "(no tasks)"
echo ""

echo "=== Pending Agent Purposes ==="
sqlite3 "$TEST_DB_PATH" "SELECT agent_id, purpose, datetime(started_at, 'localtime') as started FROM pending_agent_purposes WHERE agent_id LIKE 'uc019-%';" 2>/dev/null || echo "(none)"
echo ""

echo "=== Chat Messages ==="
sqlite3 "$TEST_DB_PATH" "SELECT sender_id, receiver_id, substr(content, 1, 50) as content_preview FROM chat_messages WHERE sender_id LIKE 'uc019-%' OR receiver_id LIKE 'uc019-%' ORDER BY created_at LIMIT 10;" 2>/dev/null || echo "(no messages)"
echo ""

echo "=== Key Verification ==="
# Check if both chat and task sessions were created
CHAT_SESSIONS=$(sqlite3 "$TEST_DB_PATH" "SELECT COUNT(*) FROM agent_sessions WHERE agent_id = 'uc019-worker' AND purpose = 'chat';" 2>/dev/null || echo "0")
TASK_SESSIONS=$(sqlite3 "$TEST_DB_PATH" "SELECT COUNT(*) FROM agent_sessions WHERE agent_id = 'uc019-worker' AND purpose = 'task';" 2>/dev/null || echo "0")
echo "Chat sessions for worker: $CHAT_SESSIONS"
echo "Task sessions for worker: $TASK_SESSIONS"

if [ "$CHAT_SESSIONS" -gt 0 ] && [ "$TASK_SESSIONS" -gt 0 ]; then
    echo -e "${GREEN}✓ Both chat and task sessions were created${NC}"
else
    echo -e "${YELLOW}⚠ Expected both chat and task sessions${NC}"
fi
echo ""

# 結果判定
if grep -qE "[0-9]+ passed" /tmp/uc019_webui_playwright.log && ! grep -qE "[0-9]+ failed" /tmp/uc019_webui_playwright.log; then
    TEST_PASSED=true
    echo -e "${GREEN}=========================================="
    echo -e "UC019 Web UI Integration Test: PASSED"
    echo -e "==========================================${NC}"
    exit 0
else
    echo -e "${RED}=========================================="
    echo -e "UC019 Web UI Integration Test: FAILED"
    echo -e "==========================================${NC}"
    echo ""
    echo "Debug info:"
    echo "  Coordinator log: /tmp/uc019_webui_coordinator.log"
    echo "  MCP log: /tmp/uc019_webui_mcp.log"
    echo "  REST log: /tmp/uc019_webui_rest.log"
    echo "  Playwright log: /tmp/uc019_webui_playwright.log"
    exit 1
fi
