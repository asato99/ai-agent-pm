#!/bin/bash
# Pilot Test: hello-world scenario
#
# Real AI agents creating a Hello World Python script.
# This test uses actual LLM API calls (costs money, takes time).
#
# Flow:
#   1. Environment preparation
#   2. MCP + REST server startup
#   3. Coordinator startup (real LLM)
#   4. Web UI startup
#   5. Playwright test execution
#   6. Deliverable verification
#
# Reference: docs/design/PILOT_TESTING.md
#            web-ui/e2e/pilot/scenarios/hello-world.md

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Path configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WEB_UI_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

# Pilot test configuration
TEST_DB_PATH="/tmp/AIAgentPM_Pilot_Hello.db"
MCP_SOCKET_PATH="/tmp/aiagentpm_pilot_hello.sock"
REST_PORT="8085"
WEB_UI_PORT="5173"  # Must be 5173 for CORS
WORKSPACE_PATH="/tmp/pilot_hello_workspace"

export MCP_COORDINATOR_TOKEN="pilot_coordinator_token_hello"
export PILOT_WORKSPACE_PATH="$WORKSPACE_PATH"

# Process IDs for cleanup
COORDINATOR_PID=""
MCP_PID=""
REST_PID=""
WEB_UI_PID=""
TEST_PASSED=false

cleanup() {
    echo ""
    echo -e "${YELLOW}Cleanup${NC}"

    # Stop processes
    [ -n "$WEB_UI_PID" ] && kill -0 "$WEB_UI_PID" 2>/dev/null && kill "$WEB_UI_PID" 2>/dev/null
    [ -n "$COORDINATOR_PID" ] && kill -0 "$COORDINATOR_PID" 2>/dev/null && kill "$COORDINATOR_PID" 2>/dev/null
    [ -n "$REST_PID" ] && kill -0 "$REST_PID" 2>/dev/null && kill "$REST_PID" 2>/dev/null
    [ -n "$MCP_PID" ] && kill -0 "$MCP_PID" 2>/dev/null && kill "$MCP_PID" 2>/dev/null

    # Clean socket
    rm -f "$MCP_SOCKET_PATH"

    if [ "$TEST_PASSED" == "true" ]; then
        echo -e "${GREEN}Cleaning up temporary files...${NC}"
        rm -f /tmp/pilot_hello_*.log
        rm -f /tmp/coordinator_pilot_hello_config.yaml
        rm -rf /tmp/coordinator_logs_pilot_hello
        rm -f "$TEST_DB_PATH" "$TEST_DB_PATH-shm" "$TEST_DB_PATH-wal"
    else
        echo -e "${YELLOW}Logs preserved for debugging:${NC}"
        echo "  - /tmp/pilot_hello_*.log"
        echo "  - /tmp/coordinator_logs_pilot_hello/"
        echo "  - $WORKSPACE_PATH"
        echo "  - $TEST_DB_PATH"
    fi
}

trap cleanup EXIT

# Header
echo "=========================================="
echo -e "${BLUE}Pilot Test: hello-world${NC}"
echo -e "${BLUE}(Real AI agents creating Hello World)${NC}"
echo "=========================================="
echo ""
echo -e "${YELLOW}NOTICE: This test uses real LLM API calls.${NC}"
echo -e "${YELLOW}        Estimated time: 10-30 minutes${NC}"
echo -e "${YELLOW}        API costs will be incurred.${NC}"
echo ""

# Step 1: Environment preparation
echo -e "${YELLOW}Step 1: Preparing environment${NC}"

# Kill any existing processes
ps aux | grep -E "(mcp-server-pm|rest-server-pm)" | grep -v grep | awk '{print $2}' | xargs -I {} kill -9 {} 2>/dev/null || true

# Clean up previous test artifacts
rm -f "$TEST_DB_PATH" "$TEST_DB_PATH-shm" "$TEST_DB_PATH-wal" "$MCP_SOCKET_PATH"
rm -rf "$WORKSPACE_PATH"
mkdir -p "$WORKSPACE_PATH"

echo "  DB: $TEST_DB_PATH"
echo "  Workspace: $WORKSPACE_PATH"
echo ""

# Step 2: Check server binaries
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

# Step 3: Initialize database
echo -e "${YELLOW}Step 3: Initializing database${NC}"

# Start MCP server briefly to initialize DB schema
AIAGENTPM_DB_PATH="$TEST_DB_PATH" "$MCP_SERVER_BIN" daemon \
    --socket-path "$MCP_SOCKET_PATH" --foreground > /tmp/pilot_hello_mcp_init.log 2>&1 &
INIT_PID=$!
sleep 3
kill "$INIT_PID" 2>/dev/null || true
rm -f "$MCP_SOCKET_PATH"

# Seed pilot data
SQL_FILE="$SCRIPT_DIR/setup/seed-pilot-hello.sql"
if [ -f "$SQL_FILE" ]; then
    sqlite3 "$TEST_DB_PATH" < "$SQL_FILE"
    echo -e "${GREEN}✓ Database initialized with pilot agents${NC}"
else
    echo -e "${RED}ERROR: Seed file not found: $SQL_FILE${NC}"
    exit 1
fi

# Verify seed data
echo "  Agents:"
sqlite3 "$TEST_DB_PATH" "SELECT '    - ' || id || ' (' || type || ')' FROM agents WHERE id LIKE 'pilot-%';"
echo ""

# Step 4: Start servers
echo -e "${YELLOW}Step 4: Starting servers${NC}"

# Start MCP server
AIAGENTPM_DB_PATH="$TEST_DB_PATH" "$MCP_SERVER_BIN" daemon \
    --socket-path "$MCP_SOCKET_PATH" --foreground > /tmp/pilot_hello_mcp.log 2>&1 &
MCP_PID=$!

for i in {1..10}; do [ -S "$MCP_SOCKET_PATH" ] && break; sleep 0.5; done
if [ -S "$MCP_SOCKET_PATH" ]; then
    echo -e "${GREEN}✓ MCP server running${NC}"
else
    echo -e "${RED}ERROR: MCP server failed to start${NC}"
    cat /tmp/pilot_hello_mcp.log
    exit 1
fi

# Start REST server
AIAGENTPM_DB_PATH="$TEST_DB_PATH" AIAGENTPM_WEBSERVER_PORT="$REST_PORT" \
    "$REST_SERVER_BIN" > /tmp/pilot_hello_rest.log 2>&1 &
REST_PID=$!

for i in {1..10}; do curl -s "http://localhost:$REST_PORT/health" > /dev/null 2>&1 && break; sleep 0.5; done
if curl -s "http://localhost:$REST_PORT/health" > /dev/null 2>&1; then
    echo -e "${GREEN}✓ REST server running at :$REST_PORT${NC}"
else
    echo -e "${RED}ERROR: REST server failed to start${NC}"
    cat /tmp/pilot_hello_rest.log
    exit 1
fi
echo ""

# Step 5: Start Coordinator
echo -e "${YELLOW}Step 5: Starting Coordinator (with real LLM)${NC}"

RUNNER_DIR="$PROJECT_ROOT/runner"
PYTHON="${RUNNER_DIR}/.venv/bin/python"
[ ! -x "$PYTHON" ] && PYTHON="python3"

# Create Coordinator config
cat > /tmp/coordinator_pilot_hello_config.yaml << EOF
polling_interval: 5
max_concurrent: 3
coordinator_token: ${MCP_COORDINATOR_TOKEN}
mcp_socket_path: $MCP_SOCKET_PATH
ai_providers:
  claude:
    cli_command: claude
    cli_args: ["--dangerously-skip-permissions", "--max-turns", "50"]
agents:
  pilot-manager:
    passkey: test-passkey
  pilot-worker-dev:
    passkey: test-passkey
  pilot-worker-review:
    passkey: test-passkey
log_directory: /tmp/coordinator_logs_pilot_hello
log_upload:
  enabled: true
work_directory: $WORKSPACE_PATH
EOF

mkdir -p /tmp/coordinator_logs_pilot_hello

AIAGENTPM_WEBSERVER_PORT="$REST_PORT" $PYTHON -m aiagent_runner --coordinator \
    -c /tmp/coordinator_pilot_hello_config.yaml -v > /tmp/pilot_hello_coordinator.log 2>&1 &
COORDINATOR_PID=$!
sleep 2

if kill -0 "$COORDINATOR_PID" 2>/dev/null; then
    echo -e "${GREEN}✓ Coordinator running (real LLM mode)${NC}"
else
    echo -e "${RED}ERROR: Coordinator failed to start${NC}"
    cat /tmp/pilot_hello_coordinator.log
    exit 1
fi
echo ""

# Step 6: Start Web UI
echo -e "${YELLOW}Step 6: Starting Web UI${NC}"
cd "$WEB_UI_ROOT"

AIAGENTPM_WEBSERVER_PORT="$REST_PORT" npm run dev -- --port "$WEB_UI_PORT" > /tmp/pilot_hello_vite.log 2>&1 &
WEB_UI_PID=$!

for i in {1..30}; do curl -s "http://localhost:$WEB_UI_PORT" > /dev/null 2>&1 && break; sleep 1; done
if curl -s "http://localhost:$WEB_UI_PORT" > /dev/null 2>&1; then
    echo -e "${GREEN}✓ Web UI running at :$WEB_UI_PORT${NC}"
else
    echo -e "${RED}ERROR: Web UI failed to start${NC}"
    cat /tmp/pilot_hello_vite.log | tail -20
    exit 1
fi
echo ""

# Step 7: Run Playwright test
echo -e "${YELLOW}Step 7: Running Playwright pilot test${NC}"
echo -e "${YELLOW}        (Waiting for AI agents to complete development)${NC}"
echo ""

PILOT_WEB_URL="http://localhost:$WEB_UI_PORT" \
PILOT_WITH_COORDINATOR="true" \
PILOT_WORKSPACE_PATH="$WORKSPACE_PATH" \
AIAGENTPM_WEBSERVER_PORT="$REST_PORT" \
npx playwright test \
    --config=e2e/pilot/playwright.pilot.config.ts \
    hello-world.spec.ts \
    2>&1 | tee /tmp/pilot_hello_playwright.log

echo ""

# Step 8: Verify deliverables
echo -e "${YELLOW}Step 8: Verifying deliverables${NC}"
echo ""

HELLO_PY="$WORKSPACE_PATH/hello.py"
if [ -f "$HELLO_PY" ]; then
    echo -e "${GREEN}✓ hello.py exists${NC}"
    echo ""
    echo "Content:"
    echo "--------"
    cat "$HELLO_PY"
    echo "--------"
    echo ""

    echo "Execution:"
    OUTPUT=$(python3 "$HELLO_PY" 2>&1) || true
    echo "Output: \"$OUTPUT\""

    if [ "$OUTPUT" == "Hello, World!" ]; then
        echo -e "${GREEN}✓ Output is correct${NC}"
    else
        echo -e "${YELLOW}⚠ Output differs from expected \"Hello, World!\"${NC}"
    fi
else
    echo -e "${YELLOW}⚠ hello.py not found at $HELLO_PY${NC}"
fi
echo ""

# Step 9: Check final state
echo -e "${YELLOW}Step 9: Checking final state${NC}"
echo ""
echo "=== Tasks ==="
sqlite3 "$TEST_DB_PATH" "SELECT id, title, status FROM tasks WHERE project_id = 'pilot-hello';" 2>/dev/null || echo "(no tasks)"
echo ""
echo "=== Recent Contexts ==="
sqlite3 "$TEST_DB_PATH" "SELECT task_id, substr(content, 1, 60) || '...' FROM contexts ORDER BY created_at DESC LIMIT 5;" 2>/dev/null || echo "(no contexts)"
echo ""

# Result determination
if grep -qE "[0-9]+ passed" /tmp/pilot_hello_playwright.log && ! grep -qE "[0-9]+ failed" /tmp/pilot_hello_playwright.log; then
    TEST_PASSED=true
    echo -e "${GREEN}==========================================${NC}"
    echo -e "${GREEN}Pilot Test hello-world: PASSED${NC}"
    echo -e "${GREEN}==========================================${NC}"
    exit 0
else
    echo -e "${RED}==========================================${NC}"
    echo -e "${RED}Pilot Test hello-world: FAILED${NC}"
    echo -e "${RED}==========================================${NC}"
    echo ""
    echo "Logs preserved at:"
    echo "  - /tmp/pilot_hello_*.log"
    echo "  - /tmp/coordinator_logs_pilot_hello/"
    exit 1
fi
