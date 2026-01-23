#!/bin/bash
# Max Turns Integration Test - AI-to-AI Conversation Auto-Termination
# 会話のmax_turns制限による強制終了テスト
#
# Reference: docs/design/AI_TO_AI_CONVERSATION.md
#
# テスト内容:
#   1. 11往復（22メッセージ）のしりとりを指示
#   2. max_turns=20（デフォルト値）で会話を開始
#   3. 20メッセージ（10往復）時点で会話が自動終了されることを確認
#
# 期待結果:
#   - 会話が10往復（20メッセージ）で自動終了
#   - 会話状態が "ended" になる
#   - MCPログに "auto-ended due to max_turns limit" が記録される

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
TEST_DB_PATH="/tmp/AIAgentPM_MaxTurns.db"
MCP_SOCKET_PATH="/tmp/aiagentpm_maxturns.sock"
REST_PORT="8091"
WEB_UI_PORT="5173"  # Must be 5173 for CORS (allowed origins in REST server)

export MCP_COORDINATOR_TOKEN="test_coordinator_token_maxturns"

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

    # デバッグ用: ログは常に保持
    if [ "${PRESERVE_LOGS:-true}" == "false" ] && [ "$TEST_PASSED" == "true" ]; then
        rm -f /tmp/maxturns_*.log
        rm -f /tmp/coordinator_maxturns_config.yaml
        rm -rf /tmp/coordinator_logs_maxturns
        rm -f "$TEST_DB_PATH" "$TEST_DB_PATH-shm" "$TEST_DB_PATH-wal"
        rm -rf /tmp/maxturns
    else
        echo -e "${YELLOW}Logs preserved for debugging:${NC}"
        echo "  - /tmp/maxturns_*.log"
        echo "  - /tmp/coordinator_logs_maxturns/"
        echo "  - /tmp/maxturns/.ai-pm/agents/*/chat.jsonl"
    fi
}

trap cleanup EXIT

echo "=========================================="
echo -e "${BLUE}Max Turns Integration Test${NC}"
echo -e "${BLUE}(AI-to-AI Conversation Auto-Termination)${NC}"
echo "=========================================="
echo ""

# Step 1: 環境準備
echo -e "${YELLOW}Step 1: Preparing environment${NC}"
ps aux | grep -E "(mcp-server-pm|rest-server-pm)" | grep -v grep | awk '{print $2}' | xargs -I {} kill -9 {} 2>/dev/null || true
lsof -ti:$REST_PORT | xargs kill -9 2>/dev/null || true
lsof -ti:$WEB_UI_PORT | xargs kill -9 2>/dev/null || true

# Kill any existing Coordinator processes, Claude CLI processes, and clean up lock files
pkill -9 -f "aiagent_runner.*coordinator" 2>/dev/null || true
pkill -9 -f "python.*aiagent_runner" 2>/dev/null || true
# Kill any leftover Claude CLI processes from previous test runs
pkill -9 -f "claude.*mcp-server-pm" 2>/dev/null || true
pkill -9 -f "claude.*maxturns" 2>/dev/null || true
# Kill any Claude processes connected to the test socket
lsof -t "$MCP_SOCKET_PATH" 2>/dev/null | xargs kill -9 2>/dev/null || true
rm -f /tmp/aiagent-runner-*/coordinator-*.lock 2>/dev/null || true
rm -rf /tmp/aiagent-runner-* 2>/dev/null || true
# Also kill any processes that might be using our test ports
fuser -k 8091/tcp 2>/dev/null || true
sleep 2  # Wait for processes to fully terminate
echo "Cleaned up existing Coordinator, Claude CLI processes and lock files"

# Verify no lingering processes
if pgrep -f "aiagent_runner" > /dev/null; then
    echo -e "${YELLOW}Warning: Some aiagent_runner processes still running${NC}"
    pgrep -f "aiagent_runner" | xargs ps -p 2>/dev/null || true
fi

rm -f "$TEST_DB_PATH" "$TEST_DB_PATH-shm" "$TEST_DB_PATH-wal" "$MCP_SOCKET_PATH"
rm -rf /tmp/maxturns
mkdir -p /tmp/maxturns
mkdir -p /tmp/maxturns/.ai-pm/agents/maxturns-initiator
mkdir -p /tmp/maxturns/.ai-pm/agents/maxturns-participant
mkdir -p /tmp/maxturns/.ai-pm/agents/maxturns-human
echo "DB: $TEST_DB_PATH"
echo "Working directory: /tmp/maxturns"
echo ""

# Step 2: ビルド確認
echo -e "${YELLOW}Step 2: Checking server binaries${NC}"
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
AIAGENTPM_DB_PATH="$TEST_DB_PATH" "$MCP_SERVER_BIN" daemon \
    --socket-path "$MCP_SOCKET_PATH" --foreground > /tmp/maxturns_mcp_init.log 2>&1 &
INIT_PID=$!
sleep 3
kill "$INIT_PID" 2>/dev/null || true
rm -f "$MCP_SOCKET_PATH"

SQL_FILE="$SCRIPT_DIR/setup/seed-maxturns-data.sql"
[ -f "$SQL_FILE" ] && sqlite3 "$TEST_DB_PATH" < "$SQL_FILE"
echo "Database initialized"
echo ""

# Step 4: サーバー起動
echo -e "${YELLOW}Step 4: Starting servers${NC}"

AIAGENTPM_DB_PATH="$TEST_DB_PATH" "$MCP_SERVER_BIN" daemon \
    --socket-path "$MCP_SOCKET_PATH" --foreground > /tmp/maxturns_mcp.log 2>&1 &
MCP_PID=$!

for i in {1..10}; do [ -S "$MCP_SOCKET_PATH" ] && break; sleep 0.5; done
echo -e "${GREEN}✓ MCP server running${NC}"

AIAGENTPM_DB_PATH="$TEST_DB_PATH" AIAGENTPM_WEBSERVER_PORT="$REST_PORT" \
    "$REST_SERVER_BIN" > /tmp/maxturns_rest.log 2>&1 &
REST_PID=$!

for i in {1..10}; do curl -s "http://localhost:$REST_PORT/health" > /dev/null 2>&1 && break; sleep 0.5; done
echo -e "${GREEN}✓ REST server running at :$REST_PORT${NC}"
echo ""

# Step 5: Coordinator起動
echo -e "${YELLOW}Step 5: Starting Coordinator${NC}"

RUNNER_DIR="$PROJECT_ROOT/runner"
PYTHON="${RUNNER_DIR}/.venv/bin/python"
[ ! -x "$PYTHON" ] && PYTHON="python3"

# max_turns test requires both initiator and participant to be managed
# Use higher max-turns for Claude CLI to allow conversation to proceed
cat > /tmp/coordinator_maxturns_config.yaml << EOF
polling_interval: 2
max_concurrent: 2
coordinator_token: ${MCP_COORDINATOR_TOKEN}
mcp_socket_path: $MCP_SOCKET_PATH
ai_providers:
  claude:
    cli_command: claude
    cli_args: ["--dangerously-skip-permissions", "--max-turns", "100"]
agents:
  maxturns-initiator:
    passkey: test-passkey
  maxturns-participant:
    passkey: test-passkey
log_directory: /tmp/coordinator_logs_maxturns
EOF

mkdir -p /tmp/coordinator_logs_maxturns
$PYTHON -m aiagent_runner --coordinator -c /tmp/coordinator_maxturns_config.yaml -v > /tmp/maxturns_coordinator.log 2>&1 &
COORDINATOR_PID=$!
sleep 3

# Verify Coordinator started successfully
if grep -q "ERROR.*Another Coordinator instance" /tmp/maxturns_coordinator.log 2>/dev/null; then
    echo -e "${RED}✗ Coordinator failed to start - another instance is running${NC}"
    cat /tmp/maxturns_coordinator.log | head -20
    exit 1
fi

if ! kill -0 "$COORDINATOR_PID" 2>/dev/null; then
    echo -e "${RED}✗ Coordinator process died unexpectedly${NC}"
    cat /tmp/maxturns_coordinator.log | tail -20
    exit 1
fi

echo -e "${GREEN}✓ Coordinator running (PID: $COORDINATOR_PID, managing initiator and participant)${NC}"
echo ""

# Step 6: Web UI起動
echo -e "${YELLOW}Step 6: Starting Web UI${NC}"
cd "$WEB_UI_ROOT"

AIAGENTPM_WEBSERVER_PORT="$REST_PORT" npm run dev -- --port "$WEB_UI_PORT" --strictPort > /tmp/maxturns_vite.log 2>&1 &
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
    max-turns.spec.ts \
    2>&1 | tee /tmp/maxturns_playwright.log | grep -E "(✓|✗|passed|failed|MaxTurns|max_turns|auto-term|shiritori)" || true

echo ""

# Step 8: 結果検証
echo -e "${YELLOW}Step 8: Verifying results${NC}"

echo "=== Conversations ==="
sqlite3 "$TEST_DB_PATH" "SELECT id, initiator_agent_id, participant_agent_id, state, max_turns FROM conversations WHERE project_id = 'maxturns-project';" 2>/dev/null || echo "(no conversations)"
echo ""

echo "=== Agent Sessions ==="
sqlite3 "$TEST_DB_PATH" "SELECT id, agent_id, purpose, state FROM agent_sessions WHERE agent_id LIKE 'maxturns-%';" 2>/dev/null || echo "(no sessions)"
echo ""

echo "=== Chat Files ==="
echo "Initiator chat file:"
cat /tmp/maxturns/.ai-pm/agents/maxturns-initiator/chat.jsonl 2>/dev/null || echo "(empty)"
echo ""
echo "Participant chat file:"
cat /tmp/maxturns/.ai-pm/agents/maxturns-participant/chat.jsonl 2>/dev/null || echo "(empty)"
echo ""

# 追加検証: conversationId の確認
echo "=== ConversationId Check ==="
CONV_ID_COUNT=$(grep -o '"conversationId"' /tmp/maxturns/.ai-pm/agents/maxturns-initiator/chat.jsonl 2>/dev/null | wc -l | tr -d ' ')
echo "Messages with conversationId in initiator chat: $CONV_ID_COUNT"

# 追加検証: max_turns limit check
echo ""
echo "=== Max Turns Auto-Termination Check ==="
if grep -q "auto-ended due to max_turns limit" /tmp/maxturns_mcp.log 2>/dev/null; then
    echo -e "${GREEN}✓ Found 'auto-ended due to max_turns limit' in MCP logs${NC}"
    AUTO_ENDED=true
else
    echo -e "${YELLOW}⚠ 'auto-ended due to max_turns limit' not found in MCP logs${NC}"
    AUTO_ENDED=false
fi

# 追加検証: Conversation状態の確認
echo ""
echo "=== Conversation State Check ==="
CONV_STATE=$(sqlite3 "$TEST_DB_PATH" "SELECT state FROM conversations WHERE project_id = 'maxturns-project' LIMIT 1;" 2>/dev/null || echo "unknown")
CONV_MAX_TURNS=$(sqlite3 "$TEST_DB_PATH" "SELECT max_turns FROM conversations WHERE project_id = 'maxturns-project' LIMIT 1;" 2>/dev/null || echo "0")
echo "Conversation state: $CONV_STATE"
echo "Max turns setting: $CONV_MAX_TURNS"

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
if [ -f "/tmp/coordinator_logs_maxturns/maxturns-initiator.log" ]; then
    tail -100 /tmp/coordinator_logs_maxturns/maxturns-initiator.log 2>/dev/null || echo "(no log)"
else
    echo "(log file not found)"
fi
echo ""
echo "--- Participant Log ---"
if [ -f "/tmp/coordinator_logs_maxturns/maxturns-participant.log" ]; then
    tail -100 /tmp/coordinator_logs_maxturns/maxturns-participant.log 2>/dev/null || echo "(no log)"
else
    echo "(log file not found)"
fi

# 結果判定
# テスト成功条件:
# 1. Playwrightテストがパス
# 2. または、Conversation が ended で auto_ended がtrue
if grep -qE "[0-9]+ passed" /tmp/maxturns_playwright.log && ! grep -qE "[0-9]+ failed" /tmp/maxturns_playwright.log; then
    TEST_PASSED=true
    echo ""
    echo -e "${GREEN}Max Turns Integration Test: PASSED${NC}"
    exit 0
elif [ "$CONV_STATE" == "ended" ] && [ "$AUTO_ENDED" == "true" ]; then
    TEST_PASSED=true
    echo ""
    echo -e "${GREEN}Max Turns Integration Test: PASSED (via DB verification)${NC}"
    exit 0
else
    echo ""
    echo -e "${RED}Max Turns Integration Test: FAILED${NC}"
    echo "Logs: /tmp/maxturns_*.log"
    exit 1
fi
