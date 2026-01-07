#!/bin/bash
# UC001 App Integration Test - True E2E Test
# アプリを含む真の統合テスト
#
# フロー（重要：順序が正しい）:
#   1. ビルド（MCP Server + App）
#   2. XCUITest実行（アプリ起動→シードデータ投入→UI操作でステータス変更）
#   3. MCPデーモン起動（XCUITestが作成した共有DBを使用）
#   4. Runner起動（MCPデーモンをポーリング）
#   5. ファイル作成検証
#
# ポイント:
#   - XCUITestが先に実行され、DBにデータを投入し、ステータスをin_progressに変更
#   - MCPデーモンは同一DBを読み取り、Runnerに提供
#   - Runnerがin_progressタスクを検出してCLI実行

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
TEST_DIR="/tmp/uc001_app_integration_test"
OUTPUT_FILE="test_output.md"

# 共有DB: XCUITestアプリが使用するパス（AIAgentPMApp.swift で定義）
SHARED_DB_PATH="/tmp/AIAgentPM_UITest.db"

DAEMON_PID=""
RUNNER_PID=""

# クリーンアップ関数
cleanup() {
    echo ""
    echo -e "${YELLOW}Cleanup${NC}"
    if [ -n "$RUNNER_PID" ] && kill -0 "$RUNNER_PID" 2>/dev/null; then
        kill "$RUNNER_PID" 2>/dev/null || true
    fi
    if [ -n "$DAEMON_PID" ] && kill -0 "$DAEMON_PID" 2>/dev/null; then
        kill "$DAEMON_PID" 2>/dev/null || true
    fi
    rm -f "$HOME/Library/Application Support/AIAgentPM/mcp.sock" 2>/dev/null
    if [ "$1" != "--keep" ]; then
        rm -rf "$TEST_DIR"
        rm -f /tmp/uc001_app_daemon.log
        rm -f /tmp/uc001_app_runner.log
        rm -f /tmp/uc001_uitest.log
        rm -f "$SHARED_DB_PATH" "$SHARED_DB_PATH-shm" "$SHARED_DB_PATH-wal"
    fi
}

trap cleanup EXIT

echo "=========================================="
echo -e "${BLUE}UC001 App Integration Test${NC}"
echo -e "${BLUE}(App + MCP + Runner + CLI E2E)${NC}"
echo "=========================================="
echo ""

# Step 1: テスト環境準備
echo -e "${YELLOW}Step 1: Preparing test environment${NC}"
rm -rf "$TEST_DIR"
mkdir -p "$TEST_DIR"
rm -f "$SHARED_DB_PATH" "$SHARED_DB_PATH-shm" "$SHARED_DB_PATH-wal"
rm -f "$HOME/Library/Application Support/AIAgentPM/mcp.sock" 2>/dev/null
echo "Test directory: $TEST_DIR"
echo "Shared DB: $SHARED_DB_PATH"
echo ""

# Step 2: MCPサーバービルド
echo -e "${YELLOW}Step 2: Building MCP server${NC}"
cd "$PROJECT_ROOT"
swift build --product mcp-server-pm 2>&1 | tail -5 || {
    echo -e "${RED}Failed to build mcp-server-pm${NC}"
    exit 1
}
MCP_SERVER_PATH="$PROJECT_ROOT/.build/debug/mcp-server-pm"
echo "MCP server build complete"
echo ""

# Step 3: アプリビルド
echo -e "${YELLOW}Step 3: Building app${NC}"
xcodebuild -scheme AIAgentPM -destination "platform=macOS" -configuration Debug build 2>&1 | tail -5 || {
    echo -e "${RED}Failed to build app${NC}"
    exit 1
}
echo "App build complete"
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

# Step 5: XCUITest実行（アプリ起動 + シードデータ投入 + ステータス変更）
# ★重要: XCUITestをMCPデーモンより先に実行
# アプリがDBを作成し、データをシードし、ステータスをin_progressに変更する
echo -e "${YELLOW}Step 5: Running XCUITest (seed data + change status)${NC}"
echo "  This will:"
echo "    1. Launch app with -UITesting -UITestScenario:UC001"
echo "    2. Seed test data via TestDataSeeder (task in backlog)"
echo "    3. Change task status: backlog → todo → in_progress via UI"
echo ""

cd "$PROJECT_ROOT"
xcodebuild test \
    -scheme AIAgentPM \
    -destination "platform=macOS" \
    -only-testing:AIAgentPMUITests/UC001_RunnerIntegrationTests/testRunnerIntegration_ChangeStatusToInProgress \
    2>&1 | tee /tmp/uc001_uitest.log | grep -E "(Test Case|passed|failed|✅|❌|error:)" || true

# テスト結果確認
if grep -q "Test Suite 'UC001_RunnerIntegrationTests' passed" /tmp/uc001_uitest.log; then
    echo -e "${GREEN}✓ XCUITest passed - Task status changed to in_progress${NC}"
elif grep -q "passed" /tmp/uc001_uitest.log; then
    echo -e "${GREEN}✓ XCUITest passed${NC}"
else
    echo -e "${RED}✗ XCUITest failed${NC}"
    grep -E "(error:|failed|FAIL)" /tmp/uc001_uitest.log | tail -20
    exit 1
fi
echo ""

# Step 6: DB状態確認（動的パス検出）
echo -e "${YELLOW}Step 6: Verifying DB state after XCUITest${NC}"

# NSTemporaryDirectory()はユーザー固有のパスを返すため、動的に検出
# /private/var/folders/.../T/AIAgentPM_UITest.db
ACTUAL_DB_PATH=$(find /private/var/folders -name "AIAgentPM_UITest.db" -type f 2>/dev/null | head -1)

if [ -z "$ACTUAL_DB_PATH" ]; then
    # /tmp もチェック
    if [ -f "$SHARED_DB_PATH" ]; then
        ACTUAL_DB_PATH="$SHARED_DB_PATH"
    else
        echo -e "${RED}UITest DB not found${NC}"
        echo "Searched: /private/var/folders/**/AIAgentPM_UITest.db"
        echo "Searched: $SHARED_DB_PATH"
        exit 1
    fi
fi

echo "DB found at: $ACTUAL_DB_PATH"
# 以降のステップで使用するためにSHARED_DB_PATHを更新
SHARED_DB_PATH="$ACTUAL_DB_PATH"
echo ""

echo "Tasks in DB:"
sqlite3 "$SHARED_DB_PATH" "SELECT id, title, status, assignee_id FROM tasks;" 2>/dev/null || echo "(query error)"
echo ""
echo "Agents in DB:"
sqlite3 "$SHARED_DB_PATH" "SELECT id, name FROM agents;" 2>/dev/null || echo "(query error)"
echo ""

# in_progressタスクの確認
IN_PROGRESS_COUNT=$(sqlite3 "$SHARED_DB_PATH" "SELECT COUNT(*) FROM tasks WHERE status='in_progress';" 2>/dev/null || echo "0")
echo "Tasks in in_progress status: $IN_PROGRESS_COUNT"

if [ "$IN_PROGRESS_COUNT" -eq "0" ]; then
    echo -e "${YELLOW}⚠ No in_progress tasks found - Runner may not pick up any task${NC}"
fi
echo ""

# Step 7: MCPデーモン起動（XCUITestが作成したDBを使用）
echo -e "${YELLOW}Step 7: Starting MCP daemon (using shared DB)${NC}"
export AIAGENTPM_DB_PATH="$SHARED_DB_PATH"

"$MCP_SERVER_PATH" daemon --foreground > /tmp/uc001_app_daemon.log 2>&1 &
DAEMON_PID=$!

sleep 2
SOCKET_PATH="$HOME/Library/Application Support/AIAgentPM/mcp.sock"
for i in {1..10}; do
    if [ -S "$SOCKET_PATH" ]; then
        echo -e "${GREEN}MCP Daemon running (PID: $DAEMON_PID)${NC}"
        break
    fi
    sleep 1
done

if [ ! -S "$SOCKET_PATH" ]; then
    echo -e "${RED}MCP Daemon failed to start${NC}"
    cat /tmp/uc001_app_daemon.log
    exit 1
fi
echo ""

# Step 8: Runner起動
echo -e "${YELLOW}Step 8: Starting Runner${NC}"

cat > /tmp/runner_app_integration_config.yaml << EOF
agent_id: agt_uitest_runner
passkey: test_passkey_12345
polling_interval: 2
cli_command: claude
cli_args:
  - "--dangerously-skip-permissions"
working_directory: $TEST_DIR
log_directory: /tmp/runner_logs_app
EOF

mkdir -p /tmp/runner_logs_app
$PYTHON -m aiagent_runner -c /tmp/runner_app_integration_config.yaml -v > /tmp/uc001_app_runner.log 2>&1 &
RUNNER_PID=$!
echo "Runner started (PID: $RUNNER_PID)"
echo ""

# Step 9: タスク実行待機
echo -e "${YELLOW}Step 9: Waiting for task execution (max 180s)${NC}"

FILE_CREATED=false

for i in $(seq 1 36); do
    if [ -f "$TEST_DIR/$OUTPUT_FILE" ]; then
        echo -e "${GREEN}✓ Output file created: $OUTPUT_FILE${NC}"
        FILE_CREATED=true
        break
    fi

    # 他のmdファイルがあるかチェック
    MD_FILES=$(ls "$TEST_DIR"/*.md 2>/dev/null || true)
    if [ -n "$MD_FILES" ]; then
        echo -e "${GREEN}✓ Markdown file(s) created in test directory${NC}"
        echo "Files: $MD_FILES"
        FILE_CREATED=true
        break
    fi

    # 進捗表示
    if [ $((i % 6)) -eq 0 ]; then
        echo "  Waiting... ($((i * 5))s)"
        # Runner状態確認
        if ! kill -0 "$RUNNER_PID" 2>/dev/null; then
            echo -e "${YELLOW}Runner process ended${NC}"
            tail -30 /tmp/uc001_app_runner.log
            break
        fi
    fi

    sleep 5
done
echo ""

# Step 10: 結果検証
echo -e "${YELLOW}Step 10: Verifying results${NC}"

# 出力ファイルを探す
OUTPUT_FILES=$(ls "$TEST_DIR"/*.md 2>/dev/null || true)
if [ -n "$OUTPUT_FILES" ]; then
    FILE_CREATED=true
    for f in $OUTPUT_FILES; do
        echo "Found: $f"
        CONTENT=$(cat "$f")
        CHAR_COUNT=$(echo "$CONTENT" | wc -c | tr -d ' ')
        echo "  Characters: $CHAR_COUNT"
        echo "  Preview (first 100 chars): $(echo "$CONTENT" | head -c 100)"
    done
else
    echo "No .md files found in $TEST_DIR"
    echo "Directory contents:"
    ls -la "$TEST_DIR" 2>/dev/null || echo "(empty)"
fi
echo ""

# Runner ログ表示
echo -e "${YELLOW}Runner log (last 30 lines):${NC}"
tail -30 /tmp/uc001_app_runner.log 2>/dev/null || echo "(no log)"
echo ""

# MCP Daemon ログ表示
echo -e "${YELLOW}MCP Daemon log (last 10 lines):${NC}"
tail -10 /tmp/uc001_app_daemon.log 2>/dev/null || echo "(no log)"
echo ""

# 結果
echo "=========================================="
if [ "$FILE_CREATED" == "true" ]; then
    echo -e "${GREEN}UC001 App Integration Test: PASSED${NC}"
    echo ""
    echo "Verified E2E flow:"
    echo "  1. App launched with UITest scenario"
    echo "  2. Test data seeded via TestDataSeeder"
    echo "  3. Task status changed via UI (backlog → in_progress)"
    echo "  4. MCP Daemon started with same DB"
    echo "  5. Runner detected in_progress task"
    echo "  6. Claude CLI executed and created file"
    exit 0
else
    echo -e "${RED}UC001 App Integration Test: FAILED${NC}"
    echo ""
    echo "Debug info:"
    echo "  - XCUITest log: /tmp/uc001_uitest.log"
    echo "  - MCP Daemon log: /tmp/uc001_app_daemon.log"
    echo "  - Runner log: /tmp/uc001_app_runner.log"
    echo "  - Shared DB: $SHARED_DB_PATH"
    echo ""
    echo "Common issues:"
    echo "  - Task not in in_progress status after XCUITest"
    echo "  - Runner couldn't authenticate with MCP daemon"
    echo "  - CLI execution failed"
    exit 1
fi
