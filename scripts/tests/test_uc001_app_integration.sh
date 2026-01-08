#!/bin/bash
# UC001 App Integration Test - True E2E Test with Coordinator
# アプリを含む真の統合テスト（Phase 4 Coordinator対応）
#
# フロー:
#   1. アプリビルド
#   2. MCPサーバービルド
#   3. Coordinator起動（ソケット待機）
#   4. XCUITest実行（アプリ起動→MCP自動起動→シードデータ投入→ステータス変更）
#   5. ファイル作成検証
#   6. 実行ログ検証（execution_logs テーブル）
#
# アーキテクチャ（Phase 4 Coordinator）:
#   - 単一のCoordinatorが全ての(agent_id, project_id)ペアを管理
#   - Coordinatorはagentごとのpasskeyを保持
#   - should_start(agent_id, project_id)で作業有無を確認
#   - 作業があればAgent Instance（Claude Code）をスポーン
#   - Agent Instanceがauthenticate → get_my_task → execute → report_completed

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
TEST_DIR="/tmp/uc001_test"
OUTPUT_FILE="test_output.md"

# 共有DB: XCUITestアプリが使用するパス
SHARED_DB_PATH="/tmp/AIAgentPM_UITest.db"

COORDINATOR_PID=""

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
    if [ "$1" != "--keep" ]; then
        rm -rf "$TEST_DIR"
        rm -f /tmp/uc001_coordinator.log
        rm -f /tmp/uc001_uitest.log
        rm -f /tmp/coordinator_uc001_config.yaml
        rm -rf /tmp/coordinator_logs_uc001
        rm -f "$SHARED_DB_PATH" "$SHARED_DB_PATH-shm" "$SHARED_DB_PATH-wal"
    fi
}

trap cleanup EXIT

echo "=========================================="
echo -e "${BLUE}UC001 App Integration Test${NC}"
echo -e "${BLUE}(Phase 4 Coordinator E2E)${NC}"
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
echo "  Agent: agt_uitest_runner (passkey: test_passkey_12345)"
echo ""

MCP_SERVER_COMMAND="$PROJECT_ROOT/.build/debug/mcp-server-pm"
cat > /tmp/coordinator_uc001_config.yaml << EOF
# Phase 4 Coordinator Configuration for UC001
polling_interval: 2
max_concurrent: 3

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
      - "20"

# Agents
agents:
  agt_uitest_runner:
    passkey: test_passkey_12345

log_directory: /tmp/coordinator_logs_uc001
EOF

mkdir -p /tmp/coordinator_logs_uc001

$PYTHON -m aiagent_runner --coordinator -c /tmp/coordinator_uc001_config.yaml -v > /tmp/uc001_coordinator.log 2>&1 &
COORDINATOR_PID=$!
echo "Coordinator started (PID: $COORDINATOR_PID)"
echo "Coordinator is waiting for MCP socket at: $SOCKET_PATH"

sleep 2
if ! kill -0 "$COORDINATOR_PID" 2>/dev/null; then
    echo -e "${RED}Coordinator failed to start${NC}"
    cat /tmp/uc001_coordinator.log
    exit 1
fi
echo -e "${GREEN}✓ Coordinator is running and waiting for MCP socket${NC}"
echo ""

# Step 6: XCUITest実行
echo -e "${YELLOW}Step 6: Running XCUITest (app + MCP + seed + status change)${NC}"
echo "  This will:"
echo "    1. Launch app with -UITesting -UITestScenario:UC001"
echo "    2. App auto-starts MCP daemon (Coordinator will connect)"
echo "    3. Seed test data via TestDataSeeder"
echo "    4. Change task status: backlog → todo → in_progress"
echo ""

cd "$PROJECT_ROOT"
xcodebuild test \
    -scheme AIAgentPM \
    -destination "platform=macOS" \
    -only-testing:AIAgentPMUITests/UC001_RunnerIntegrationTests/testRunnerIntegration_ChangeStatusToInProgress \
    2>&1 | tee /tmp/uc001_uitest.log | grep -E "(Test Case|passed|failed|✅|❌|error:)" || true

if grep -q "Test Suite 'UC001_RunnerIntegrationTests' passed" /tmp/uc001_uitest.log; then
    echo -e "${GREEN}✓ XCUITest passed - Task status changed to in_progress${NC}"
elif grep -q "passed" /tmp/uc001_uitest.log; then
    echo -e "${GREEN}✓ XCUITest passed${NC}"
else
    echo -e "${RED}✗ XCUITest failed${NC}"
    grep -E "(error:|failed|FAIL)" /tmp/uc001_uitest.log | tail -20
    echo ""
    echo "Coordinator log (last 30 lines):"
    tail -30 /tmp/uc001_coordinator.log 2>/dev/null || echo "(no log)"
    exit 1
fi
echo ""

# Step 7: ファイル作成待機
echo -e "${YELLOW}Step 7: Waiting for file creation (max 120s)${NC}"

FILE_CREATED=false

for i in $(seq 1 24); do
    if [ -f "$TEST_DIR/$OUTPUT_FILE" ]; then
        echo -e "${GREEN}✓ Output file created: $OUTPUT_FILE${NC}"
        FILE_CREATED=true
        break
    fi

    # Any md file
    MD_FILES=$(ls "$TEST_DIR"/*.md 2>/dev/null || true)
    if [ -n "$MD_FILES" ]; then
        echo -e "${GREEN}✓ Markdown file(s) created${NC}"
        echo "Files: $MD_FILES"
        FILE_CREATED=true
        break
    fi

    if [ $((i % 6)) -eq 0 ]; then
        echo "  Waiting... ($((i * 5))s)"
        if ! kill -0 "$COORDINATOR_PID" 2>/dev/null; then
            echo -e "${YELLOW}Coordinator process ended${NC}"
            break
        fi
    fi

    sleep 5
done
echo ""

# Step 8: DB状態確認
echo -e "${YELLOW}Step 8: Verifying DB and execution logs${NC}"

# Use the shared DB path directly (Coordinator uses this path)
ACTUAL_DB_PATH="$SHARED_DB_PATH"
if [ ! -f "$ACTUAL_DB_PATH" ]; then
    echo -e "${RED}UITest DB not found at $ACTUAL_DB_PATH${NC}"
    exit 1
fi
echo "DB: $ACTUAL_DB_PATH"
echo ""

# Check execution_logs table
echo "=== Execution Logs in DB ==="
EXEC_LOG_COUNT=$(sqlite3 "$ACTUAL_DB_PATH" "SELECT COUNT(*) FROM execution_logs;" 2>/dev/null || echo "0")
echo "Execution log records: $EXEC_LOG_COUNT"

if [ "$EXEC_LOG_COUNT" -gt "0" ]; then
    echo -e "${GREEN}✓ Execution logs created${NC}"
    sqlite3 "$ACTUAL_DB_PATH" "SELECT id, task_id, agent_id, status, log_file_path FROM execution_logs;" 2>/dev/null
else
    echo -e "${RED}✗ No execution logs found${NC}"
fi
echo ""

# Check tasks status
echo "=== Tasks in DB ==="
sqlite3 "$ACTUAL_DB_PATH" "SELECT id, title, status, assignee_id FROM tasks;" 2>/dev/null || echo "(query error)"
echo ""

# Check sub-tasks (tasks with parent_task_id)
echo "=== Sub-tasks in DB ==="
SUBTASK_COUNT=$(sqlite3 "$ACTUAL_DB_PATH" "SELECT COUNT(*) FROM tasks WHERE parent_task_id IS NOT NULL;" 2>/dev/null || echo "0")
echo "Sub-task records: $SUBTASK_COUNT"

if [ "$SUBTASK_COUNT" -gt "0" ]; then
    echo -e "${GREEN}✓ Sub-tasks created${NC}"
    sqlite3 "$ACTUAL_DB_PATH" "SELECT id, title, status, parent_task_id FROM tasks WHERE parent_task_id IS NOT NULL;" 2>/dev/null
else
    echo -e "${YELLOW}No sub-tasks found (Agent may have executed directly)${NC}"
fi
echo ""

# Step 9: Coordinator ログ表示
echo -e "${YELLOW}Step 9: Coordinator log (last 30 lines)${NC}"
tail -30 /tmp/uc001_coordinator.log 2>/dev/null || echo "(no log)"
echo ""

# Step 10: 結果検証
echo "=========================================="

OUTPUT_FILES=$(ls "$TEST_DIR"/*.md 2>/dev/null || true)
if [ -n "$OUTPUT_FILES" ]; then
    FILE_CREATED=true
    for f in $OUTPUT_FILES; do
        echo "Found: $f"
        CHAR_COUNT=$(cat "$f" | wc -c | tr -d ' ')
        echo "  Characters: $CHAR_COUNT"
    done
fi

# 結果判定
if [ "$FILE_CREATED" == "true" ] && [ "$EXEC_LOG_COUNT" -gt "0" ]; then
    echo -e "${GREEN}UC001 App Integration Test: PASSED${NC}"
    echo ""
    echo "Verified (Phase 4 Coordinator Architecture):"
    echo "  ✓ App launched with UITest scenario"
    echo "  ✓ Test data seeded (agent, project, task, assignment)"
    echo "  ✓ Task status changed via UI"
    echo "  ✓ Coordinator detected in_progress task"
    echo "  ✓ Agent Instance spawned and executed"
    echo "  ✓ File created in working directory"
    echo "  ✓ Execution log recorded in DB ($EXEC_LOG_COUNT records)"
    if [ "$SUBTASK_COUNT" -gt "0" ]; then
        echo "  ✓ Sub-tasks created ($SUBTASK_COUNT records)"
    fi
    exit 0
elif [ "$FILE_CREATED" == "true" ]; then
    echo -e "${YELLOW}UC001 App Integration Test: PARTIAL${NC}"
    echo ""
    echo "File created but execution logs missing."
    echo "This indicates get_my_task/report_completed not creating logs."
    exit 1
else
    echo -e "${RED}UC001 App Integration Test: FAILED${NC}"
    echo ""
    echo "Debug info:"
    echo "  - XCUITest log: /tmp/uc001_uitest.log"
    echo "  - Coordinator log: /tmp/uc001_coordinator.log"
    echo "  - Coordinator logs dir: /tmp/coordinator_logs_uc001/"
    echo "  - Shared DB: $ACTUAL_DB_PATH"
    exit 1
fi
