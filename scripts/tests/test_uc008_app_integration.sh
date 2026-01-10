#!/bin/bash
# UC008 App Integration Test - Task Blocking E2E Test
# タスクブロックによる作業中断テスト
#
# フロー:
#   1. アプリビルド
#   2. MCPサーバービルド
#   3. Coordinator起動（ソケット待機）
#   4. XCUITest実行（アプリ起動→MCP自動起動→シードデータ投入→ステータス変更→ブロック）
#   5. サブタスクのカスケードブロック検証
#   6. エージェント停止検証（get_agent_actionがstopを返す）
#
# アーキテクチャ（Phase 4 Coordinator）:
#   - 単一のCoordinatorが全ての(agent_id, project_id)ペアを管理
#   - Coordinatorはagentごとのpasskeyを保持
#   - get_agent_action(agent_id, project_id)で作業有無を確認
#   - 作業があればAgent Instance（Claude Code）をスポーン
#   - ブロック時はget_agent_actionがaction: "stop"を返す

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
TEST_DIR="/tmp/uc008"
OUTPUT_FILE="README.md"

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
    # Note: MCP Daemon is managed by the app (terminates when app terminates)
    # テスト失敗時はログを保持してデバッグを容易にする
    if [ "$TEST_PASSED" == "true" ] && [ "$1" != "--keep" ]; then
        rm -rf "$TEST_DIR"
        rm -f /tmp/uc008_coordinator.log
        rm -f /tmp/uc008_uitest.log
        rm -f /tmp/coordinator_uc008_config.yaml
        rm -rf /tmp/coordinator_logs_uc008
        rm -f "$SHARED_DB_PATH" "$SHARED_DB_PATH-shm" "$SHARED_DB_PATH-wal"
    else
        echo "Logs preserved for debugging:"
        echo "  - Coordinator: /tmp/uc008_coordinator.log"
        echo "  - Agent logs: /tmp/coordinator_logs_uc008/"
    fi
}

trap cleanup EXIT

echo "=========================================="
echo -e "${BLUE}UC008 App Integration Test${NC}"
echo -e "${BLUE}(Task Blocking E2E)${NC}"
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
swift build --product mcp-server-pm 2>&1 | tail -3 || {
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

# Step 5: Coordinator起動（ソケット待機）
echo -e "${YELLOW}Step 5: Starting Coordinator (waits for MCP socket)${NC}"
echo "  Architecture: Phase 4 Coordinator"
echo "  - Coordinator starts FIRST and waits for MCP socket"
echo "  - App will start daemon, Coordinator will connect"
echo "  Agent: agt_uc008_worker (passkey: test_passkey_uc008_worker)"
echo ""

MCP_SERVER_COMMAND="$PROJECT_ROOT/.build/debug/mcp-server-pm"
cat > /tmp/coordinator_uc008_config.yaml << EOF
# Phase 4/5 Coordinator Configuration for UC008
polling_interval: 2
max_concurrent: 3

# Phase 5: Coordinator token for authorization
coordinator_token: ${MCP_COORDINATOR_TOKEN}

# MCP server configuration (for Agent Instances via stdio transport)
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
  agt_uc008_worker:
    passkey: test_passkey_uc008_worker

log_directory: /tmp/coordinator_logs_uc008
EOF

mkdir -p /tmp/coordinator_logs_uc008

$PYTHON -m aiagent_runner --coordinator -c /tmp/coordinator_uc008_config.yaml -v > /tmp/uc008_coordinator.log 2>&1 &
COORDINATOR_PID=$!
echo "Coordinator started (PID: $COORDINATOR_PID)"
echo "Coordinator is waiting for MCP socket at: $SOCKET_PATH"

sleep 2
if ! kill -0 "$COORDINATOR_PID" 2>/dev/null; then
    echo -e "${RED}Coordinator failed to start${NC}"
    cat /tmp/uc008_coordinator.log
    exit 1
fi
echo -e "${GREEN}✓ Coordinator is running and waiting for MCP socket${NC}"
echo ""

# Step 6: XCUITest実行
echo -e "${YELLOW}Step 6: Running XCUITest (app + MCP + seed + blocking test)${NC}"
echo "  This will:"
echo "    1. Launch app with -UITesting -UITestScenario:UC008"
echo "    2. App auto-starts MCP daemon (Coordinator will connect)"
echo "    3. Seed test data via TestDataSeeder"
echo "    4. Change task status: backlog → todo → in_progress"
echo "    5. Wait for subtasks to be created"
echo "    6. Change task status: in_progress → blocked"
echo "    7. Verify subtasks cascade to blocked"
echo ""

cd "$PROJECT_ROOT"
xcodebuild test \
    -scheme AIAgentPM \
    -destination "platform=macOS" \
    -only-testing:AIAgentPMUITests/UC008_TaskBlockingTests/testTaskBlocking_BlockParentAndVerifyCascade \
    2>&1 | tee /tmp/uc008_uitest.log | grep -E "(Test Case|passed|failed|✅|❌|error:)" || true

if grep -q "Test Suite 'UC008_TaskBlockingTests' passed" /tmp/uc008_uitest.log; then
    echo -e "${GREEN}✓ XCUITest passed - Task blocking and cascade verified${NC}"
elif grep -q "passed" /tmp/uc008_uitest.log; then
    echo -e "${GREEN}✓ XCUITest passed${NC}"
else
    echo -e "${RED}✗ XCUITest failed${NC}"
    grep -E "(error:|failed|FAIL)" /tmp/uc008_uitest.log | tail -20
    echo ""
    echo "Coordinator log (last 30 lines):"
    tail -30 /tmp/uc008_coordinator.log 2>/dev/null || echo "(no log)"
    exit 1
fi
echo ""

# Step 7: DB状態確認
echo -e "${YELLOW}Step 7: Verifying DB state${NC}"

# Use the shared DB path directly (Coordinator uses this path)
ACTUAL_DB_PATH="$SHARED_DB_PATH"
if [ ! -f "$ACTUAL_DB_PATH" ]; then
    echo -e "${RED}UITest DB not found at $ACTUAL_DB_PATH${NC}"
    exit 1
fi
echo "DB: $ACTUAL_DB_PATH"
echo ""

# Check tasks status - specifically looking for blocked tasks
echo "=== Tasks in DB ==="
sqlite3 "$ACTUAL_DB_PATH" "SELECT id, title, status, parent_task_id FROM tasks;" 2>/dev/null || echo "(query error)"
echo ""

# Check blocked tasks count
BLOCKED_COUNT=$(sqlite3 "$ACTUAL_DB_PATH" "SELECT COUNT(*) FROM tasks WHERE status = 'blocked';" 2>/dev/null || echo "0")
echo "Blocked task count: $BLOCKED_COUNT"

# Check sub-tasks (tasks with parent_task_id)
echo "=== Sub-tasks in DB ==="
SUBTASK_COUNT=$(sqlite3 "$ACTUAL_DB_PATH" "SELECT COUNT(*) FROM tasks WHERE parent_task_id IS NOT NULL;" 2>/dev/null || echo "0")
echo "Sub-task records: $SUBTASK_COUNT"

if [ "$SUBTASK_COUNT" -gt "0" ]; then
    echo -e "${GREEN}✓ Sub-tasks created${NC}"
    sqlite3 "$ACTUAL_DB_PATH" "SELECT id, title, status, parent_task_id FROM tasks WHERE parent_task_id IS NOT NULL;" 2>/dev/null

    # Check if all subtasks are blocked
    BLOCKED_SUBTASK_COUNT=$(sqlite3 "$ACTUAL_DB_PATH" "SELECT COUNT(*) FROM tasks WHERE parent_task_id IS NOT NULL AND status = 'blocked';" 2>/dev/null || echo "0")
    echo ""
    echo "Blocked sub-tasks: $BLOCKED_SUBTASK_COUNT / $SUBTASK_COUNT"

    if [ "$BLOCKED_SUBTASK_COUNT" == "$SUBTASK_COUNT" ]; then
        echo -e "${GREEN}✓ All sub-tasks cascaded to blocked${NC}"
    else
        echo -e "${YELLOW}⚠ Not all sub-tasks are blocked${NC}"
    fi
else
    echo -e "${YELLOW}No sub-tasks found (Agent may not have created them yet)${NC}"
fi
echo ""

# Check execution logs
echo "=== Execution Logs in DB ==="
EXEC_LOG_COUNT=$(sqlite3 "$ACTUAL_DB_PATH" "SELECT COUNT(*) FROM execution_logs;" 2>/dev/null || echo "0")
echo "Execution log records: $EXEC_LOG_COUNT"

if [ "$EXEC_LOG_COUNT" -gt "0" ]; then
    echo -e "${GREEN}✓ Execution logs created${NC}"
    sqlite3 "$ACTUAL_DB_PATH" "SELECT id, task_id, agent_id, status FROM execution_logs;" 2>/dev/null
else
    echo -e "${YELLOW}⚠ No execution logs found${NC}"
fi
echo ""

# Step 8: Coordinator ログ表示
echo -e "${YELLOW}Step 8: Coordinator log (last 30 lines)${NC}"
tail -30 /tmp/uc008_coordinator.log 2>/dev/null || echo "(no log)"
echo ""

# Check for "stop" action in coordinator log
if grep -q '"action".*"stop"' /tmp/uc008_coordinator.log 2>/dev/null; then
    echo -e "${GREEN}✓ Agent received stop action${NC}"
    STOP_RECEIVED=true
elif grep -q "task_blocked" /tmp/uc008_coordinator.log 2>/dev/null; then
    echo -e "${GREEN}✓ Task blocked detected in logs${NC}"
    STOP_RECEIVED=true
else
    echo -e "${YELLOW}⚠ Stop action not found in logs (may still be correct)${NC}"
    STOP_RECEIVED=false
fi
echo ""

# Step 9: 結果検証
echo "=========================================="

# 結果判定
# 必須条件: サブタスク作成、サブタスクのblocked化
if [ "$SUBTASK_COUNT" -gt "0" ] && [ "$BLOCKED_SUBTASK_COUNT" == "$SUBTASK_COUNT" ]; then
    TEST_PASSED=true
    echo -e "${GREEN}UC008 App Integration Test: PASSED${NC}"
    echo ""
    echo "Verified (Phase 4 Coordinator Architecture):"
    echo "  ✓ App launched with UITest scenario"
    echo "  ✓ Test data seeded (agent, project, task)"
    echo "  ✓ Task status changed to in_progress via UI"
    echo "  ✓ Coordinator detected in_progress task"
    echo "  ✓ Agent Instance spawned and created sub-tasks ($SUBTASK_COUNT records)"
    echo "  ✓ Task status changed to blocked via UI"
    echo "  ✓ Sub-tasks cascaded to blocked ($BLOCKED_SUBTASK_COUNT/$SUBTASK_COUNT)"
    if [ "$STOP_RECEIVED" == "true" ]; then
        echo "  ✓ Agent received stop action"
    fi
    exit 0
elif [ "$SUBTASK_COUNT" -gt "0" ]; then
    echo -e "${YELLOW}UC008 App Integration Test: PARTIAL${NC}"
    echo ""
    echo "Sub-tasks created but not all cascaded to blocked."
    echo "  - Sub-tasks: $SUBTASK_COUNT"
    echo "  - Blocked: $BLOCKED_SUBTASK_COUNT"
    echo ""
    echo "Debug info:"
    echo "  - Coordinator log: /tmp/uc008_coordinator.log"
    echo "  - Agent logs: /tmp/coordinator_logs_uc008/"
    exit 1
else
    echo -e "${RED}UC008 App Integration Test: FAILED${NC}"
    echo ""
    echo "No sub-tasks were created."
    echo ""
    echo "Debug info:"
    echo "  - XCUITest log: /tmp/uc008_uitest.log"
    echo "  - Coordinator log: /tmp/uc008_coordinator.log"
    echo "  - Coordinator logs dir: /tmp/coordinator_logs_uc008/"
    echo "  - Shared DB: $ACTUAL_DB_PATH"
    exit 1
fi
