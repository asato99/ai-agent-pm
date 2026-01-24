#!/bin/bash
# UC018-B Web UI Integration Test - Parent Agent Auto-Approval
# 上位エージェント（親）がチャットで依頼した場合の自動承認テスト
#
# UC018との違い:
#   - UC018: 田中（非上位）→ Worker-01 → pending_approval
#   - UC018-B: 佐藤（上位/親）→ Worker-01 → approved（自動承認）

set -e

# 色付き出力
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# パス設定
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WEB_UI_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

# テスト設定
TEST_DB_PATH="/tmp/AIAgentPM_UC018B_WebUI.db"
MCP_SOCKET_PATH="/tmp/aiagentpm_uc018b_webui.sock"
REST_PORT="8090"
WEB_UI_PORT="5173"  # Must be 5173 for CORS (allowed origins in REST server)

MCP_PID=""
REST_PID=""
WEB_UI_PID=""
TEST_PASSED=false

cleanup() {
    echo ""
    echo -e "${YELLOW}Cleanup${NC}"

    [ -n "$WEB_UI_PID" ] && kill -0 "$WEB_UI_PID" 2>/dev/null && kill "$WEB_UI_PID" 2>/dev/null
    [ -n "$REST_PID" ] && kill -0 "$REST_PID" 2>/dev/null && kill "$REST_PID" 2>/dev/null
    [ -n "$MCP_PID" ] && kill -0 "$MCP_PID" 2>/dev/null && kill "$MCP_PID" 2>/dev/null

    rm -f "$MCP_SOCKET_PATH"

    if [ "$TEST_PASSED" == "true" ]; then
        rm -f /tmp/uc018b_webui_*.log
        rm -f "$TEST_DB_PATH" "$TEST_DB_PATH-shm" "$TEST_DB_PATH-wal"
    else
        echo "Logs preserved: /tmp/uc018b_webui_*.log"
    fi
}

trap cleanup EXIT

echo "=========================================="
echo -e "${BLUE}UC018-B Web UI Integration Test${NC}"
echo -e "${BLUE}(Parent Agent Auto-Approval)${NC}"
echo "=========================================="
echo ""

# Step 1: 環境準備
echo -e "${YELLOW}Step 1: Preparing environment${NC}"
ps aux | grep -E "(mcp-server-pm|rest-server-pm)" | grep -v grep | awk '{print $2}' | xargs -I {} kill -9 {} 2>/dev/null || true
rm -f "$TEST_DB_PATH" "$TEST_DB_PATH-shm" "$TEST_DB_PATH-wal" "$MCP_SOCKET_PATH"
mkdir -p /tmp/uc018b_webui_work
echo "DB: $TEST_DB_PATH"
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
    --socket-path "$MCP_SOCKET_PATH" --foreground > /tmp/uc018b_webui_mcp_init.log 2>&1 &
INIT_PID=$!
sleep 3
kill "$INIT_PID" 2>/dev/null || true
rm -f "$MCP_SOCKET_PATH"

SQL_FILE="$SCRIPT_DIR/setup/seed-uc018b-data.sql"
[ -f "$SQL_FILE" ] && sqlite3 "$TEST_DB_PATH" < "$SQL_FILE"
echo "Database initialized with UC018-B test data"

# Create chat files for test data
WORKING_DIR="/tmp/uc018b_webui_work"
CHAT_BASE="$WORKING_DIR/.ai-pm/agents"

mkdir -p "$CHAT_BASE/uc018b-sato"
mkdir -p "$CHAT_BASE/uc018b-worker-01"

cat > "$WORKING_DIR/.ai-pm/.gitignore" << 'GITIGNORE'
# AI Agent PM - auto-generated
chat.jsonl
context.md
GITIGNORE

TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Worker-01's response to Sato (parent)
# 上位からの依頼なので、承認依頼ではなく直接作業開始の旨を伝える
cat > "$CHAT_BASE/uc018b-worker-01/chat.jsonl" << EOF
{"id":{"value":"msg-uc018b-001"},"senderId":{"value":"uc018b-worker-01"},"receiverId":{"value":"uc018b-sato"},"content":"承知しました。API認証機能の実装を開始します。JWTを使用した認証システムを構築します。","createdAt":"$TIMESTAMP"}
EOF

echo "Chat files created"
echo ""

# Step 4: サーバー起動
echo -e "${YELLOW}Step 4: Starting servers${NC}"

AIAGENTPM_DB_PATH="$TEST_DB_PATH" "$MCP_SERVER_BIN" daemon \
    --socket-path "$MCP_SOCKET_PATH" --foreground > /tmp/uc018b_webui_mcp.log 2>&1 &
MCP_PID=$!

for i in {1..10}; do [ -S "$MCP_SOCKET_PATH" ] && break; sleep 0.5; done
echo -e "${GREEN}✓ MCP server running${NC}"

AIAGENTPM_DB_PATH="$TEST_DB_PATH" AIAGENTPM_WEBSERVER_PORT="$REST_PORT" \
    "$REST_SERVER_BIN" > /tmp/uc018b_webui_rest.log 2>&1 &
REST_PID=$!

for i in {1..10}; do curl -s "http://localhost:$REST_PORT/health" > /dev/null 2>&1 && break; sleep 0.5; done
echo -e "${GREEN}✓ REST server running at :$REST_PORT${NC}"
echo ""

# Step 5: Web UI起動
echo -e "${YELLOW}Step 5: Starting Web UI${NC}"
cd "$WEB_UI_ROOT"

AIAGENTPM_WEBSERVER_PORT="$REST_PORT" npm run dev -- --port "$WEB_UI_PORT" > /tmp/uc018b_webui_vite.log 2>&1 &
WEB_UI_PID=$!

for i in {1..20}; do curl -s "http://localhost:$WEB_UI_PORT" > /dev/null 2>&1 && break; sleep 1; done
echo -e "${GREEN}✓ Web UI running at :$WEB_UI_PORT${NC}"
echo ""

# Step 6: Playwrightテスト実行
echo -e "${YELLOW}Step 6: Running Playwright tests${NC}"
echo ""

INTEGRATION_WEB_URL="http://localhost:$WEB_UI_PORT" \
AIAGENTPM_WEBSERVER_PORT="$REST_PORT" \
npx playwright test \
    --config=e2e/integration/playwright.integration.config.ts \
    chat-task-auto-approval.spec.ts \
    2>&1 | tee /tmp/uc018b_webui_playwright.log | grep -E "(✓|✗|passed|failed|skipped|Step)" || true

echo ""

# Step 7: 結果検証
echo -e "${YELLOW}Step 7: Verifying results${NC}"
echo "=== Agents ==="
sqlite3 "$TEST_DB_PATH" "SELECT id, name, role, parent_agent_id FROM agents WHERE id LIKE 'uc018b-%';"
echo ""
echo "=== Tasks ==="
sqlite3 "$TEST_DB_PATH" "SELECT id, title, approval_status, requester_id FROM tasks WHERE id LIKE 'uc018b-%';" 2>/dev/null || echo "(no tasks)"
echo ""

# 結果判定
PASSED_COUNT=$(grep -c "✓" /tmp/uc018b_webui_playwright.log 2>/dev/null | tr -d '\n' || echo "0")
FAILED_COUNT=$(grep -c "✘" /tmp/uc018b_webui_playwright.log 2>/dev/null | tr -d '\n' || echo "0")
SKIPPED_COUNT=$(grep -c "skipped" /tmp/uc018b_webui_playwright.log 2>/dev/null | tr -d '\n' || echo "0")

echo ""
echo "=== Test Summary ==="
echo "Passed: $PASSED_COUNT"
echo "Failed: $FAILED_COUNT"
echo "Skipped: $SKIPPED_COUNT"
echo ""

if [ "$FAILED_COUNT" -gt 0 ]; then
    echo -e "${RED}UC018-B: $FAILED_COUNT tests failed${NC}"
    echo "Check logs: /tmp/uc018b_webui_*.log"
    exit 1
else
    echo -e "${GREEN}UC018-B Web UI Integration Test: ALL PASSED${NC}"
    TEST_PASSED=true
    exit 0
fi
