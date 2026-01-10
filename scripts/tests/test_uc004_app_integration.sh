#!/bin/bash
# UC004 App Integration Test - Multi-Project Same Agent E2E Test
# 複数プロジェクト×同一エージェント統合テスト
#
# 設計: 2プロジェクト + 1エージェント（両方に割り当て）+ 2タスク（各プロジェクトに1つ）
# - 同一エージェントが複数プロジェクトで独立して動作することを検証
#
# フロー:
#   1. アプリビルド
#   2. MCPサーバービルド
#   3. Runner確認
#   4. Coordinator起動（ソケット待機状態で起動）
#   5. XCUITest実行（アプリ起動→MCP自動起動→Coordinator接続→ステータス変更→ファイル作成待機）
#   6. 結果検証
#
# アーキテクチャ（Phase 4 Coordinator）:
#   - 単一のCoordinatorが全ての(agent_id, project_id)ペアを管理
#   - Coordinatorはagentごとのpasskeyを保持
#   - get_agent_action(agent_id, project_id)で各ペアの作業有無を確認
#   - 作業があればAgent Instance（Claude Code）をスポーン
#   - Agent Instanceがauthenticate → get_my_task → execute → report_completed
#
# ポイント:
#   - Coordinatorが先に起動してソケット待機
#   - アプリがMCPデーモンを自動起動
#   - XCUITestでDBにデータを投入
#   - XCUITest内でファイル作成を待機（アプリが起動している間）

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
TEST_DIR="/tmp/uc004_app_integration_test"
OUTPUT_FILE="README.md"

# シードデータが作成するディレクトリ（seedUC004Dataで設定）
FRONTEND_WORK_DIR="/tmp/uc004/frontend"
BACKEND_WORK_DIR="/tmp/uc004/backend"

# 共有DB: XCUITestアプリが使用するパス
SHARED_DB_PATH="/tmp/AIAgentPM_UITest.db"

# Phase 5: Coordinator token for authorization
export MCP_COORDINATOR_TOKEN="test_coordinator_token_uc001"

COORDINATOR_PID=""

# クリーンアップ関数
cleanup() {
    echo ""
    echo -e "${YELLOW}Cleanup${NC}"
    # Coordinator停止（単一プロセス）
    if [ -n "$COORDINATOR_PID" ] && kill -0 "$COORDINATOR_PID" 2>/dev/null; then
        kill "$COORDINATOR_PID" 2>/dev/null || true
        echo "Coordinator stopped"
    fi
    # Note: MCP Daemon is managed by the app (terminates when app terminates)
    if [ "$1" != "--keep" ]; then
        rm -rf "$TEST_DIR"
        rm -rf /tmp/uc004
        rm -f /tmp/uc004_coordinator.log
        rm -f /tmp/uc004_uitest.log
        rm -f /tmp/coordinator_uc004_config.yaml
        rm -rf /tmp/coordinator_logs_uc004
        rm -f "$SHARED_DB_PATH" "$SHARED_DB_PATH-shm" "$SHARED_DB_PATH-wal"
    fi
}

trap cleanup EXIT

echo "=========================================="
echo -e "${BLUE}UC004 App Integration Test${NC}"
echo -e "${BLUE}(Multi-Project Same Agent E2E)${NC}"
echo "=========================================="
echo ""

# Step 1: テスト環境準備
echo -e "${YELLOW}Step 1: Preparing test environment${NC}"

# CRITICAL: Kill ALL stale MCP daemon processes from previous runs
# This prevents Coordinator from connecting to an old daemon with wrong database
echo "Killing any stale MCP daemon processes..."
ps aux | grep "mcp-server-pm" | grep -v grep | awk '{print $2}' | xargs -I {} kill -9 {} 2>/dev/null || true
sleep 1

rm -rf "$TEST_DIR"
rm -rf /tmp/uc004
mkdir -p "$TEST_DIR"
mkdir -p "$FRONTEND_WORK_DIR"
mkdir -p "$BACKEND_WORK_DIR"
rm -f "$SHARED_DB_PATH" "$SHARED_DB_PATH-shm" "$SHARED_DB_PATH-wal"
# Remove stale socket and PID files
rm -f "$HOME/Library/Application Support/AIAgentPM/mcp.sock" 2>/dev/null
rm -f "$HOME/Library/Application Support/AIAgentPM/daemon.pid" 2>/dev/null
echo "Test directory: $TEST_DIR"
echo "Working directories (from Project.working_directory):"
echo "  Frontend: $FRONTEND_WORK_DIR"
echo "  Backend: $BACKEND_WORK_DIR"
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

# MCPサーバービルド
swift build --product mcp-server-pm 2>&1 | tail -3 || {
    echo -e "${RED}Failed to build MCP server${NC}"
    exit 1
}
echo "MCP server build complete"

# ソケットパス設定（アプリがデーモンを起動）
SOCKET_PATH="$HOME/Library/Application Support/AIAgentPM/mcp.sock"
rm -f "$SOCKET_PATH" 2>/dev/null
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

# Step 5: Coordinator起動（ソケット待機状態）
# Phase 4アーキテクチャ: Coordinatorが先に起動し、ソケットが作成されるまで待機
echo -e "${YELLOW}Step 5: Starting Coordinator (waits for MCP socket)${NC}"
echo "  Architecture: Phase 4 Coordinator"
echo "  - Coordinator starts FIRST and waits for MCP socket"
echo "  - App will start daemon, Coordinator will connect"
echo "  - Single Coordinator polls list_active_projects_with_agents()"
echo "  - Calls get_agent_action(agent_id, project_id) for each pair"
echo "  - Spawns Agent Instances (Claude Code) as needed"
echo "  Agent: agt_uc004_dev (passkey configured in Coordinator)"
echo ""

# Coordinator設定（単一ファイルで全agentのpasskeyを管理）
cat > /tmp/coordinator_uc004_config.yaml << EOF
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
  agt_uc004_dev:
    passkey: test_passkey_uc004

log_directory: /tmp/coordinator_logs_uc004
EOF

mkdir -p /tmp/coordinator_logs_uc004

# Coordinator起動（--coordinatorフラグでPhase 4モード）
# Coordinatorはソケットが見つかるまで待機する
$PYTHON -m aiagent_runner --coordinator -c /tmp/coordinator_uc004_config.yaml -v > /tmp/uc004_coordinator.log 2>&1 &
COORDINATOR_PID=$!
echo "Coordinator started (PID: $COORDINATOR_PID)"
echo "Coordinator is waiting for MCP socket at: $SOCKET_PATH"

# Coordinatorの起動確認（プロセスが生きているか）
sleep 2
if ! kill -0 "$COORDINATOR_PID" 2>/dev/null; then
    echo -e "${RED}Coordinator failed to start${NC}"
    cat /tmp/uc004_coordinator.log
    exit 1
fi
echo -e "${GREEN}✓ Coordinator is running and waiting for MCP socket${NC}"
echo ""

# Step 6: XCUITest実行（アプリ起動 + MCP自動起動 + シードデータ投入 + ステータス変更 + ファイル待機）
echo -e "${YELLOW}Step 6: Running XCUITest (app + MCP auto-start + seed data + wait for files)${NC}"
echo "  This will:"
echo "    1. Launch app with -UITesting -UITestScenario:UC004"
echo "    2. App auto-starts MCP daemon (Coordinator will connect)"
echo "    3. Seed test data (1 agent assigned to 2 projects)"
echo "    4. Change both task statuses: backlog → todo → in_progress via UI"
echo "    5. Wait for Coordinator to spawn Agent Instances and create files (max 180s)"
echo ""

cd "$PROJECT_ROOT"
xcodebuild test \
    -scheme AIAgentPM \
    -destination "platform=macOS" \
    -only-testing:AIAgentPMUITests/UC004_MultiProjectSameAgentTests/testMultiProjectIntegration_ChangeBothTasksToInProgress \
    2>&1 | tee /tmp/uc004_uitest.log | grep -E "(Test Case|passed|failed|✅|❌|error:)" || true

# テスト結果確認
if grep -q "Test Suite 'UC004_MultiProjectSameAgentTests' passed" /tmp/uc004_uitest.log; then
    echo -e "${GREEN}✓ XCUITest passed - Files were created by Coordinator${NC}"
elif grep -q "passed" /tmp/uc004_uitest.log; then
    echo -e "${GREEN}✓ XCUITest passed${NC}"
else
    echo -e "${RED}✗ XCUITest failed${NC}"
    grep -E "(error:|failed|FAIL)" /tmp/uc004_uitest.log | tail -20
    echo ""
    echo "Coordinator log (last 30 lines):"
    tail -30 /tmp/uc004_coordinator.log 2>/dev/null || echo "(no log)"
    exit 1
fi
echo ""

# Step 7: 結果検証
echo -e "${YELLOW}Step 7: Verifying outputs${NC}"

FRONTEND_CHARS=0
BACKEND_CHARS=0

# フロントエンド検証
if [ -f "$FRONTEND_WORK_DIR/$OUTPUT_FILE" ]; then
    CONTENT=$(cat "$FRONTEND_WORK_DIR/$OUTPUT_FILE")
    FRONTEND_CHARS=$(echo "$CONTENT" | wc -c | tr -d ' ')
    echo "Frontend output: $FRONTEND_CHARS characters"

    # Frontendに関連する内容を含むか
    if echo "$CONTENT" | grep -qi "frontend\|フロントエンド"; then
        echo -e "${GREEN}✓ Frontend output contains project-specific content${NC}"
    fi
else
    echo -e "${RED}✗ Frontend output not found${NC}"
fi

# バックエンド検証
if [ -f "$BACKEND_WORK_DIR/$OUTPUT_FILE" ]; then
    CONTENT=$(cat "$BACKEND_WORK_DIR/$OUTPUT_FILE")
    BACKEND_CHARS=$(echo "$CONTENT" | wc -c | tr -d ' ')
    echo "Backend output: $BACKEND_CHARS characters"

    # Backendに関連する内容を含むか
    if echo "$CONTENT" | grep -qi "backend\|バックエンド"; then
        echo -e "${GREEN}✓ Backend output contains project-specific content${NC}"
    fi
else
    echo -e "${RED}✗ Backend output not found${NC}"
fi
echo ""

# Step 7.5: 実行ログ検証
echo -e "${YELLOW}Step 7.5: Verifying execution logs${NC}"
if [ -f "$SHARED_DB_PATH" ]; then
    EXEC_LOG_COUNT=$(sqlite3 "$SHARED_DB_PATH" "SELECT COUNT(*) FROM execution_logs;" 2>/dev/null || echo "0")
    echo "Execution log records: $EXEC_LOG_COUNT"
    if [ "$EXEC_LOG_COUNT" -gt "0" ]; then
        echo -e "${GREEN}✓ Execution logs created${NC}"
        sqlite3 "$SHARED_DB_PATH" "SELECT id, task_id, agent_id, status FROM execution_logs;" 2>/dev/null
    else
        echo -e "${RED}✗ No execution logs found${NC}"
    fi
else
    echo -e "${YELLOW}DB not found at $SHARED_DB_PATH${NC}"
    EXEC_LOG_COUNT=0
fi
echo ""

# Coordinator ログ表示
echo -e "${YELLOW}Coordinator log (last 30 lines):${NC}"
tail -30 /tmp/uc004_coordinator.log 2>/dev/null || echo "(no log)"
echo ""

# 結果判定
echo "=========================================="
FRONTEND_CREATED=false
BACKEND_CREATED=false

if [ -f "$FRONTEND_WORK_DIR/$OUTPUT_FILE" ]; then
    FRONTEND_CREATED=true
fi
if [ -f "$BACKEND_WORK_DIR/$OUTPUT_FILE" ]; then
    BACKEND_CREATED=true
fi

if [ "$FRONTEND_CREATED" == "true" ] && [ "$BACKEND_CREATED" == "true" ] && [ "$EXEC_LOG_COUNT" -gt "0" ]; then
    echo -e "${GREEN}UC004 App Integration Test: PASSED${NC}"
    echo ""
    echo "Verified (Phase 4 Coordinator Architecture):"
    echo "  ✓ Coordinator started FIRST and waited for MCP socket"
    echo "  ✓ App started MCP daemon, Coordinator connected"
    echo "  ✓ Single Coordinator manages all (agent_id, project_id) pairs"
    echo "  ✓ Same agent (agt_uc004_dev) assigned to both projects"
    echo "  ✓ Coordinator spawned Agent Instances for each pair"
    echo "  ✓ working_directory per task from Project (via MCP)"
    echo "  ✓ Execution logs recorded in DB ($EXEC_LOG_COUNT records)"
    echo "  ✓ Frontend project: $FRONTEND_WORK_DIR ($FRONTEND_CHARS chars)"
    echo "  ✓ Backend project: $BACKEND_WORK_DIR ($BACKEND_CHARS chars)"
    exit 0
elif [ "$FRONTEND_CREATED" == "true" ] && [ "$BACKEND_CREATED" == "true" ]; then
    echo -e "${YELLOW}UC004 App Integration Test: PARTIAL${NC}"
    echo ""
    echo "Files created but execution logs missing ($EXEC_LOG_COUNT records)."
    echo "This indicates get_my_task/report_completed not creating logs."
    exit 1
else
    echo -e "${RED}UC004 App Integration Test: FAILED${NC}"
    echo ""
    echo "Debug info:"
    echo "  - XCUITest log: /tmp/uc004_uitest.log"
    echo "  - Coordinator log: /tmp/uc004_coordinator.log"
    echo "  - Coordinator logs dir: /tmp/coordinator_logs_uc004/"
    echo "  - Shared DB: $SHARED_DB_PATH"
    exit 1
fi
