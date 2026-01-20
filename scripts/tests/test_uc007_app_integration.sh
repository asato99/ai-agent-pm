#!/bin/bash
# UC007 App Integration Test - Dependent Task Execution E2E Test
# 依存関係のあるタスク実行テスト（生成→計算）
#
# 設計: 1プロジェクト + 3エージェント（マネージャー、生成担当、計算担当）+ 1親タスク
# - マネージャーが2つのサブタスクを作成（生成タスク、計算タスク）
# - 計算タスクは生成タスクに依存（dependencies フィールドで設定）
# - 生成担当が乱数をseed.txtに書き込み
# - 計算担当がseed.txtを読み込み、2倍にしてresult.txtに書き込み
#
# 検証ポイント（厳密）:
#   - DBでdependenciesフィールドが設定されていること
#   - seed.txt × 2 == result.txt であること
#
# フロー:
#   1. テスト環境準備
#   2. アプリビルド
#   3. MCPサーバービルド
#   4. Runner確認
#   5. Coordinator起動（ソケット待機状態で起動）
#   6. XCUITest実行（アプリ起動→MCP自動起動→シードデータ→ステータス変更→完了待機）
#   7. 結果検証（依存関係設定、成果物、計算結果の整合性）

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
WORKING_DIR="/tmp/uc007"
OUTPUT_FILE_SEED="seed.txt"
OUTPUT_FILE_RESULT="result.txt"

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
        rm -f /tmp/uc007_coordinator.log
        rm -f /tmp/uc007_uitest.log
        rm -f /tmp/coordinator_uc007_config.yaml
        rm -rf /tmp/coordinator_logs_uc007
        rm -f "$SHARED_DB_PATH" "$SHARED_DB_PATH-shm" "$SHARED_DB_PATH-wal"
    fi
}

trap 'if [ $? -ne 0 ]; then TEST_FAILED=true; fi; cleanup' EXIT

echo "=========================================="
echo -e "${BLUE}UC007 App Integration Test${NC}"
echo -e "${BLUE}(Dependent Task Execution: Generator → Calculator)${NC}"
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
echo "Expected outputs:"
echo "  - $WORKING_DIR/$OUTPUT_FILE_SEED (Random number)"
echo "  - $WORKING_DIR/$OUTPUT_FILE_RESULT (Seed × 2)"
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
echo "  Architecture: Phase 4 Coordinator with Dependent Tasks"
echo "  - Coordinator starts FIRST and waits for MCP socket"
echo "  - App will start daemon, Coordinator will connect"
echo "  - Main task in_progress → Manager starts"
echo "  - Manager creates 2 subtasks with dependency (generator → calculator)"
echo "  - Generator task executes first"
echo "  - Calculator task waits for generator to complete"
echo "  - Calculator task executes after generator is done"
echo "  Agents:"
echo "    - agt_uc007_manager (Manager)"
echo "    - agt_uc007_generator (Generator Worker)"
echo "    - agt_uc007_calculator (Calculator Worker)"
echo ""

# Coordinator設定
cat > /tmp/coordinator_uc007_config.yaml << EOF
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
  agt_uc007_manager:
    passkey: test_passkey_uc007_manager
  agt_uc007_generator:
    passkey: test_passkey_uc007_generator
  agt_uc007_calculator:
    passkey: test_passkey_uc007_calculator

log_directory: /tmp/coordinator_logs_uc007
EOF

mkdir -p /tmp/coordinator_logs_uc007

# Coordinator起動
$PYTHON -m aiagent_runner --coordinator -c /tmp/coordinator_uc007_config.yaml -v > /tmp/uc007_coordinator.log 2>&1 &
COORDINATOR_PID=$!
echo "Coordinator started (PID: $COORDINATOR_PID)"
echo "Coordinator is waiting for MCP socket at: $HOME/Library/Application Support/AIAgentPM/mcp.sock"

sleep 2
if ! kill -0 "$COORDINATOR_PID" 2>/dev/null; then
    echo -e "${RED}Coordinator failed to start${NC}"
    cat /tmp/uc007_coordinator.log
    exit 1
fi
echo -e "${GREEN}✓ Coordinator is running and waiting for MCP socket${NC}"
echo ""

# Step 6: XCUITest実行
echo -e "${YELLOW}Step 6: Running XCUITest (app + MCP auto-start + seed data + wait for completion)${NC}"
echo "  This will:"
echo "    1. Launch app with -UITesting -UITestScenario:UC007"
echo "    2. App auto-starts MCP daemon (Coordinator will connect)"
echo "    3. Seed test data (Manager, 2 Workers, 1 main task)"
echo "    4. Change main task status: backlog → todo → in_progress via UI"
echo "    5. Wait for Manager → Workers (with dependency) → completion (max 300s)"
echo ""

cd "$PROJECT_ROOT"
xcodebuild test \
    -scheme AIAgentPM \
    -destination "platform=macOS" \
    -only-testing:AIAgentPMUITests/UC007_DependentTaskExecutionTests/testDependentTaskExecution_ChangeMainTaskToInProgress \
    2>&1 | tee /tmp/uc007_uitest.log | grep -E "(Test Case|passed|failed|✅|❌|error:)" || true

# テスト結果確認
if grep -q "Test Suite 'UC007_DependentTaskExecutionTests' passed" /tmp/uc007_uitest.log; then
    echo -e "${GREEN}✓ XCUITest passed - Dependent task execution completed${NC}"
elif grep -q "passed" /tmp/uc007_uitest.log; then
    echo -e "${GREEN}✓ XCUITest passed${NC}"
else
    echo -e "${RED}✗ XCUITest failed${NC}"
    grep -E "(error:|failed|FAIL)" /tmp/uc007_uitest.log | tail -20
    echo ""
    echo "Coordinator log (last 30 lines):"
    tail -30 /tmp/uc007_coordinator.log 2>/dev/null || echo "(no log)"
    TEST_FAILED=true
    exit 1
fi
echo ""

# Step 7: 結果検証
echo -e "${YELLOW}Step 7: Verifying outputs${NC}"

# ファイル存在確認
SEED_FILE_CREATED=false
RESULT_FILE_CREATED=false
SEED_VALUE=""
RESULT_VALUE=""

if [ -f "$WORKING_DIR/$OUTPUT_FILE_SEED" ]; then
    SEED_VALUE=$(cat "$WORKING_DIR/$OUTPUT_FILE_SEED" | tr -d '[:space:]')
    echo "seed.txt: $SEED_VALUE"
    echo -e "${GREEN}✓ $OUTPUT_FILE_SEED created by Generator Worker${NC}"
    SEED_FILE_CREATED=true
else
    echo -e "${RED}✗ $OUTPUT_FILE_SEED not found${NC}"
fi

if [ -f "$WORKING_DIR/$OUTPUT_FILE_RESULT" ]; then
    RESULT_VALUE=$(cat "$WORKING_DIR/$OUTPUT_FILE_RESULT" | tr -d '[:space:]')
    echo "result.txt: $RESULT_VALUE"
    echo -e "${GREEN}✓ $OUTPUT_FILE_RESULT created by Calculator Worker${NC}"
    RESULT_FILE_CREATED=true
else
    echo -e "${RED}✗ $OUTPUT_FILE_RESULT not found${NC}"
fi
echo ""

# Step 7.5: タスク階層の検証（仕様書の9項目に基づく）
echo -e "${YELLOW}Step 7.5: Verifying task assignment (UC007 spec: 9 assertions)${NC}"

# 検証結果フラグ（仕様書の9項目）
V1_SUBTASK_CREATED=false        # 1. マネージャーがサブタスク(2つ)を作成したこと
V2_GEN_TASK_TO_GEN_WORKER=false # 2. 生成タスクが生成担当に割り当てられていること
V3_CALC_TASK_TO_CALC_WORKER=false # 3. 計算タスクが計算担当に割り当てられていること
V4_DEPENDENCY_SET=false          # 4. 【厳密】計算タスクのdependenciesに生成タスクIDが含まれる
V5_SEED_FILE_CREATED=false       # 5. seed.txt が作成されていること
V6_RESULT_FILE_CREATED=false     # 6. result.txt が作成されていること
V7_CALCULATION_CORRECT=false     # 7. 【厳密】seed × 2 == result
V8_EXECUTION_ORDER=false         # 8. 生成タスク完了時刻 < 計算タスク開始時刻
V9_ALL_TASKS_DONE=false          # 9. 全タスクがdoneになっていること

if [ -f "$SHARED_DB_PATH" ]; then
    # 9. 親タスクのステータス
    MAIN_TASK_STATUS=$(sqlite3 "$SHARED_DB_PATH" "SELECT status FROM tasks WHERE id = 'tsk_uc007_main';" 2>/dev/null || echo "")
    echo "Main task (tsk_uc007_main) status: $MAIN_TASK_STATUS"

    # 1. サブタスク（マネージャーが作成）
    SUBTASK_COUNT=$(sqlite3 "$SHARED_DB_PATH" "SELECT COUNT(*) FROM tasks WHERE parent_task_id = 'tsk_uc007_main';" 2>/dev/null || echo "0")
    echo "Subtasks (created by Manager): $SUBTASK_COUNT"
    if [ "$SUBTASK_COUNT" -ge "2" ]; then
        V1_SUBTASK_CREATED=true
        echo -e "${GREEN}  ✓ [1] Manager created 2+ subtasks${NC}"
    else
        echo -e "${RED}  ✗ [1] Manager did NOT create 2 subtasks (found: $SUBTASK_COUNT)${NC}"
    fi

    # 2. 生成タスクが生成担当に割り当てられているか
    GEN_TASK_ASSIGNED=$(sqlite3 "$SHARED_DB_PATH" "SELECT COUNT(*) FROM tasks WHERE parent_task_id = 'tsk_uc007_main' AND assignee_id = 'agt_uc007_generator' AND (title LIKE '%生成%' OR title LIKE '%seed%' OR title LIKE '%乱数%' OR description LIKE '%seed%' OR description LIKE '%乱数%');" 2>/dev/null || echo "0")
    echo "Generator tasks assigned to Generator worker: $GEN_TASK_ASSIGNED"
    if [ "$GEN_TASK_ASSIGNED" -gt "0" ]; then
        V2_GEN_TASK_TO_GEN_WORKER=true
        echo -e "${GREEN}  ✓ [2] Generator task assigned to Generator worker${NC}"
    else
        echo -e "${RED}  ✗ [2] Generator task NOT properly assigned${NC}"
        echo "  Debug - all subtasks:"
        sqlite3 "$SHARED_DB_PATH" "SELECT id, title, assignee_id FROM tasks WHERE parent_task_id = 'tsk_uc007_main';" 2>/dev/null
    fi

    # 3. 計算タスクが計算担当に割り当てられているか
    CALC_TASK_ASSIGNED=$(sqlite3 "$SHARED_DB_PATH" "SELECT COUNT(*) FROM tasks WHERE parent_task_id = 'tsk_uc007_main' AND assignee_id = 'agt_uc007_calculator' AND (title LIKE '%計算%' OR title LIKE '%2倍%' OR title LIKE '%result%' OR description LIKE '%2倍%' OR description LIKE '%result%');" 2>/dev/null || echo "0")
    echo "Calculator tasks assigned to Calculator worker: $CALC_TASK_ASSIGNED"
    if [ "$CALC_TASK_ASSIGNED" -gt "0" ]; then
        V3_CALC_TASK_TO_CALC_WORKER=true
        echo -e "${GREEN}  ✓ [3] Calculator task assigned to Calculator worker${NC}"
    else
        echo -e "${RED}  ✗ [3] Calculator task NOT properly assigned${NC}"
    fi

    # 4. 【厳密】依存関係の検証（DBのdependenciesフィールドを確認）
    # 生成タスクのIDを取得
    GEN_TASK_ID=$(sqlite3 "$SHARED_DB_PATH" "SELECT id FROM tasks WHERE parent_task_id = 'tsk_uc007_main' AND assignee_id = 'agt_uc007_generator' LIMIT 1;" 2>/dev/null || echo "")
    # 計算タスクのdependenciesを取得
    CALC_TASK_DEPS=$(sqlite3 "$SHARED_DB_PATH" "SELECT dependencies FROM tasks WHERE parent_task_id = 'tsk_uc007_main' AND assignee_id = 'agt_uc007_calculator' LIMIT 1;" 2>/dev/null || echo "")

    echo "  Generator task ID: $GEN_TASK_ID"
    echo "  Calculator task dependencies: $CALC_TASK_DEPS"

    if [ -n "$GEN_TASK_ID" ] && [ -n "$CALC_TASK_DEPS" ]; then
        # dependenciesはJSON配列として保存されている（例: ["tsk_xxx"]）
        if echo "$CALC_TASK_DEPS" | grep -q "$GEN_TASK_ID"; then
            V4_DEPENDENCY_SET=true
            echo -e "${GREEN}  ✓ [4] Calculator task depends on Generator task (DB verified)${NC}"
        else
            echo -e "${RED}  ✗ [4] Calculator task does NOT depend on Generator task in DB${NC}"
            echo "    Expected: dependencies to contain '$GEN_TASK_ID'"
            echo "    Actual: '$CALC_TASK_DEPS'"
        fi
    else
        echo -e "${RED}  ✗ [4] Could not verify dependency (missing task IDs)${NC}"
    fi

    # 5-6. ファイル作成
    if [ "$SEED_FILE_CREATED" = "true" ]; then
        V5_SEED_FILE_CREATED=true
        echo -e "${GREEN}  ✓ [5] seed.txt created${NC}"
    else
        echo -e "${RED}  ✗ [5] seed.txt NOT created${NC}"
    fi

    if [ "$RESULT_FILE_CREATED" = "true" ]; then
        V6_RESULT_FILE_CREATED=true
        echo -e "${GREEN}  ✓ [6] result.txt created${NC}"
    else
        echo -e "${RED}  ✗ [6] result.txt NOT created${NC}"
    fi

    # 7. 【厳密】計算結果の検証（seed × 2 == result）
    if [ -n "$SEED_VALUE" ] && [ -n "$RESULT_VALUE" ]; then
        EXPECTED_RESULT=$((SEED_VALUE * 2))
        if [ "$RESULT_VALUE" -eq "$EXPECTED_RESULT" ]; then
            V7_CALCULATION_CORRECT=true
            echo -e "${GREEN}  ✓ [7] Calculation correct: $SEED_VALUE × 2 = $RESULT_VALUE${NC}"
        else
            echo -e "${RED}  ✗ [7] Calculation INCORRECT: $SEED_VALUE × 2 should be $EXPECTED_RESULT, but got $RESULT_VALUE${NC}"
        fi
    else
        echo -e "${RED}  ✗ [7] Cannot verify calculation (missing values)${NC}"
    fi

    # 8. 実行順序の検証（ファイルタイムスタンプ）
    if [ -f "$WORKING_DIR/$OUTPUT_FILE_SEED" ] && [ -f "$WORKING_DIR/$OUTPUT_FILE_RESULT" ]; then
        SEED_MTIME=$(stat -f %m "$WORKING_DIR/$OUTPUT_FILE_SEED" 2>/dev/null || echo "0")
        RESULT_MTIME=$(stat -f %m "$WORKING_DIR/$OUTPUT_FILE_RESULT" 2>/dev/null || echo "0")
        if [ "$SEED_MTIME" -lt "$RESULT_MTIME" ]; then
            V8_EXECUTION_ORDER=true
            echo -e "${GREEN}  ✓ [8] Execution order correct (seed.txt created before result.txt)${NC}"
        else
            echo -e "${RED}  ✗ [8] Execution order INCORRECT (result.txt may have been created before seed.txt)${NC}"
        fi
    else
        echo -e "${YELLOW}  ⚠ [8] Cannot verify execution order (files not found)${NC}"
    fi

    # 9. 全タスクがdoneか
    TASKS_NOT_DONE=$(sqlite3 "$SHARED_DB_PATH" "SELECT COUNT(*) FROM tasks WHERE (id = 'tsk_uc007_main' OR parent_task_id = 'tsk_uc007_main') AND status != 'done';" 2>/dev/null || echo "0")
    if [ "$TASKS_NOT_DONE" -eq "0" ]; then
        V9_ALL_TASKS_DONE=true
        echo -e "${GREEN}  ✓ [9] All tasks are done${NC}"
    else
        echo -e "${RED}  ✗ [9] Some tasks are NOT done ($TASKS_NOT_DONE not done)${NC}"
    fi

    # 全タスク一覧
    echo ""
    echo "All tasks in hierarchy:"
    sqlite3 "$SHARED_DB_PATH" "SELECT id, title, status, assignee_id, parent_task_id, dependencies FROM tasks;" 2>/dev/null
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
        sqlite3 "$SHARED_DB_PATH" "SELECT id, task_id, agent_id, status, started_at FROM execution_logs ORDER BY started_at;" 2>/dev/null
    fi
fi
echo ""

# Coordinator ログ表示
echo -e "${YELLOW}Coordinator log (last 50 lines):${NC}"
tail -50 /tmp/uc007_coordinator.log 2>/dev/null || echo "(no log)"
echo ""

# 結果判定（仕様書の9項目）
echo "=========================================="
echo -e "${YELLOW}Final Result: UC007 Specification Verification${NC}"
echo ""

# 9項目の結果サマリー
echo "UC007 Specification (9 assertions):"
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

check_assertion 1 "Manager created 2+ subtasks" "$V1_SUBTASK_CREATED"
check_assertion 2 "Generator task assigned to Generator worker" "$V2_GEN_TASK_TO_GEN_WORKER"
check_assertion 3 "Calculator task assigned to Calculator worker" "$V3_CALC_TASK_TO_CALC_WORKER"
check_assertion 4 "Dependency set in DB (calculator depends on generator)" "$V4_DEPENDENCY_SET"
check_assertion 5 "seed.txt created" "$V5_SEED_FILE_CREATED"
check_assertion 6 "result.txt created" "$V6_RESULT_FILE_CREATED"
check_assertion 7 "Calculation correct (seed × 2 == result)" "$V7_CALCULATION_CORRECT"
check_assertion 8 "Execution order correct (generator before calculator)" "$V8_EXECUTION_ORDER"
check_assertion 9 "All tasks are done" "$V9_ALL_TASKS_DONE"

echo ""
echo "Result: $PASS_COUNT/9 assertions passed"
echo ""

# 全9項目がパスの場合のみ成功
if [ "$PASS_COUNT" -eq 9 ]; then
    echo -e "${GREEN}UC007 App Integration Test: PASSED${NC}"
    echo ""
    echo "All 9 assertions verified:"
    echo "  ✓ Manager → Workers assignment with dependency"
    echo "  ✓ Dependency correctly set in DB"
    echo "  ✓ Execution order: Generator completed before Calculator started"
    echo "  ✓ Calculation integrity: seed × 2 == result"
    echo "  ✓ Output files created (seed.txt, result.txt)"
    exit 0
else
    echo -e "${RED}UC007 App Integration Test: FAILED${NC}"
    echo ""
    echo "Failed assertions: $FAIL_COUNT/9"
    echo ""
    echo "Debug info:"
    echo "  - XCUITest log: /tmp/uc007_uitest.log"
    echo "  - Coordinator log: /tmp/uc007_coordinator.log"
    echo "  - Coordinator logs dir: /tmp/coordinator_logs_uc007/"
    echo "  - Shared DB: $SHARED_DB_PATH"
    TEST_FAILED=true
    exit 1
fi
