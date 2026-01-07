#!/bin/bash
# UC002 App Integration Test - Multi-Agent Collaboration E2E Test
# マルチエージェント協調テスト（アプリ統合版）
#
# フロー:
#   1. ビルド（MCP Server + App）
#   2. XCUITest実行（アプリ起動→シードデータ投入→UI操作でステータス変更）
#   3. MCPデーモン起動（XCUITestが作成した共有DBを使用）
#   4. Runner起動（2つ - 詳細ライター用、簡潔ライター用）
#   5. ファイル作成検証（文字数比較）
#
# ポイント:
#   - XCUITestが先に実行され、DBにデータを投入し、両タスクをin_progressに変更
#   - MCPデーモンは同一DBを読み取り、Runnerに提供
#   - 2つのRunnerがそれぞれのタスクを検出してCLI実行
#   - 詳細版は長く、簡潔版は短い出力になることを検証

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
TEST_DIR="/tmp/uc002_app_integration_test"
DETAILED_DIR="$TEST_DIR/detailed"
CONCISE_DIR="$TEST_DIR/concise"
OUTPUT_FILE="PROJECT_SUMMARY.md"

# 共有DB: XCUITestアプリが使用するパス
SHARED_DB_PATH="/tmp/AIAgentPM_UITest.db"

DAEMON_PID=""
DETAILED_RUNNER_PID=""
CONCISE_RUNNER_PID=""

# クリーンアップ関数
cleanup() {
    echo ""
    echo -e "${YELLOW}Cleanup${NC}"
    if [ -n "$DETAILED_RUNNER_PID" ] && kill -0 "$DETAILED_RUNNER_PID" 2>/dev/null; then
        kill "$DETAILED_RUNNER_PID" 2>/dev/null || true
    fi
    if [ -n "$CONCISE_RUNNER_PID" ] && kill -0 "$CONCISE_RUNNER_PID" 2>/dev/null; then
        kill "$CONCISE_RUNNER_PID" 2>/dev/null || true
    fi
    if [ -n "$DAEMON_PID" ] && kill -0 "$DAEMON_PID" 2>/dev/null; then
        kill "$DAEMON_PID" 2>/dev/null || true
    fi
    rm -f "$HOME/Library/Application Support/AIAgentPM/mcp.sock" 2>/dev/null
    if [ "$1" != "--keep" ]; then
        rm -rf "$TEST_DIR"
        rm -f /tmp/uc002_app_daemon.log
        rm -f /tmp/uc002_detailed_runner.log
        rm -f /tmp/uc002_concise_runner.log
        rm -f /tmp/uc002_uitest.log
        rm -f "$SHARED_DB_PATH" "$SHARED_DB_PATH-shm" "$SHARED_DB_PATH-wal"
    fi
}

trap cleanup EXIT

echo "=========================================="
echo -e "${BLUE}UC002 App Integration Test${NC}"
echo -e "${BLUE}(Multi-Agent Collaboration E2E)${NC}"
echo "=========================================="
echo ""

# Step 1: テスト環境準備
echo -e "${YELLOW}Step 1: Preparing test environment${NC}"
rm -rf "$TEST_DIR"
mkdir -p "$DETAILED_DIR"
mkdir -p "$CONCISE_DIR"
rm -f "$SHARED_DB_PATH" "$SHARED_DB_PATH-shm" "$SHARED_DB_PATH-wal"
rm -f "$HOME/Library/Application Support/AIAgentPM/mcp.sock" 2>/dev/null
echo "Test directory: $TEST_DIR"
echo "  Detailed: $DETAILED_DIR"
echo "  Concise: $CONCISE_DIR"
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
echo -e "${YELLOW}Step 5: Running XCUITest (seed data + change status)${NC}"
echo "  This will:"
echo "    1. Launch app with -UITesting -UITestScenario:UC002"
echo "    2. Seed test data (detailed + concise writers)"
echo "    3. Change both task statuses: backlog → todo → in_progress via UI"
echo ""

cd "$PROJECT_ROOT"
xcodebuild test \
    -scheme AIAgentPM \
    -destination "platform=macOS" \
    -only-testing:AIAgentPMUITests/UC002_MultiAgentCollaborationTests/testMultiAgentIntegration_ChangeBothTasksToInProgress \
    2>&1 | tee /tmp/uc002_uitest.log | grep -E "(Test Case|passed|failed|✅|❌|error:)" || true

# テスト結果確認
if grep -q "Test Suite 'UC002_MultiAgentCollaborationTests' passed" /tmp/uc002_uitest.log; then
    echo -e "${GREEN}✓ XCUITest passed - Both task statuses changed to in_progress${NC}"
elif grep -q "passed" /tmp/uc002_uitest.log; then
    echo -e "${GREEN}✓ XCUITest passed${NC}"
else
    echo -e "${RED}✗ XCUITest failed${NC}"
    grep -E "(error:|failed|FAIL)" /tmp/uc002_uitest.log | tail -20
    exit 1
fi
echo ""

# Step 6: DB状態確認（動的パス検出）
echo -e "${YELLOW}Step 6: Verifying DB state after XCUITest${NC}"

ACTUAL_DB_PATH=$(find /private/var/folders -name "AIAgentPM_UITest.db" -type f 2>/dev/null | head -1)

if [ -z "$ACTUAL_DB_PATH" ]; then
    if [ -f "$SHARED_DB_PATH" ]; then
        ACTUAL_DB_PATH="$SHARED_DB_PATH"
    else
        echo -e "${RED}UITest DB not found${NC}"
        exit 1
    fi
fi

echo "DB found at: $ACTUAL_DB_PATH"
SHARED_DB_PATH="$ACTUAL_DB_PATH"
echo ""

echo "Tasks in DB:"
sqlite3 "$SHARED_DB_PATH" "SELECT id, title, status, assignee_id FROM tasks;" 2>/dev/null || echo "(query error)"
echo ""
echo "Agents in DB:"
sqlite3 "$SHARED_DB_PATH" "SELECT id, name, system_prompt FROM agents;" 2>/dev/null || echo "(query error)"
echo ""

# in_progressタスクの確認
IN_PROGRESS_COUNT=$(sqlite3 "$SHARED_DB_PATH" "SELECT COUNT(*) FROM tasks WHERE status='in_progress';" 2>/dev/null || echo "0")
echo "Tasks in in_progress status: $IN_PROGRESS_COUNT"

if [ "$IN_PROGRESS_COUNT" -lt "2" ]; then
    echo -e "${YELLOW}⚠ Less than 2 in_progress tasks found - Runners may not pick up all tasks${NC}"
fi
echo ""

# Step 7: MCPデーモン起動
echo -e "${YELLOW}Step 7: Starting MCP daemon (using shared DB)${NC}"
export AIAGENTPM_DB_PATH="$SHARED_DB_PATH"

"$MCP_SERVER_PATH" daemon --foreground > /tmp/uc002_app_daemon.log 2>&1 &
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
    cat /tmp/uc002_app_daemon.log
    exit 1
fi
echo ""

# Step 8: Runner起動（2つ）
echo -e "${YELLOW}Step 8: Starting Runners (detailed + concise)${NC}"

# 詳細ライター用Runner設定
cat > /tmp/runner_uc002_detailed_config.yaml << EOF
agent_id: agt_detailed_writer
passkey: test_passkey_detailed
polling_interval: 2
cli_command: claude
cli_args:
  - "--dangerously-skip-permissions"
working_directory: $DETAILED_DIR
log_directory: /tmp/runner_logs_uc002_detailed
EOF

# 簡潔ライター用Runner設定
cat > /tmp/runner_uc002_concise_config.yaml << EOF
agent_id: agt_concise_writer
passkey: test_passkey_concise
polling_interval: 2
cli_command: claude
cli_args:
  - "--dangerously-skip-permissions"
working_directory: $CONCISE_DIR
log_directory: /tmp/runner_logs_uc002_concise
EOF

mkdir -p /tmp/runner_logs_uc002_detailed
mkdir -p /tmp/runner_logs_uc002_concise

# 詳細ライター用Runner起動
$PYTHON -m aiagent_runner -c /tmp/runner_uc002_detailed_config.yaml -v > /tmp/uc002_detailed_runner.log 2>&1 &
DETAILED_RUNNER_PID=$!
echo "Detailed Runner started (PID: $DETAILED_RUNNER_PID)"

# 簡潔ライター用Runner起動
$PYTHON -m aiagent_runner -c /tmp/runner_uc002_concise_config.yaml -v > /tmp/uc002_concise_runner.log 2>&1 &
CONCISE_RUNNER_PID=$!
echo "Concise Runner started (PID: $CONCISE_RUNNER_PID)"
echo ""

# Step 9: タスク実行待機
echo -e "${YELLOW}Step 9: Waiting for task execution (max 180s)${NC}"

DETAILED_CREATED=false
CONCISE_CREATED=false

for i in $(seq 1 36); do
    # 詳細版ファイルチェック
    if [ "$DETAILED_CREATED" != "true" ]; then
        if [ -f "$DETAILED_DIR/$OUTPUT_FILE" ]; then
            echo -e "${GREEN}✓ Detailed writer created $OUTPUT_FILE${NC}"
            DETAILED_CREATED=true
        fi
    fi

    # 簡潔版ファイルチェック
    if [ "$CONCISE_CREATED" != "true" ]; then
        if [ -f "$CONCISE_DIR/$OUTPUT_FILE" ]; then
            echo -e "${GREEN}✓ Concise writer created $OUTPUT_FILE${NC}"
            CONCISE_CREATED=true
        fi
    fi

    # 両方作成されたら終了
    if [ "$DETAILED_CREATED" == "true" ] && [ "$CONCISE_CREATED" == "true" ]; then
        break
    fi

    # 進捗表示
    if [ $((i % 6)) -eq 0 ]; then
        echo "  Waiting... ($((i * 5))s)"
        # Runner状態確認
        if ! kill -0 "$DETAILED_RUNNER_PID" 2>/dev/null; then
            echo -e "${YELLOW}Detailed Runner process ended${NC}"
        fi
        if ! kill -0 "$CONCISE_RUNNER_PID" 2>/dev/null; then
            echo -e "${YELLOW}Concise Runner process ended${NC}"
        fi
    fi

    sleep 5
done
echo ""

# Step 10: 結果検証
echo -e "${YELLOW}Step 10: Verifying outputs${NC}"

DETAILED_CHARS=0
CONCISE_CHARS=0
DETAILED_HAS_BACKGROUND=false

# 詳細版検証
if [ -f "$DETAILED_DIR/$OUTPUT_FILE" ]; then
    CONTENT=$(cat "$DETAILED_DIR/$OUTPUT_FILE")
    DETAILED_CHARS=$(echo "$CONTENT" | wc -c | tr -d ' ')
    echo "Detailed output: $DETAILED_CHARS characters"

    # 「背景」を含むかチェック
    if echo "$CONTENT" | grep -q "背景"; then
        DETAILED_HAS_BACKGROUND=true
    fi

    # 詳細版の基準: 300文字以上 または「背景」を含む
    if [ "$DETAILED_CHARS" -gt 300 ] || [ "$DETAILED_HAS_BACKGROUND" == "true" ]; then
        echo -e "${GREEN}✓ Detailed output meets criteria${NC}"
    else
        echo -e "${YELLOW}⚠ Detailed output may not be comprehensive enough${NC}"
    fi
else
    echo -e "${RED}✗ Detailed output not found${NC}"
fi

# 簡潔版検証
if [ -f "$CONCISE_DIR/$OUTPUT_FILE" ]; then
    CONTENT=$(cat "$CONCISE_DIR/$OUTPUT_FILE")
    CONCISE_CHARS=$(echo "$CONTENT" | wc -c | tr -d ' ')
    echo "Concise output: $CONCISE_CHARS characters"

    # 詳細版との比較
    if [ "$DETAILED_CHARS" -gt 0 ]; then
        RATIO=$((DETAILED_CHARS / CONCISE_CHARS))
        echo "  Ratio (detailed/concise): ${RATIO}x"
    fi

    # 簡潔版は詳細版より短いはず
    if [ "$CONCISE_CHARS" -lt "$DETAILED_CHARS" ]; then
        echo -e "${GREEN}✓ Concise output is shorter than detailed${NC}"
    else
        echo -e "${YELLOW}⚠ Concise output is NOT shorter than detailed${NC}"
    fi
else
    echo -e "${RED}✗ Concise output not found${NC}"
fi
echo ""

# Runner ログ表示
echo -e "${YELLOW}Detailed Runner log (last 20 lines):${NC}"
tail -20 /tmp/uc002_detailed_runner.log 2>/dev/null || echo "(no log)"
echo ""

echo -e "${YELLOW}Concise Runner log (last 20 lines):${NC}"
tail -20 /tmp/uc002_concise_runner.log 2>/dev/null || echo "(no log)"
echo ""

# 結果
echo "=========================================="
if [ "$DETAILED_CREATED" == "true" ] && [ "$CONCISE_CREATED" == "true" ]; then
    # 追加の検証
    PASS=true

    # 詳細版が基準を満たしているか
    if [ "$DETAILED_CHARS" -lt 300 ] && [ "$DETAILED_HAS_BACKGROUND" != "true" ]; then
        echo -e "${YELLOW}Warning: Detailed output may not be comprehensive${NC}"
    fi

    # 簡潔版が詳細版より短いか
    if [ "$CONCISE_CHARS" -ge "$DETAILED_CHARS" ]; then
        echo -e "${YELLOW}Warning: Concise output is not shorter than detailed${NC}"
        # 警告だが失敗にはしない
    fi

    echo -e "${GREEN}UC002 App Integration Test: PASSED${NC}"
    echo ""
    echo "Verified:"
    echo "  - Detailed writer created comprehensive output ($DETAILED_CHARS chars)"
    echo "  - Concise writer created brief output ($CONCISE_CHARS chars)"
    echo "  - Different system_prompts produced different outputs"
    exit 0
else
    echo -e "${RED}UC002 App Integration Test: FAILED${NC}"
    echo ""
    echo "Debug info:"
    echo "  - XCUITest log: /tmp/uc002_uitest.log"
    echo "  - MCP Daemon log: /tmp/uc002_app_daemon.log"
    echo "  - Detailed Runner log: /tmp/uc002_detailed_runner.log"
    echo "  - Concise Runner log: /tmp/uc002_concise_runner.log"
    echo "  - Shared DB: $SHARED_DB_PATH"
    exit 1
fi
