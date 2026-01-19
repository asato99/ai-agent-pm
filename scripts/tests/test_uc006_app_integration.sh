#!/bin/bash
# UC006 App Integration Test - Multiple Workers Assignment E2E Test
# 複数ワーカーへのタスク割り当てテスト
#
# 設計: 1プロジェクト + 3エージェント（マネージャー、日本語ワーカー、中国語ワーカー）+ 1親タスク
# - マネージャーが2つのサブタスクを作成
# - 日本語タスクは日本語担当ワーカーに割り当て
# - 中国語タスクは中国語担当ワーカーに割り当て
# - 各ワーカーが翻訳ファイルを生成
#
# フロー:
#   1. テスト環境準備
#   2. アプリビルド
#   3. MCPサーバービルド
#   4. Runner確認
#   5. Coordinator起動（ソケット待機状態で起動）
#   6. XCUITest実行（アプリ起動→MCP自動起動→シードデータ→ステータス変更→完了待機）
#   7. 結果検証（タスク割り当て、成果物）

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
WORKING_DIR="/tmp/uc006"
OUTPUT_FILE_JA="hello_ja.txt"
OUTPUT_FILE_ZH="hello_zh.txt"

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
        rm -f /tmp/uc006_coordinator.log
        rm -f /tmp/uc006_uitest.log
        rm -f /tmp/coordinator_uc006_config.yaml
        rm -rf /tmp/coordinator_logs_uc006
        rm -f "$SHARED_DB_PATH" "$SHARED_DB_PATH-shm" "$SHARED_DB_PATH-wal"
    fi
}

trap 'if [ $? -ne 0 ]; then TEST_FAILED=true; fi; cleanup' EXIT

echo "=========================================="
echo -e "${BLUE}UC006 App Integration Test${NC}"
echo -e "${BLUE}(Multiple Workers Assignment E2E)${NC}"
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
echo "  - $WORKING_DIR/$OUTPUT_FILE_JA (Japanese translation)"
echo "  - $WORKING_DIR/$OUTPUT_FILE_ZH (Chinese translation)"
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
echo "  Architecture: Phase 4 Coordinator with Multiple Workers"
echo "  - Coordinator starts FIRST and waits for MCP socket"
echo "  - App will start daemon, Coordinator will connect"
echo "  - Main task in_progress → Manager starts"
echo "  - Manager creates 2 subtasks → assigns to Workers based on specialization"
echo "  - Manager sets subtasks to in_progress → Workers start"
echo "  - Workers execute their translation tasks, complete"
echo "  - Manager confirms and completes main task"
echo "  Agents:"
echo "    - agt_uc006_manager (Translation Manager)"
echo "    - agt_uc006_ja (Japanese Translator)"
echo "    - agt_uc006_zh (Chinese Translator)"
echo ""

# Coordinator設定
cat > /tmp/coordinator_uc006_config.yaml << EOF
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
  agt_uc006_manager:
    passkey: test_passkey_uc006_manager
  agt_uc006_ja:
    passkey: test_passkey_uc006_ja
  agt_uc006_zh:
    passkey: test_passkey_uc006_zh

log_directory: /tmp/coordinator_logs_uc006
EOF

mkdir -p /tmp/coordinator_logs_uc006

# Coordinator起動
$PYTHON -m aiagent_runner --coordinator -c /tmp/coordinator_uc006_config.yaml -v > /tmp/uc006_coordinator.log 2>&1 &
COORDINATOR_PID=$!
echo "Coordinator started (PID: $COORDINATOR_PID)"
echo "Coordinator is waiting for MCP socket at: $HOME/Library/Application Support/AIAgentPM/mcp.sock"

sleep 2
if ! kill -0 "$COORDINATOR_PID" 2>/dev/null; then
    echo -e "${RED}Coordinator failed to start${NC}"
    cat /tmp/uc006_coordinator.log
    exit 1
fi
echo -e "${GREEN}✓ Coordinator is running and waiting for MCP socket${NC}"
echo ""

# Step 6: XCUITest実行
echo -e "${YELLOW}Step 6: Running XCUITest (app + MCP auto-start + seed data + wait for completion)${NC}"
echo "  This will:"
echo "    1. Launch app with -UITesting -UITestScenario:UC006"
echo "    2. App auto-starts MCP daemon (Coordinator will connect)"
echo "    3. Seed test data (Manager, 2 Workers, 1 main task, 1 input file)"
echo "    4. Change main task status: backlog → todo → in_progress via UI"
echo "    5. Wait for Manager → Workers assignment → completion (max 300s)"
echo ""

cd "$PROJECT_ROOT"
xcodebuild test \
    -scheme AIAgentPM \
    -destination "platform=macOS" \
    -only-testing:AIAgentPMUITests/UC006_MultiWorkerAssignmentTests/testMultiWorkerAssignment_ChangeMainTaskToInProgress \
    2>&1 | tee /tmp/uc006_uitest.log | grep -E "(Test Case|passed|failed|✅|❌|error:)" || true

# テスト結果確認
if grep -q "Test Suite 'UC006_MultiWorkerAssignmentTests' passed" /tmp/uc006_uitest.log; then
    echo -e "${GREEN}✓ XCUITest passed - Multiple Workers assignment completed${NC}"
elif grep -q "passed" /tmp/uc006_uitest.log; then
    echo -e "${GREEN}✓ XCUITest passed${NC}"
else
    echo -e "${RED}✗ XCUITest failed${NC}"
    grep -E "(error:|failed|FAIL)" /tmp/uc006_uitest.log | tail -20
    echo ""
    echo "Coordinator log (last 30 lines):"
    tail -30 /tmp/uc006_coordinator.log 2>/dev/null || echo "(no log)"
    TEST_FAILED=true
    # Continue to Step 7 for verification even if XCUITest fails
    # exit 1  # Removed to allow Step 7 verification
fi
echo ""

# Step 7: 結果検証
echo -e "${YELLOW}Step 7: Verifying outputs${NC}"

# ファイル存在確認
JA_FILE_CREATED=false
ZH_FILE_CREATED=false

if [ -f "$WORKING_DIR/$OUTPUT_FILE_JA" ]; then
    CONTENT_JA=$(cat "$WORKING_DIR/$OUTPUT_FILE_JA")
    CHARS_JA=$(echo "$CONTENT_JA" | wc -c | tr -d ' ')
    echo "$OUTPUT_FILE_JA: $CHARS_JA characters"
    echo -e "${GREEN}✓ $OUTPUT_FILE_JA created by Japanese Worker${NC}"
    JA_FILE_CREATED=true
else
    echo -e "${RED}✗ $OUTPUT_FILE_JA not found${NC}"
fi

if [ -f "$WORKING_DIR/$OUTPUT_FILE_ZH" ]; then
    CONTENT_ZH=$(cat "$WORKING_DIR/$OUTPUT_FILE_ZH")
    CHARS_ZH=$(echo "$CONTENT_ZH" | wc -c | tr -d ' ')
    echo "$OUTPUT_FILE_ZH: $CHARS_ZH characters"
    echo -e "${GREEN}✓ $OUTPUT_FILE_ZH created by Chinese Worker${NC}"
    ZH_FILE_CREATED=true
else
    echo -e "${RED}✗ $OUTPUT_FILE_ZH not found${NC}"
fi
echo ""

# Step 7.5: タスク階層の検証（仕様書の7項目に基づく）
echo -e "${YELLOW}Step 7.5: Verifying task assignment (UC006 spec: 7 assertions)${NC}"

# 検証結果フラグ（仕様書の7項目）
V1_SUBTASK_CREATED=false      # 1. マネージャーがサブタスク(2つ)を作成したこと
V2_JA_TASK_TO_JA_WORKER=false # 2. 日本語タスクが日本語担当に割り当てられていること
V3_ZH_TASK_TO_ZH_WORKER=false # 3. 中国語タスクが中国語担当に割り当てられていること
V4_JA_FILE_CREATED=false      # 4. hello_ja.txt が作成されていること
V5_ZH_FILE_CREATED=false      # 5. hello_zh.txt が作成されていること
V6_ALL_SUBTASK_DONE=false     # 6. 全サブタスクがdoneになっていること
V7_MAIN_TASK_DONE=false       # 7. 親タスクがdoneになっていること

if [ -f "$SHARED_DB_PATH" ]; then
    # 7. 親タスクのステータス
    MAIN_TASK_STATUS=$(sqlite3 "$SHARED_DB_PATH" "SELECT status FROM tasks WHERE id = 'tsk_uc006_main';" 2>/dev/null || echo "")
    echo "Main task (tsk_uc006_main) status: $MAIN_TASK_STATUS"
    if [ "$MAIN_TASK_STATUS" = "done" ]; then
        V7_MAIN_TASK_DONE=true
        echo -e "${GREEN}  ✓ [7] Main task is done${NC}"
    else
        echo -e "${RED}  ✗ [7] Main task is NOT done (status: $MAIN_TASK_STATUS)${NC}"
    fi

    # 1. サブタスク（マネージャーが作成）
    SUBTASK_COUNT=$(sqlite3 "$SHARED_DB_PATH" "SELECT COUNT(*) FROM tasks WHERE parent_task_id = 'tsk_uc006_main';" 2>/dev/null || echo "0")
    echo "Subtasks (created by Manager): $SUBTASK_COUNT"
    if [ "$SUBTASK_COUNT" -ge "2" ]; then
        V1_SUBTASK_CREATED=true
        echo -e "${GREEN}  ✓ [1] Manager created 2+ subtasks${NC}"
    else
        echo -e "${RED}  ✗ [1] Manager did NOT create 2 subtasks (found: $SUBTASK_COUNT)${NC}"
    fi

    # 2. 日本語タスクが日本語担当に割り当てられているか
    # タスクのtitleまたはdescriptionに「日本語」を含み、assignee_idが agt_uc006_ja
    JA_TASK_ASSIGNED=$(sqlite3 "$SHARED_DB_PATH" "SELECT COUNT(*) FROM tasks WHERE parent_task_id = 'tsk_uc006_main' AND assignee_id = 'agt_uc006_ja' AND (title LIKE '%日本語%' OR description LIKE '%日本語%' OR title LIKE '%Japanese%' OR description LIKE '%Japanese%' OR title LIKE '%ja%' OR title LIKE '%JA%');" 2>/dev/null || echo "0")
    echo "Japanese tasks assigned to JA worker: $JA_TASK_ASSIGNED"
    if [ "$JA_TASK_ASSIGNED" -gt "0" ]; then
        V2_JA_TASK_TO_JA_WORKER=true
        echo -e "${GREEN}  ✓ [2] Japanese task assigned to Japanese worker${NC}"
    else
        echo -e "${RED}  ✗ [2] Japanese task NOT properly assigned${NC}"
        # デバッグ: 全サブタスクを表示
        echo "  Debug - all subtasks:"
        sqlite3 "$SHARED_DB_PATH" "SELECT id, title, assignee_id FROM tasks WHERE parent_task_id = 'tsk_uc006_main';" 2>/dev/null
    fi

    # 3. 中国語タスクが中国語担当に割り当てられているか
    ZH_TASK_ASSIGNED=$(sqlite3 "$SHARED_DB_PATH" "SELECT COUNT(*) FROM tasks WHERE parent_task_id = 'tsk_uc006_main' AND assignee_id = 'agt_uc006_zh' AND (title LIKE '%中国語%' OR description LIKE '%中国語%' OR title LIKE '%Chinese%' OR description LIKE '%Chinese%' OR title LIKE '%zh%' OR title LIKE '%ZH%');" 2>/dev/null || echo "0")
    echo "Chinese tasks assigned to ZH worker: $ZH_TASK_ASSIGNED"
    if [ "$ZH_TASK_ASSIGNED" -gt "0" ]; then
        V3_ZH_TASK_TO_ZH_WORKER=true
        echo -e "${GREEN}  ✓ [3] Chinese task assigned to Chinese worker${NC}"
    else
        echo -e "${RED}  ✗ [3] Chinese task NOT properly assigned${NC}"
    fi

    # 4. 日本語翻訳ファイル作成
    if [ "$JA_FILE_CREATED" = "true" ]; then
        V4_JA_FILE_CREATED=true
        echo -e "${GREEN}  ✓ [4] hello_ja.txt created${NC}"
    else
        echo -e "${RED}  ✗ [4] hello_ja.txt NOT created${NC}"
    fi

    # 5. 中国語翻訳ファイル作成
    if [ "$ZH_FILE_CREATED" = "true" ]; then
        V5_ZH_FILE_CREATED=true
        echo -e "${GREEN}  ✓ [5] hello_zh.txt created${NC}"
    else
        echo -e "${RED}  ✗ [5] hello_zh.txt NOT created${NC}"
    fi

    # 6. 全サブタスクがdoneか
    SUBTASKS_NOT_DONE=$(sqlite3 "$SHARED_DB_PATH" "SELECT COUNT(*) FROM tasks WHERE parent_task_id = 'tsk_uc006_main' AND status != 'done';" 2>/dev/null || echo "0")
    if [ "$SUBTASK_COUNT" -gt "0" ] && [ "$SUBTASKS_NOT_DONE" -eq "0" ]; then
        V6_ALL_SUBTASK_DONE=true
        echo -e "${GREEN}  ✓ [6] All subtasks are done${NC}"
    else
        echo -e "${RED}  ✗ [6] Some subtasks are NOT done ($SUBTASKS_NOT_DONE not done)${NC}"
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

# Step 7.7: 並行実行検証
echo -e "${YELLOW}Step 7.7: Verifying parallel execution${NC}"
V8_PARALLEL_EXECUTION=false
if [ -f "$SHARED_DB_PATH" ]; then
    # 実行ログを取得（サブタスクの直接の実行ログのみ）
    JA_START=$(sqlite3 "$SHARED_DB_PATH" "
        SELECT e.started_at FROM execution_logs e
        JOIN tasks t ON e.task_id = t.id
        WHERE e.agent_id = 'agt_uc006_ja' AND t.parent_task_id = 'tsk_uc006_main'
        ORDER BY e.started_at LIMIT 1;
    " 2>/dev/null || echo "")

    ZH_START=$(sqlite3 "$SHARED_DB_PATH" "
        SELECT e.started_at FROM execution_logs e
        JOIN tasks t ON e.task_id = t.id
        WHERE e.agent_id = 'agt_uc006_zh' AND t.parent_task_id = 'tsk_uc006_main'
        ORDER BY e.started_at LIMIT 1;
    " 2>/dev/null || echo "")

    JA_END=$(sqlite3 "$SHARED_DB_PATH" "
        SELECT e.completed_at FROM execution_logs e
        JOIN tasks t ON e.task_id = t.id
        WHERE e.agent_id = 'agt_uc006_ja' AND t.parent_task_id = 'tsk_uc006_main'
        ORDER BY e.started_at LIMIT 1;
    " 2>/dev/null || echo "")

    ZH_END=$(sqlite3 "$SHARED_DB_PATH" "
        SELECT e.completed_at FROM execution_logs e
        JOIN tasks t ON e.task_id = t.id
        WHERE e.agent_id = 'agt_uc006_zh' AND t.parent_task_id = 'tsk_uc006_main'
        ORDER BY e.started_at LIMIT 1;
    " 2>/dev/null || echo "")

    echo "Execution times:"
    echo "  JA Worker: started=$JA_START, completed=$JA_END"
    echo "  ZH Worker: started=$ZH_START, completed=$ZH_END"

    # 並行実行の判定
    # 並行実行 ⟺ JA.started < ZH.completed AND ZH.started < JA.completed
    # completed_at がない場合は検証不可（並行/順次の判定はできない）
    if [ -n "$JA_END" ] && [ -n "$ZH_END" ]; then
        # 両方完了している場合: 期間重複チェック
        PARALLEL_CHECK=$(sqlite3 "$SHARED_DB_PATH" "
            SELECT COUNT(*)
            FROM execution_logs ja, execution_logs zh
            WHERE ja.agent_id = 'agt_uc006_ja'
              AND zh.agent_id = 'agt_uc006_zh'
              AND ja.task_id IN (SELECT id FROM tasks WHERE parent_task_id = 'tsk_uc006_main')
              AND zh.task_id IN (SELECT id FROM tasks WHERE parent_task_id = 'tsk_uc006_main')
              AND ja.started_at < zh.completed_at
              AND zh.started_at < ja.completed_at;
        " 2>/dev/null || echo "0")

        if [ "$PARALLEL_CHECK" -gt "0" ]; then
            V8_PARALLEL_EXECUTION=true
            echo -e "${GREEN}✓ Workers executed in parallel (overlapping execution periods)${NC}"
        else
            echo -e "${RED}✗ Workers did NOT execute in parallel (no overlap in execution periods)${NC}"
        fi
    else
        # completed_at がない場合は検証不可
        echo -e "${YELLOW}⚠ Cannot verify parallel execution (completed_at is NULL)${NC}"
        echo "  Parallel execution requires both start and end times to check period overlap."
    fi

    # デバッグ用: 実行タイムライン表示
    echo ""
    echo "Execution timeline:"
    sqlite3 "$SHARED_DB_PATH" "
        SELECT e.agent_id, substr(t.title, 1, 30) as title,
               datetime(e.started_at) AS started,
               datetime(e.completed_at) AS completed
        FROM execution_logs e
        JOIN tasks t ON e.task_id = t.id
        WHERE e.agent_id IN ('agt_uc006_ja', 'agt_uc006_zh')
          AND t.parent_task_id = 'tsk_uc006_main'
        ORDER BY e.started_at;
    " 2>/dev/null
fi
echo ""

# Coordinator ログ表示
echo -e "${YELLOW}Coordinator log (last 50 lines):${NC}"
tail -50 /tmp/uc006_coordinator.log 2>/dev/null || echo "(no log)"
echo ""

# 結果判定（仕様書の8項目）
echo "=========================================="
echo -e "${YELLOW}Final Result: UC006 Specification Verification${NC}"
echo ""

# 8項目の結果サマリー
echo "UC006 Specification (8 assertions):"
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
check_assertion 2 "Japanese task assigned to Japanese worker" "$V2_JA_TASK_TO_JA_WORKER"
check_assertion 3 "Chinese task assigned to Chinese worker" "$V3_ZH_TASK_TO_ZH_WORKER"
check_assertion 4 "hello_ja.txt created" "$V4_JA_FILE_CREATED"
check_assertion 5 "hello_zh.txt created" "$V5_ZH_FILE_CREATED"
check_assertion 6 "All subtasks are done" "$V6_ALL_SUBTASK_DONE"
check_assertion 7 "Main task is done" "$V7_MAIN_TASK_DONE"
check_assertion 8 "Workers executed in parallel" "$V8_PARALLEL_EXECUTION"

echo ""
echo "Result: $PASS_COUNT/8 assertions passed"
echo ""

# 全8項目がパスの場合のみ成功
if [ "$PASS_COUNT" -eq 8 ]; then
    echo -e "${GREEN}UC006 App Integration Test: PASSED${NC}"
    echo ""
    echo "All 8 assertions verified:"
    echo "  ✓ Manager → Multiple Workers assignment based on specialization"
    echo "  ✓ Tasks correctly assigned to appropriate workers"
    echo "  ✓ Output files created (hello_ja.txt, hello_zh.txt)"
    echo "  ✓ Workers executed in parallel"
    exit 0
else
    echo -e "${RED}UC006 App Integration Test: FAILED${NC}"
    echo ""
    echo "Failed assertions: $FAIL_COUNT/8"
    echo ""
    echo "Debug info:"
    echo "  - XCUITest log: /tmp/uc006_uitest.log"
    echo "  - Coordinator log: /tmp/uc006_coordinator.log"
    echo "  - Coordinator logs dir: /tmp/coordinator_logs_uc006/"
    echo "  - Shared DB: $SHARED_DB_PATH"
    TEST_FAILED=true
    exit 1
fi
