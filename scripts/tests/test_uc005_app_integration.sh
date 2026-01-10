#!/bin/bash
# UC005 App Integration Test - Manager → Worker Delegation E2E Test
# マネージャー→ワーカー委任テスト
#
# 設計: 1プロジェクト + 2エージェント（マネージャー、ワーカー）+ 1親タスク
# - マネージャーがサブタスクを作成してワーカーに委任
# - ワーカーがサブサブタスクを作成して実行
# - 全タスクがdoneになることを検証
#
# フロー:
#   1. テスト環境準備
#   2. アプリビルド
#   3. MCPサーバービルド
#   4. Runner確認
#   5. Coordinator起動（ソケット待機状態で起動）
#   6. XCUITest実行（アプリ起動→MCP自動起動→シードデータ→ステータス変更→完了待機）
#   7. 結果検証（タスク階層、成果物）

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
WORKING_DIR="/tmp/uc005"
OUTPUT_FILE="README.md"

# 共有DB: XCUITestアプリが使用するパス
SHARED_DB_PATH="/tmp/AIAgentPM_UITest.db"

# Phase 5: Coordinator token for authorization
export MCP_COORDINATOR_TOKEN="test_coordinator_token_uc001"

COORDINATOR_PID=""
TEST_FAILED=false

# クリーンアップ関数
cleanup() {
    echo ""
    echo -e "${YELLOW}Cleanup${NC}"
    # Coordinator停止
    if [ -n "$COORDINATOR_PID" ] && kill -0 "$COORDINATOR_PID" 2>/dev/null; then
        kill "$COORDINATOR_PID" 2>/dev/null || true
        echo "Coordinator stopped"
    fi
    # --keep オプションまたはテスト失敗時はログを保持
    if [ "$1" != "--keep" ] && [ "$TEST_FAILED" != "true" ]; then
        rm -rf "$WORKING_DIR"
        rm -f /tmp/uc005_coordinator.log
        rm -f /tmp/uc005_uitest.log
        rm -f /tmp/coordinator_uc005_config.yaml
        rm -rf /tmp/coordinator_logs_uc005
        rm -f "$SHARED_DB_PATH" "$SHARED_DB_PATH-shm" "$SHARED_DB_PATH-wal"
    fi
}

trap 'if [ $? -ne 0 ]; then TEST_FAILED=true; fi; cleanup' EXIT

echo "=========================================="
echo -e "${BLUE}UC005 App Integration Test${NC}"
echo -e "${BLUE}(Manager → Worker Delegation E2E)${NC}"
echo "=========================================="
echo ""

# Step 1: テスト環境準備
echo -e "${YELLOW}Step 1: Preparing test environment${NC}"

# CRITICAL: Kill ALL stale MCP daemon processes from previous runs
echo "Killing any stale MCP daemon processes..."
ps aux | grep "mcp-server-pm" | grep -v grep | awk '{print $2}' | xargs -I {} kill -9 {} 2>/dev/null || true
sleep 1

rm -rf "$WORKING_DIR"
mkdir -p "$WORKING_DIR"
rm -f "$SHARED_DB_PATH" "$SHARED_DB_PATH-shm" "$SHARED_DB_PATH-wal"
rm -f "$HOME/Library/Application Support/AIAgentPM/mcp.sock" 2>/dev/null
rm -f "$HOME/Library/Application Support/AIAgentPM/daemon.pid" 2>/dev/null
echo "Test directory: $WORKING_DIR"
echo "Expected output: $WORKING_DIR/$OUTPUT_FILE"
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
echo "Note: MCP Daemon will be started by the app"
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
echo -e "${YELLOW}Step 5: Starting Coordinator (waits for MCP socket)${NC}"
echo "  Architecture: Phase 4 Coordinator with Manager → Worker delegation"
echo "  - Coordinator starts FIRST and waits for MCP socket"
echo "  - App will start daemon, Coordinator will connect"
echo "  - Main task in_progress → Manager starts"
echo "  - Manager creates subtask → assigns to Worker"
echo "  - Manager sets subtask to in_progress → Worker starts"
echo "  - Worker creates sub-subtasks, executes, completes"
echo "  - Manager confirms and completes main task"
echo "  Agents:"
echo "    - agt_uc005_manager (Manager)"
echo "    - agt_uc005_worker (Worker)"
echo ""

# Coordinator設定
cat > /tmp/coordinator_uc005_config.yaml << EOF
# Phase 4/5 Coordinator Configuration
polling_interval: 2
max_concurrent: 3

# Phase 5: Coordinator token for authorization
coordinator_token: ${MCP_COORDINATOR_TOKEN}

# MCP socket path (Coordinator and Agent Instances connect to the SAME daemon)
mcp_socket_path: $HOME/Library/Application Support/AIAgentPM/mcp.sock

# AI providers - how to launch each AI type
ai_providers:
  claude:
    cli_command: claude
    cli_args:
      - "--dangerously-skip-permissions"
      - "--max-turns"
      - "50"

# Agents - only passkey is needed (ai_type, system_prompt come from MCP)
agents:
  agt_uc005_manager:
    passkey: test_passkey_uc005_manager
  agt_uc005_worker:
    passkey: test_passkey_uc005_worker

log_directory: /tmp/coordinator_logs_uc005
EOF

mkdir -p /tmp/coordinator_logs_uc005

# Coordinator起動
$PYTHON -m aiagent_runner --coordinator -c /tmp/coordinator_uc005_config.yaml -v > /tmp/uc005_coordinator.log 2>&1 &
COORDINATOR_PID=$!
echo "Coordinator started (PID: $COORDINATOR_PID)"
echo "Coordinator is waiting for MCP socket at: $HOME/Library/Application Support/AIAgentPM/mcp.sock"

sleep 2
if ! kill -0 "$COORDINATOR_PID" 2>/dev/null; then
    echo -e "${RED}Coordinator failed to start${NC}"
    cat /tmp/uc005_coordinator.log
    exit 1
fi
echo -e "${GREEN}✓ Coordinator is running and waiting for MCP socket${NC}"
echo ""

# Step 6: XCUITest実行
echo -e "${YELLOW}Step 6: Running XCUITest (app + MCP auto-start + seed data + wait for completion)${NC}"
echo "  This will:"
echo "    1. Launch app with -UITesting -UITestScenario:UC005"
echo "    2. App auto-starts MCP daemon (Coordinator will connect)"
echo "    3. Seed test data (Manager, Worker, 1 main task)"
echo "    4. Change main task status: backlog → todo → in_progress via UI"
echo "    5. Wait for Manager → Worker delegation → completion (max 240s)"
echo ""

cd "$PROJECT_ROOT"
xcodebuild test \
    -scheme AIAgentPM \
    -destination "platform=macOS" \
    -only-testing:AIAgentPMUITests/UC005_ManagerWorkerDelegationTests/testManagerWorkerDelegation_ChangeMainTaskToInProgress \
    2>&1 | tee /tmp/uc005_uitest.log | grep -E "(Test Case|passed|failed|✅|❌|error:)" || true

# テスト結果確認
if grep -q "Test Suite 'UC005_ManagerWorkerDelegationTests' passed" /tmp/uc005_uitest.log; then
    echo -e "${GREEN}✓ XCUITest passed - Manager→Worker delegation completed${NC}"
elif grep -q "passed" /tmp/uc005_uitest.log; then
    echo -e "${GREEN}✓ XCUITest passed${NC}"
else
    echo -e "${RED}✗ XCUITest failed${NC}"
    grep -E "(error:|failed|FAIL)" /tmp/uc005_uitest.log | tail -20
    echo ""
    echo "Coordinator log (last 30 lines):"
    tail -30 /tmp/uc005_coordinator.log 2>/dev/null || echo "(no log)"
    TEST_FAILED=true
    exit 1
fi
echo ""

# Step 7: 結果検証
echo -e "${YELLOW}Step 7: Verifying outputs${NC}"

# ファイル存在確認
if [ -f "$WORKING_DIR/$OUTPUT_FILE" ]; then
    CONTENT=$(cat "$WORKING_DIR/$OUTPUT_FILE")
    CHARS=$(echo "$CONTENT" | wc -c | tr -d ' ')
    echo "$OUTPUT_FILE: $CHARS characters"
    echo -e "${GREEN}✓ $OUTPUT_FILE created by Worker${NC}"
else
    echo -e "${RED}✗ $OUTPUT_FILE not found${NC}"
fi
echo ""

# Step 7.5: タスク階層の検証（仕様書の7項目に基づく）
echo -e "${YELLOW}Step 7.5: Verifying task hierarchy (UC005 spec: 7 assertions)${NC}"

# 検証結果フラグ（仕様書の7項目）
V1_SUBTASK_CREATED=false      # 1. マネージャーがサブタスクを作成したこと
V2_SUBTASK_TO_WORKER=false    # 2. サブタスクがワーカーに割り当てられていること
V3_SUBSUBTASK_CREATED=false   # 3. ワーカーがサブサブタスクを作成したこと
V4_SUBSUBTASK_TO_WORKER=false # 4. サブサブタスクがワーカー自身に割り当てられていること
V5_ALL_SUBSUBTASK_DONE=false  # 5. 全てのサブサブタスクがdoneになっていること
V6_ALL_SUBTASK_DONE=false     # 6. 全てのサブタスクがdoneになっていること
V7_MAIN_TASK_DONE=false       # 7. 親タスクがdoneになっていること

if [ -f "$SHARED_DB_PATH" ]; then
    # 7. 親タスクのステータス
    MAIN_TASK_STATUS=$(sqlite3 "$SHARED_DB_PATH" "SELECT status FROM tasks WHERE id = 'tsk_uc005_main';" 2>/dev/null || echo "")
    echo "Main task (tsk_uc005_main) status: $MAIN_TASK_STATUS"
    if [ "$MAIN_TASK_STATUS" = "done" ]; then
        V7_MAIN_TASK_DONE=true
        echo -e "${GREEN}  ✓ [7] Main task is done${NC}"
    else
        echo -e "${RED}  ✗ [7] Main task is NOT done (status: $MAIN_TASK_STATUS)${NC}"
    fi

    # 1. サブタスク（マネージャーが作成）
    SUBTASK_COUNT=$(sqlite3 "$SHARED_DB_PATH" "SELECT COUNT(*) FROM tasks WHERE parent_task_id = 'tsk_uc005_main';" 2>/dev/null || echo "0")
    echo "Subtasks (created by Manager): $SUBTASK_COUNT"
    if [ "$SUBTASK_COUNT" -gt "0" ]; then
        V1_SUBTASK_CREATED=true
        echo -e "${GREEN}  ✓ [1] Manager created subtask(s)${NC}"
    else
        echo -e "${RED}  ✗ [1] Manager did NOT create any subtasks${NC}"
    fi

    # 2. サブタスクがワーカーに割り当てられているか
    SUBTASKS_ASSIGNED_TO_WORKER=$(sqlite3 "$SHARED_DB_PATH" "SELECT COUNT(*) FROM tasks WHERE parent_task_id = 'tsk_uc005_main' AND assignee_id = 'agt_uc005_worker';" 2>/dev/null || echo "0")
    echo "Subtasks assigned to Worker: $SUBTASKS_ASSIGNED_TO_WORKER"
    if [ "$SUBTASKS_ASSIGNED_TO_WORKER" -gt "0" ]; then
        V2_SUBTASK_TO_WORKER=true
        echo -e "${GREEN}  ✓ [2] Subtask(s) assigned to Worker${NC}"
    else
        echo -e "${RED}  ✗ [2] NO subtasks assigned to Worker${NC}"
    fi

    # 6. 全サブタスクがdoneか
    SUBTASKS_NOT_DONE=$(sqlite3 "$SHARED_DB_PATH" "SELECT COUNT(*) FROM tasks WHERE parent_task_id = 'tsk_uc005_main' AND status != 'done';" 2>/dev/null || echo "0")
    if [ "$SUBTASK_COUNT" -gt "0" ] && [ "$SUBTASKS_NOT_DONE" -eq "0" ]; then
        V6_ALL_SUBTASK_DONE=true
        echo -e "${GREEN}  ✓ [6] All subtasks are done${NC}"
    else
        echo -e "${RED}  ✗ [6] Some subtasks are NOT done ($SUBTASKS_NOT_DONE not done)${NC}"
    fi

    # 3. サブサブタスク（ワーカーが作成）
    SUBSUBTASK_COUNT=$(sqlite3 "$SHARED_DB_PATH" "SELECT COUNT(*) FROM tasks WHERE parent_task_id IN (SELECT id FROM tasks WHERE parent_task_id = 'tsk_uc005_main');" 2>/dev/null || echo "0")
    echo "Sub-subtasks (created by Worker): $SUBSUBTASK_COUNT"
    if [ "$SUBSUBTASK_COUNT" -gt "0" ]; then
        V3_SUBSUBTASK_CREATED=true
        echo -e "${GREEN}  ✓ [3] Worker created sub-subtask(s)${NC}"
    else
        echo -e "${RED}  ✗ [3] Worker did NOT create any sub-subtasks${NC}"
    fi

    # 4. サブサブタスクがワーカー自身に割り当てられているか
    SUBSUBTASKS_ASSIGNED_TO_WORKER=$(sqlite3 "$SHARED_DB_PATH" "SELECT COUNT(*) FROM tasks WHERE parent_task_id IN (SELECT id FROM tasks WHERE parent_task_id = 'tsk_uc005_main') AND assignee_id = 'agt_uc005_worker';" 2>/dev/null || echo "0")
    if [ "$SUBSUBTASK_COUNT" -gt "0" ] && [ "$SUBSUBTASKS_ASSIGNED_TO_WORKER" -eq "$SUBSUBTASK_COUNT" ]; then
        V4_SUBSUBTASK_TO_WORKER=true
        echo -e "${GREEN}  ✓ [4] All sub-subtasks assigned to Worker${NC}"
    elif [ "$SUBSUBTASK_COUNT" -eq "0" ]; then
        echo -e "${RED}  ✗ [4] No sub-subtasks exist to verify${NC}"
    else
        echo -e "${RED}  ✗ [4] NOT all sub-subtasks assigned to Worker ($SUBSUBTASKS_ASSIGNED_TO_WORKER of $SUBSUBTASK_COUNT)${NC}"
    fi

    # 5. 全サブサブタスクがdoneか
    SUBSUBTASKS_NOT_DONE=$(sqlite3 "$SHARED_DB_PATH" "SELECT COUNT(*) FROM tasks WHERE parent_task_id IN (SELECT id FROM tasks WHERE parent_task_id = 'tsk_uc005_main') AND status != 'done';" 2>/dev/null || echo "0")
    if [ "$SUBSUBTASK_COUNT" -gt "0" ] && [ "$SUBSUBTASKS_NOT_DONE" -eq "0" ]; then
        V5_ALL_SUBSUBTASK_DONE=true
        echo -e "${GREEN}  ✓ [5] All sub-subtasks are done${NC}"
    elif [ "$SUBSUBTASK_COUNT" -eq "0" ]; then
        echo -e "${RED}  ✗ [5] No sub-subtasks exist to verify${NC}"
    else
        echo -e "${RED}  ✗ [5] Some sub-subtasks are NOT done ($SUBSUBTASKS_NOT_DONE not done)${NC}"
    fi

    # 全タスク一覧
    echo ""
    echo "All tasks in hierarchy:"
    sqlite3 "$SHARED_DB_PATH" "SELECT id, title, status, assignee_id, parent_task_id FROM tasks;" 2>/dev/null
else
    echo -e "${RED}DB not found at $SHARED_DB_PATH${NC}"
fi
echo ""

# Step 7.6: 実行ログ検証
echo -e "${YELLOW}Step 7.6: Verifying execution logs${NC}"
if [ -f "$SHARED_DB_PATH" ]; then
    EXEC_LOG_COUNT=$(sqlite3 "$SHARED_DB_PATH" "SELECT COUNT(*) FROM execution_logs;" 2>/dev/null || echo "0")
    echo "Execution log records: $EXEC_LOG_COUNT"
    if [ "$EXEC_LOG_COUNT" -gt "0" ]; then
        echo -e "${GREEN}✓ Execution logs created${NC}"
        sqlite3 "$SHARED_DB_PATH" "SELECT id, task_id, agent_id, status FROM execution_logs;" 2>/dev/null
    fi
fi
echo ""

# Coordinator ログ表示
echo -e "${YELLOW}Coordinator log (last 50 lines):${NC}"
tail -50 /tmp/uc005_coordinator.log 2>/dev/null || echo "(no log)"
echo ""

# 結果判定（仕様書の7項目 + 成果物確認）
echo "=========================================="
echo -e "${YELLOW}Final Result: UC005 Specification Verification${NC}"
echo ""

# 成果物確認
OUTPUT_CREATED=false
if [ -f "$WORKING_DIR/$OUTPUT_FILE" ]; then
    OUTPUT_CREATED=true
    echo -e "${GREEN}  ✓ Output file created: $OUTPUT_FILE${NC}"
else
    echo -e "${RED}  ✗ Output file NOT created: $OUTPUT_FILE${NC}"
fi

# 7項目の結果サマリー
echo ""
echo "UC005 Specification (7 assertions):"
PASS_COUNT=0
FAIL_COUNT=0

check_assertion() {
    local num=$1
    local name=$2
    local result=$3
    if [ "$result" = "true" ]; then
        echo -e "${GREEN}  ✓ [$num] $name${NC}"
        PASS_COUNT=$((PASS_COUNT + 1))
    else
        echo -e "${RED}  ✗ [$num] $name${NC}"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
}

check_assertion 1 "Manager created subtask(s)" "$V1_SUBTASK_CREATED"
check_assertion 2 "Subtask(s) assigned to Worker" "$V2_SUBTASK_TO_WORKER"
check_assertion 3 "Worker created sub-subtask(s)" "$V3_SUBSUBTASK_CREATED"
check_assertion 4 "Sub-subtask(s) assigned to Worker" "$V4_SUBSUBTASK_TO_WORKER"
check_assertion 5 "All sub-subtasks are done" "$V5_ALL_SUBSUBTASK_DONE"
check_assertion 6 "All subtasks are done" "$V6_ALL_SUBTASK_DONE"
check_assertion 7 "Main task is done" "$V7_MAIN_TASK_DONE"

echo ""
echo "Result: $PASS_COUNT/7 assertions passed"
echo ""

# 全7項目がパスかつ成果物が作成されている場合のみ成功
if [ "$PASS_COUNT" -eq 7 ] && [ "$OUTPUT_CREATED" = "true" ]; then
    echo -e "${GREEN}UC005 App Integration Test: PASSED${NC}"
    echo ""
    echo "All 7 assertions verified:"
    echo "  ✓ Manager → Worker delegation flow completed"
    echo "  ✓ Task hierarchy correctly structured"
    echo "  ✓ Output file created ($CHARS chars)"
    exit 0
else
    echo -e "${RED}UC005 App Integration Test: FAILED${NC}"
    echo ""
    echo "Failed assertions: $FAIL_COUNT/7"
    if [ "$OUTPUT_CREATED" != "true" ]; then
        echo "Output file: NOT created"
    fi
    echo ""
    echo "Debug info:"
    echo "  - XCUITest log: /tmp/uc005_uitest.log"
    echo "  - Coordinator log: /tmp/uc005_coordinator.log"
    echo "  - Coordinator logs dir: /tmp/coordinator_logs_uc005/"
    echo "  - Shared DB: $SHARED_DB_PATH"
    TEST_FAILED=true
    exit 1
fi
