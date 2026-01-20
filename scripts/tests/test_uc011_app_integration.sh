#!/bin/bash
# UC011 App Integration Test - Project Pause/Resume with Runner
# プロジェクト一時停止/再開と Coordinator 統合テスト
#
# フロー:
#   1. アプリビルド
#   2. MCPサーバービルド
#   3. Coordinator起動
#   4. XCUITest実行（アプリ起動→シードデータ投入→ステータス変更→一時停止→再開）
#   5. ファイル作成検証
#   6. 実行ログ検証
#
# 検証内容:
#   - プロジェクト一時停止時にエージェントが停止する
#   - プロジェクト再開後にエージェントが実行を再開する
#   - タスクが最終的に完了する

set -e

# 色付き出力
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# プロジェクトルート
PROJECT_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

# テスト設定
TEST_DIR="/tmp/uc011_test"
COMPLETE_FILE="complete.md"  # 完了マーカーファイル

# Phase 5: Coordinator token for authorization
export MCP_COORDINATOR_TOKEN="test_coordinator_token_uc001"

# 共有DB: XCUITestアプリが使用するパス
SHARED_DB_PATH="/tmp/AIAgentPM_UITest.db"

COORDINATOR_PID=""
TEST_PASSED=false

# クリーンアップ関数
cleanup() {
    echo ""
    echo -e "${YELLOW}Cleanup${NC}"
    # Coordinator停止
    if [ -n "$COORDINATOR_PID" ] && kill -0 "$COORDINATOR_PID" 2>/dev/null; then
        kill "$COORDINATOR_PID" 2>/dev/null || true
        echo "Coordinator stopped"
    fi
    # テスト失敗時はログを保持
    if [ "$TEST_PASSED" == "true" ] && [ "$1" != "--keep" ]; then
        rm -rf "$TEST_DIR"
        rm -f /tmp/uc011_coordinator.log
        rm -f /tmp/uc011_uitest.log
        rm -f /tmp/coordinator_uc011_config.yaml
        rm -rf /tmp/coordinator_logs_uc011
        rm -f "$SHARED_DB_PATH" "$SHARED_DB_PATH-shm" "$SHARED_DB_PATH-wal"
    else
        echo "Logs preserved for debugging:"
        echo "  - Coordinator: /tmp/uc011_coordinator.log"
        echo "  - Agent logs: /tmp/coordinator_logs_uc011/"
    fi
}

trap cleanup EXIT

echo "=========================================="
echo -e "${BLUE}UC011 App Integration Test${NC}"
echo -e "${BLUE}(Project Pause/Resume with Runner)${NC}"
echo "=========================================="
echo ""

# Step 1: テスト環境準備
echo -e "${YELLOW}Step 1: Preparing test environment${NC}"

# Kill stale MCP daemon processes
echo "Killing any stale MCP daemon processes..."
ps aux | grep "mcp-server-pm" | grep -v grep | awk '{print $2}' | xargs -I {} kill -9 {} 2>/dev/null || true
sleep 1

rm -rf "$TEST_DIR"
mkdir -p "$TEST_DIR"
rm -f "$SHARED_DB_PATH" "$SHARED_DB_PATH-shm" "$SHARED_DB_PATH-wal"
rm -f "$HOME/Library/Application Support/AIAgentPM/mcp.sock" 2>/dev/null
rm -f "$HOME/Library/Application Support/AIAgentPM/daemon.pid" 2>/dev/null
echo "Test directory: $TEST_DIR"
echo "Shared DB: $SHARED_DB_PATH"
echo ""

# Step 2: アプリビルド
echo -e "${YELLOW}Step 2: Building app${NC}"
cd "$PROJECT_ROOT"
xcodebuild -scheme AIAgentPM -destination "platform=macOS" -configuration Debug build 2>&1 | tail -5 || {
    echo -e "${RED}Failed to build app${NC}"
    exit 1
}
echo "App build complete"
echo ""

# Step 3: MCPサーバービルド
echo -e "${YELLOW}Step 3: Building MCP server${NC}"
cd "$PROJECT_ROOT"
xcodebuild -scheme MCPServer -destination 'platform=macOS' build 2>&1 | tail -3 || {
    echo -e "${RED}Failed to build MCP server${NC}"
    exit 1
}
echo "MCP server build complete"
SOCKET_PATH="$HOME/Library/Application Support/AIAgentPM/mcp.sock"
echo ""

# Step 4: Runnerの確認
echo -e "${YELLOW}Step 4: Checking Runner setup${NC}"
RUNNER_DIR="$PROJECT_ROOT/runner"
if [ -d "$RUNNER_DIR/.venv" ]; then
    PYTHON="$RUNNER_DIR/.venv/bin/python"
else
    PYTHON="python3"
fi

if ! $PYTHON -c "import aiagent_runner" 2>/dev/null; then
    echo "Installing Runner..."
    cd "$RUNNER_DIR"
    pip install -e . -q
    cd "$PROJECT_ROOT"
fi
echo "Runner is ready"
echo ""

# Step 5: Coordinator起動
echo -e "${YELLOW}Step 5: Starting Coordinator${NC}"
echo "  Agent: agt_uc011_dev (passkey: test_passkey_uc011)"
echo ""

MCP_SERVER_COMMAND="$PROJECT_ROOT/.build/debug/mcp-server-pm"
cat > /tmp/coordinator_uc011_config.yaml << EOF
# Coordinator Configuration for UC011
polling_interval: 2
max_concurrent: 3

# Coordinator token for authorization
coordinator_token: ${MCP_COORDINATOR_TOKEN}

# MCP server configuration
mcp_server_command: $MCP_SERVER_COMMAND
mcp_database_path: $SHARED_DB_PATH

# AI providers
ai_providers:
  claude:
    cli_command: claude
    cli_args:
      - "--dangerously-skip-permissions"
      - "--max-turns"
      - "50"

# Agents
agents:
  agt_uc011_dev:
    passkey: test_passkey_uc011

log_directory: /tmp/coordinator_logs_uc011
EOF

mkdir -p /tmp/coordinator_logs_uc011

$PYTHON -m aiagent_runner --coordinator -c /tmp/coordinator_uc011_config.yaml -v > /tmp/uc011_coordinator.log 2>&1 &
COORDINATOR_PID=$!
echo "Coordinator started (PID: $COORDINATOR_PID)"
echo "Coordinator is waiting for MCP socket at: $SOCKET_PATH"

sleep 2
if ! kill -0 "$COORDINATOR_PID" 2>/dev/null; then
    echo -e "${RED}Coordinator failed to start${NC}"
    cat /tmp/uc011_coordinator.log
    exit 1
fi
echo -e "${GREEN}✓ Coordinator is running${NC}"
echo ""

# Step 6: XCUITest実行
echo -e "${YELLOW}Step 6: Running XCUITest${NC}"
echo "  This will:"
echo "    1. Launch app with -UITesting -UITestScenario:UC011"
echo "    2. Seed test data (段階的ファイル作成タスク)"
echo "    3. Change task status to in_progress"
echo "    4. Wait for step1.md creation (confirms agent running)"
echo "    5. Pause project"
echo "    6. Wait 30s, verify complete.md NOT created (confirms agent stopped)"
echo "    7. Resume project"
echo "    8. Wait for complete.md creation (confirms task completed)"
echo ""

cd "$PROJECT_ROOT"
xcodebuild test \
    -scheme AIAgentPM \
    -destination "platform=macOS" \
    -only-testing:AIAgentPMUITests/UC011_ProjectPauseIntegrationTests/testPauseResumeIntegration_RunningAgentStopsAndResumes \
    2>&1 | tee /tmp/uc011_uitest.log | grep -E "(Test Case|passed|failed|✅|❌|error:|Phase)" || true

if grep -q "Test Suite 'UC011_ProjectPauseIntegrationTests' passed" /tmp/uc011_uitest.log; then
    echo -e "${GREEN}✓ XCUITest passed - Pause/Resume integration verified${NC}"
elif grep -q "passed" /tmp/uc011_uitest.log; then
    echo -e "${GREEN}✓ XCUITest passed${NC}"
else
    echo -e "${RED}✗ XCUITest failed${NC}"
    grep -E "(error:|failed|FAIL|❌)" /tmp/uc011_uitest.log | tail -20
    echo ""
    echo "Coordinator log (last 30 lines):"
    tail -30 /tmp/uc011_coordinator.log 2>/dev/null || echo "(no log)"
    exit 1
fi
echo ""

# Step 7: ファイル作成確認
echo -e "${YELLOW}Step 7: Verifying file creation${NC}"

if [ -f "$TEST_DIR/complete.md" ]; then
    echo -e "${GREEN}✓ complete.md created (task completed)${NC}"
    echo "Content preview:"
    head -10 "$TEST_DIR/complete.md"
else
    echo -e "${RED}✗ complete.md not found${NC}"
fi

# List all step files
echo ""
echo "Step files in $TEST_DIR:"
ls -la "$TEST_DIR"/*.md 2>/dev/null || echo "(no md files)"
echo ""

# Step 8: DB状態確認
echo -e "${YELLOW}Step 8: Verifying DB state${NC}"

ACTUAL_DB_PATH="$SHARED_DB_PATH"
if [ ! -f "$ACTUAL_DB_PATH" ]; then
    echo -e "${RED}UITest DB not found at $ACTUAL_DB_PATH${NC}"
    exit 1
fi
echo "DB: $ACTUAL_DB_PATH"
echo ""

# Check project status
echo "=== Projects in DB ==="
sqlite3 "$ACTUAL_DB_PATH" "SELECT id, name, status FROM projects;" 2>/dev/null || echo "(query error)"
echo ""

# Check tasks status
echo "=== Tasks in DB ==="
sqlite3 "$ACTUAL_DB_PATH" "SELECT id, title, status, assignee_id FROM tasks;" 2>/dev/null || echo "(query error)"
echo ""

# Check execution_logs
echo "=== Execution Logs ==="
EXEC_LOG_COUNT=$(sqlite3 "$ACTUAL_DB_PATH" "SELECT COUNT(*) FROM execution_logs;" 2>/dev/null || echo "0")
echo "Execution log records: $EXEC_LOG_COUNT"

if [ "$EXEC_LOG_COUNT" -gt "0" ]; then
    echo -e "${GREEN}✓ Execution logs created${NC}"
    sqlite3 "$ACTUAL_DB_PATH" "SELECT id, task_id, agent_id, status FROM execution_logs;" 2>/dev/null
else
    echo -e "${YELLOW}⚠ No execution logs found${NC}"
fi
echo ""

# Step 9: 結果判定
echo "=========================================="
echo -e "${BLUE}Test Results${NC}"
echo "=========================================="

UITEST_PASSED=false
if grep -q "passed" /tmp/uc011_uitest.log; then
    UITEST_PASSED=true
fi

if [ "$UITEST_PASSED" == "true" ]; then
    echo -e "${GREEN}✓ UC011 Integration Test PASSED${NC}"
    echo "  - Project pause/resume verified via UI"
    echo "  - Agent state transitions observed"
    TEST_PASSED=true
else
    echo -e "${RED}✗ UC011 Integration Test FAILED${NC}"
    exit 1
fi
echo ""
