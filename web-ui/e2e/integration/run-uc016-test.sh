#!/bin/bash
# UC016 Web UI Integration Test - AI-to-AI Conversation
# AIエージェント間会話テスト
#
# Reference: docs/usecase/UC016_AIToAIConversation.md
#            docs/design/AI_TO_AI_CONVERSATION.md
#
# フロー:
#   1. テスト環境準備
#   2. MCP + RESTサーバー起動
#   3. Coordinator起動 (initiator, participant両方管理)
#   4. Web UI起動
#   5. Playwrightテスト実行
#   6. 結果検証（Conversation状態、chat.jsonl、conversationId）

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
TEST_DB_PATH="/tmp/AIAgentPM_UC016_WebUI.db"
MCP_SOCKET_PATH="/tmp/aiagentpm_uc016_webui.sock"
REST_PORT="8089"
WEB_UI_PORT="5173"  # Must be 5173 for CORS (allowed origins in REST server)

export MCP_COORDINATOR_TOKEN="test_coordinator_token_uc016_webui"

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

    # デバッグ用: ログは常に保持（PRESERVE_LOGS=false で削除可能）
    if [ "${PRESERVE_LOGS:-true}" == "false" ] && [ "$TEST_PASSED" == "true" ]; then
        rm -f /tmp/uc016_webui_*.log
        rm -f /tmp/coordinator_uc016_webui_config.yaml
        rm -rf /tmp/coordinator_logs_uc016_webui
        rm -f "$TEST_DB_PATH" "$TEST_DB_PATH-shm" "$TEST_DB_PATH-wal"
        rm -rf /tmp/uc016
    else
        echo -e "${YELLOW}Logs preserved for debugging:${NC}"
        echo "  - /tmp/uc016_webui_*.log"
        echo "  - /tmp/coordinator_logs_uc016_webui/"
        echo "  - /tmp/uc016/.ai-pm/agents/*/chat.jsonl"
    fi
}

trap cleanup EXIT

echo "=========================================="
echo -e "${BLUE}UC016 Web UI Integration Test${NC}"
echo -e "${BLUE}(AI-to-AI Conversation)${NC}"
echo "=========================================="
echo ""

# Step 1: 環境準備
echo -e "${YELLOW}Step 1: Preparing environment${NC}"
ps aux | grep -E "(mcp-server-pm|rest-server-pm)" | grep -v grep | awk '{print $2}' | xargs -I {} kill -9 {} 2>/dev/null || true
# Kill any processes using the required ports
lsof -ti:$REST_PORT | xargs kill -9 2>/dev/null || true
lsof -ti:$WEB_UI_PORT | xargs kill -9 2>/dev/null || true
rm -f "$TEST_DB_PATH" "$TEST_DB_PATH-shm" "$TEST_DB_PATH-wal" "$MCP_SOCKET_PATH"
rm -rf /tmp/uc016  # Clear chat files from previous runs
mkdir -p /tmp/uc016
mkdir -p /tmp/uc016/.ai-pm/agents/uc016-initiator
mkdir -p /tmp/uc016/.ai-pm/agents/uc016-participant
mkdir -p /tmp/uc016/.ai-pm/agents/uc016-human
echo "DB: $TEST_DB_PATH"
echo "Working directory: /tmp/uc016"
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
    --socket-path "$MCP_SOCKET_PATH" --foreground > /tmp/uc016_webui_mcp_init.log 2>&1 &
INIT_PID=$!
sleep 3
kill "$INIT_PID" 2>/dev/null || true
rm -f "$MCP_SOCKET_PATH"

SQL_FILE="$SCRIPT_DIR/setup/seed-uc016-data.sql"
[ -f "$SQL_FILE" ] && sqlite3 "$TEST_DB_PATH" < "$SQL_FILE"
echo "Database initialized"
echo ""

# Step 4: サーバー起動
echo -e "${YELLOW}Step 4: Starting servers${NC}"

AIAGENTPM_DB_PATH="$TEST_DB_PATH" "$MCP_SERVER_BIN" daemon \
    --socket-path "$MCP_SOCKET_PATH" --foreground > /tmp/uc016_webui_mcp.log 2>&1 &
MCP_PID=$!

for i in {1..10}; do [ -S "$MCP_SOCKET_PATH" ] && break; sleep 0.5; done
echo -e "${GREEN}✓ MCP server running${NC}"

AIAGENTPM_DB_PATH="$TEST_DB_PATH" AIAGENTPM_WEBSERVER_PORT="$REST_PORT" \
    "$REST_SERVER_BIN" > /tmp/uc016_webui_rest.log 2>&1 &
REST_PID=$!

for i in {1..10}; do curl -s "http://localhost:$REST_PORT/health" > /dev/null 2>&1 && break; sleep 0.5; done
echo -e "${GREEN}✓ REST server running at :$REST_PORT${NC}"
echo ""

# Step 5: Coordinator起動
echo -e "${YELLOW}Step 5: Starting Coordinator${NC}"

RUNNER_DIR="$PROJECT_ROOT/runner"
PYTHON="${RUNNER_DIR}/.venv/bin/python"
[ ! -x "$PYTHON" ] && PYTHON="python3"

# UC016 requires both initiator and participant to be managed
cat > /tmp/coordinator_uc016_webui_config.yaml << EOF
polling_interval: 2
max_concurrent: 2
coordinator_token: ${MCP_COORDINATOR_TOKEN}
mcp_socket_path: $MCP_SOCKET_PATH
ai_providers:
  claude:
    cli_command: claude
    cli_args: ["--dangerously-skip-permissions", "--max-turns", "50"]
agents:
  uc016-initiator:
    passkey: test-passkey
  uc016-participant:
    passkey: test-passkey
log_directory: /tmp/coordinator_logs_uc016_webui
EOF

mkdir -p /tmp/coordinator_logs_uc016_webui
$PYTHON -m aiagent_runner --coordinator -c /tmp/coordinator_uc016_webui_config.yaml -v > /tmp/uc016_webui_coordinator.log 2>&1 &
COORDINATOR_PID=$!
sleep 2
echo -e "${GREEN}✓ Coordinator running (managing initiator and participant)${NC}"
echo ""

# Step 6: Web UI起動
echo -e "${YELLOW}Step 6: Starting Web UI${NC}"
cd "$WEB_UI_ROOT"

# vite.config.ts uses AIAGENTPM_WEBSERVER_PORT env var
# Use --strictPort to fail if port is in use (instead of auto-selecting another port)
AIAGENTPM_WEBSERVER_PORT="$REST_PORT" npm run dev -- --port "$WEB_UI_PORT" --strictPort > /tmp/uc016_webui_vite.log 2>&1 &
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
    ai-conversation.spec.ts \
    2>&1 | tee /tmp/uc016_webui_playwright.log | grep -E "(✓|✗|passed|failed|UC016|conversation|Conversation|shiritori)" || true

echo ""

# Step 8: 結果検証
echo -e "${YELLOW}Step 8: Verifying results${NC}"

echo "=== Conversations ==="
sqlite3 "$TEST_DB_PATH" "SELECT id, initiator_agent_id, participant_agent_id, state, purpose FROM conversations WHERE project_id = 'uc016-project';" 2>/dev/null || echo "(no conversations)"
echo ""

echo "=== Agent Sessions ==="
sqlite3 "$TEST_DB_PATH" "SELECT id, agent_id, purpose, state FROM agent_sessions WHERE agent_id LIKE 'uc016-%';" 2>/dev/null || echo "(no sessions)"
echo ""

echo "=== Chat Files ==="
echo "Initiator chat file:"
cat /tmp/uc016/.ai-pm/agents/uc016-initiator/chat.jsonl 2>/dev/null || echo "(empty)"
echo ""
echo "Participant chat file:"
cat /tmp/uc016/.ai-pm/agents/uc016-participant/chat.jsonl 2>/dev/null || echo "(empty)"
echo ""
echo "Human chat file:"
cat /tmp/uc016/.ai-pm/agents/uc016-human/chat.jsonl 2>/dev/null || echo "(empty)"
echo ""

# 追加検証: conversationId の確認
echo "=== ConversationId Check ==="
CONV_ID_COUNT=$(grep -o '"conversationId"' /tmp/uc016/.ai-pm/agents/uc016-initiator/chat.jsonl 2>/dev/null | wc -l | tr -d ' ')
echo "Messages with conversationId in initiator chat: $CONV_ID_COUNT"

# 追加検証: Conversation状態の確認
echo ""
echo "=== Conversation State Check ==="
CONV_STATE=$(sqlite3 "$TEST_DB_PATH" "SELECT state FROM conversations WHERE project_id = 'uc016-project' LIMIT 1;" 2>/dev/null || echo "unknown")
echo "Conversation state: $CONV_STATE"
if [ "$CONV_STATE" == "ended" ]; then
    echo -e "${GREEN}✓ Conversation properly ended${NC}"
else
    echo -e "${YELLOW}⚠ Conversation not ended (state: $CONV_STATE)${NC}"
fi

# AIエージェントのログ表示（会話終了付近の挙動確認用）
echo ""
echo "=== AI Agent Logs (Last 100 lines each) ==="
echo ""
echo "--- Initiator Log ---"
if [ -f "/tmp/coordinator_logs_uc016_webui/uc016-initiator.log" ]; then
    tail -100 /tmp/coordinator_logs_uc016_webui/uc016-initiator.log 2>/dev/null || echo "(no log)"
else
    echo "(log file not found)"
fi
echo ""
echo "--- Participant Log ---"
if [ -f "/tmp/coordinator_logs_uc016_webui/uc016-participant.log" ]; then
    tail -100 /tmp/coordinator_logs_uc016_webui/uc016-participant.log 2>/dev/null || echo "(no log)"
else
    echo "(log file not found)"
fi

# 結果判定
if grep -qE "[0-9]+ passed" /tmp/uc016_webui_playwright.log && ! grep -qE "[0-9]+ failed" /tmp/uc016_webui_playwright.log; then
    TEST_PASSED=true
    echo -e "${GREEN}UC016 Web UI Integration Test: PASSED${NC}"
    exit 0
else
    echo -e "${RED}UC016 Web UI Integration Test: FAILED${NC}"
    echo "Logs: /tmp/uc016_webui_*.log"
    exit 1
fi
