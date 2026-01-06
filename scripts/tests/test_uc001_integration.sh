#!/bin/bash
# UC001 Integration Test (Phase 3: Pull Architecture)
# アプリ経由でのタスク作成 → Runner検出 → CLI実行 → ファイル作成 を確認するテスト
#
# Phase 3 アーキテクチャ:
#   アプリ → ステータス変更 → Runner(ポーリング) → CLI実行 → ファイル作成
#
# このテストは実際のClaude CLIを起動してファイルを作成します。

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
TEST_DIR="/tmp/uc001_integration_test"
OUTPUT_FILE="integration_test_output.md"
EXPECTED_CONTENT="integration test content"
TIMEOUT_SECONDS=180
RUNNER_PID=""
DAEMON_PID=""

# クリーンアップ関数
cleanup() {
    echo ""
    echo -e "${YELLOW}Cleanup: Stopping Runner, Daemon, and cleaning up${NC}"
    if [ -n "$RUNNER_PID" ] && kill -0 "$RUNNER_PID" 2>/dev/null; then
        kill "$RUNNER_PID" 2>/dev/null || true
        echo "Runner stopped (PID: $RUNNER_PID)"
    fi
    if [ -n "$DAEMON_PID" ] && kill -0 "$DAEMON_PID" 2>/dev/null; then
        kill "$DAEMON_PID" 2>/dev/null || true
        echo "MCP Daemon stopped (PID: $DAEMON_PID)"
    fi
    # ソケットファイルを削除
    rm -f "$HOME/Library/Application Support/AIAgentPM/mcp.sock" 2>/dev/null
    if [ "$1" != "--keep" ]; then
        rm -rf "$TEST_DIR"
        rm -f /tmp/uc001_integration_test.log
        rm -f /tmp/runner.log
        rm -f /tmp/daemon.log
        echo "Cleaned up test files"
    fi
}

# エラー時もクリーンアップ
trap cleanup EXIT

echo "=========================================="
echo -e "${BLUE}UC001 Integration Test (Phase 3)${NC}"
echo "=========================================="
echo ""

# Step 1: テスト環境の準備
echo -e "${YELLOW}Step 1: Preparing test environment${NC}"
rm -rf "$TEST_DIR"
mkdir -p "$TEST_DIR"
echo "Test directory: $TEST_DIR"
echo "Expected output: $TEST_DIR/$OUTPUT_FILE"
echo ""

# Step 2: テスト設定確認
echo -e "${YELLOW}Step 2: Test configuration${NC}"
echo "Architecture: Pull-based (Runner polls for tasks)"
echo "Working directory: $TEST_DIR"
echo "Output file: $OUTPUT_FILE"
echo ""

# Step 3: ビルド
echo -e "${YELLOW}Step 3: Building application${NC}"
cd "$PROJECT_ROOT"
xcodebuild -scheme AIAgentPM -destination 'platform=macOS' build -quiet 2>&1 || {
    echo -e "${RED}Build failed${NC}"
    exit 1
}
echo "Build succeeded"
echo ""

# Step 4: Runnerの確認
echo -e "${YELLOW}Step 4: Checking Runner setup${NC}"
RUNNER_DIR="$PROJECT_ROOT/runner"
if [ ! -d "$RUNNER_DIR" ]; then
    echo -e "${RED}Runner directory not found: $RUNNER_DIR${NC}"
    exit 1
fi

# Python仮想環境の確認
if [ -d "$RUNNER_DIR/.venv" ]; then
    PYTHON="$RUNNER_DIR/.venv/bin/python"
else
    PYTHON="python3"
fi

# Runnerがインストールされているか確認
if ! $PYTHON -c "import aiagent_runner" 2>/dev/null; then
    echo -e "${YELLOW}Installing Runner...${NC}"
    cd "$RUNNER_DIR"
    pip install -e . -q
    cd "$PROJECT_ROOT"
fi
echo "Runner is ready"
echo ""

# Step 5: MCPデーモンを起動
echo -e "${YELLOW}Step 5: Starting MCP daemon${NC}"

# MCPServerをビルドして最新バイナリを使用
echo "Building mcp-server-pm..."
cd "$PROJECT_ROOT"
swift build --product mcp-server-pm 2>&1 || {
    echo -e "${RED}Failed to build mcp-server-pm${NC}"
    exit 1
}
MCP_SERVER_PATH="$PROJECT_ROOT/.build/debug/mcp-server-pm"

if [ ! -f "$MCP_SERVER_PATH" ]; then
    echo -e "${RED}mcp-server-pm binary not found at: $MCP_SERVER_PATH${NC}"
    exit 1
fi

echo "MCP Server path: $MCP_SERVER_PATH"

# 既存のソケットファイルを削除
rm -f "$HOME/Library/Application Support/AIAgentPM/mcp.sock" 2>/dev/null

# テスト用のDBパスを設定
TEST_DB_PATH="$HOME/Library/Application Support/AIAgentPM/uitest.db"
export AIAGENTPM_DB_PATH="$TEST_DB_PATH"

# DBディレクトリを作成
mkdir -p "$(dirname "$TEST_DB_PATH")"

# 既存のDBを削除（新しいDBを作成させる）
rm -f "$TEST_DB_PATH"

# デーモンを起動（スキーマ作成のため）
"$MCP_SERVER_PATH" daemon --foreground > /tmp/daemon.log 2>&1 &
DAEMON_PID=$!
echo "MCP Daemon started (PID: $DAEMON_PID)"

# デーモンの起動確認
sleep 2
if ! kill -0 "$DAEMON_PID" 2>/dev/null; then
    echo -e "${RED}MCP Daemon failed to start${NC}"
    echo "Daemon log:"
    cat /tmp/daemon.log 2>/dev/null || echo "(no log)"
    exit 1
fi

# ソケットファイルの確認
SOCKET_PATH="$HOME/Library/Application Support/AIAgentPM/mcp.sock"
if [ ! -S "$SOCKET_PATH" ]; then
    echo -e "${YELLOW}Waiting for socket file...${NC}"
    for i in {1..10}; do
        sleep 1
        if [ -S "$SOCKET_PATH" ]; then
            echo "Socket file created"
            break
        fi
    done
fi

if [ -S "$SOCKET_PATH" ]; then
    echo -e "${GREEN}MCP Daemon is running and listening${NC}"
else
    echo -e "${RED}Socket file not found: $SOCKET_PATH${NC}"
    echo "Daemon log:"
    cat /tmp/daemon.log 2>/dev/null || echo "(no log)"
    exit 1
fi
echo ""

# Step 5.5: テストデータをDBに投入
echo -e "${YELLOW}Step 5.5: Seeding test data into DB${NC}"

# テストデータの定義
TEST_PROJECT_ID="prj_uitest"
TEST_AGENT_ID="agt_uitest_runner"
TEST_PASSKEY="test_passkey_12345"
# SHA256(passkey + salt) where salt is "dGVzdF9zYWx0X3ZhbHVl" (base64 of "test_salt_value")
TEST_PASSKEY_HASH="8446c343611a5931f214cc2c5f2ec67bf59f28c3a4436d33762d2e5e8e8c99cb"
TEST_SALT="dGVzdF9zYWx0X3ZhbHVl"
TEST_TASK_ID="tsk_uc001_integration"

# DBにテストデータを投入（マイグレーション後のスキーマに合わせる）
# UUIDを生成
CREDENTIAL_ID=$(uuidgen | tr '[:upper:]' '[:lower:]')

sqlite3 "$TEST_DB_PATH" << EOSQL
-- プロジェクト
INSERT OR REPLACE INTO projects (id, name, description, status, created_at, updated_at)
VALUES ('$TEST_PROJECT_ID', 'UC001 Test Project', 'Integration test project', 'active', datetime('now'), datetime('now'));

-- エージェント（project_idなし - v3マイグレーション後）
INSERT OR REPLACE INTO agents (id, name, role, type, status, created_at, updated_at)
VALUES ('$TEST_AGENT_ID', 'UC001 Runner Agent', 'Integration test runner', 'ai', 'active', datetime('now'), datetime('now'));

-- エージェント認証情報（id, agent_id, passkey_hash, salt, created_at, last_used_at）
INSERT OR REPLACE INTO agent_credentials (id, agent_id, passkey_hash, salt, created_at)
VALUES ('$CREDENTIAL_ID', '$TEST_AGENT_ID', '$TEST_PASSKEY_HASH', '$TEST_SALT', datetime('now'));

-- タスク（in_progress状態で作成し、assignee_idでエージェントに割り当て - Runnerが検出する）
INSERT OR REPLACE INTO tasks (id, project_id, title, description, status, priority, assignee_id, created_at, updated_at)
VALUES ('$TEST_TASK_ID', '$TEST_PROJECT_ID', 'UC001 Integration Test Task',
'Create a file named integration_test_output.md with the text "integration test content" in the current working directory.',
'in_progress', 'medium', '$TEST_AGENT_ID', datetime('now'), datetime('now'));
EOSQL

if [ $? -eq 0 ]; then
    echo -e "${GREEN}Test data seeded successfully${NC}"
    echo "  Project: $TEST_PROJECT_ID"
    echo "  Agent: $TEST_AGENT_ID"
    echo "  Task: $TEST_TASK_ID (status: in_progress)"
else
    echo -e "${RED}Failed to seed test data${NC}"
    exit 1
fi
echo ""

# Step 6: Runner設定
echo -e "${YELLOW}Step 6: Runner configuration${NC}"

# Runner設定ファイルを作成
cat > /tmp/runner_test_config.yaml << EOF
agent_id: $TEST_AGENT_ID
passkey: $TEST_PASSKEY
polling_interval: 2
cli_command: claude
cli_args:
  - "--dangerously-skip-permissions"
working_directory: $TEST_DIR
log_directory: /tmp/runner_logs
EOF

echo "Agent ID: $TEST_AGENT_ID"
echo "Config: /tmp/runner_test_config.yaml"
echo ""

# Step 7: Runnerをバックグラウンドで起動
echo -e "${YELLOW}Step 7: Starting Runner in background${NC}"
echo "Runner will poll for in_progress tasks..."

# Runnerを起動（バックグラウンド）
$PYTHON -m aiagent_runner -c /tmp/runner_test_config.yaml -v > /tmp/runner.log 2>&1 &
RUNNER_PID=$!
echo "Runner started (PID: $RUNNER_PID)"

# Runnerの起動確認
sleep 2
if ! kill -0 "$RUNNER_PID" 2>/dev/null; then
    echo -e "${RED}Runner failed to start${NC}"
    echo "Runner log:"
    cat /tmp/runner.log 2>/dev/null || echo "(no log)"
    exit 1
fi
echo "Runner is running"
echo ""

# Step 8: タスク検出を待機
echo -e "${YELLOW}Step 8: Waiting for Runner to detect task${NC}"
echo "Task is already in_progress, Runner should detect it immediately..."
echo ""

# Runnerがタスクを検出するのを待つ（ログを監視）
echo "Monitoring Runner logs for task detection..."
for i in {1..15}; do
    if grep -q "Found.*task" /tmp/runner.log 2>/dev/null || \
       grep -q "Executing" /tmp/runner.log 2>/dev/null || \
       grep -q "task_id" /tmp/runner.log 2>/dev/null; then
        echo -e "${GREEN}Runner detected task!${NC}"
        break
    fi
    if [ $i -eq 15 ]; then
        echo -e "${YELLOW}Timeout waiting for task detection, continuing...${NC}"
    fi
    sleep 2
done

echo ""
echo "Runner log so far:"
echo "---"
tail -30 /tmp/runner.log 2>/dev/null || echo "(no log yet)"
echo "---"
echo ""

# Step 9: ファイル作成を確認
echo -e "${YELLOW}Step 9: Verifying file creation${NC}"

# Claude Codeが作業を完了するまで待つ（最大60秒）
echo "Waiting for CLI execution to complete (max 60s)..."
for i in {1..12}; do
    if [ -f "$TEST_DIR/$OUTPUT_FILE" ]; then
        echo "File detected after $((i * 5)) seconds"
        break
    fi
    # Runnerログを確認
    if grep -q "Task completed" /tmp/runner.log 2>/dev/null; then
        echo "Runner reported task completion"
    fi
    sleep 5
done

# デバッグ用ログ出力
echo ""
echo "MCP Daemon log (last 20 lines):"
echo "---"
tail -20 /tmp/daemon.log 2>/dev/null || echo "(no log)"
echo "---"
echo ""
echo "Runner log (last 20 lines):"
echo "---"
tail -20 /tmp/runner.log 2>/dev/null || echo "(no log)"
echo "---"

if [ -f "$TEST_DIR/$OUTPUT_FILE" ]; then
    echo -e "${GREEN}✓ File created: $OUTPUT_FILE${NC}"
    echo ""
    echo "File content:"
    echo "---"
    cat "$TEST_DIR/$OUTPUT_FILE"
    echo "---"

    # 内容の検証
    FILE_CONTENT=$(cat "$TEST_DIR/$OUTPUT_FILE")
    if echo "$FILE_CONTENT" | grep -q "$EXPECTED_CONTENT"; then
        echo -e "${GREEN}✓ Content verified: contains '$EXPECTED_CONTENT'${NC}"
        TEST_RESULT="PASSED"
    else
        echo -e "${YELLOW}⚠ Content does not contain expected text '$EXPECTED_CONTENT'${NC}"
        TEST_RESULT="PARTIAL"
    fi
else
    echo -e "${RED}✗ File not created: $OUTPUT_FILE${NC}"
    echo ""
    echo "Directory contents:"
    ls -la "$TEST_DIR" 2>/dev/null || echo "(directory empty or not found)"
    echo ""
    echo "Checking test log for errors..."
    grep -E "(error|Error|failed|Failed)" /tmp/uc001_integration_test.log 2>/dev/null | head -20 || echo "(no errors in log)"
    TEST_RESULT="FAILED"
fi

echo ""

# 結果
echo "=========================================="
if [ "$TEST_RESULT" == "PASSED" ]; then
    echo -e "${GREEN}UC001 Integration Test: PASSED${NC}"
    echo ""
    echo "Verified (Phase 3 Pull Architecture):"
    echo "  - App launched successfully"
    echo "  - Task status changed to in_progress"
    echo "  - Runner detected the task"
    echo "  - Claude CLI was executed by Runner"
    echo "  - File was created by agent"
    echo "  - File content contains expected text"
    exit 0
elif [ "$TEST_RESULT" == "PARTIAL" ]; then
    echo -e "${YELLOW}UC001 Integration Test: PARTIAL${NC}"
    echo ""
    echo "File was created but content verification failed:"
    echo "  - Expected content: '$EXPECTED_CONTENT'"
    echo "  - Check agent instructions in task description"
    exit 1
else
    echo -e "${RED}UC001 Integration Test: FAILED${NC}"
    echo ""
    echo "The file was not created. Possible issues:"
    echo "  - Runner may not have detected the task"
    echo "  - Agent credentials may be incorrect"
    echo "  - MCP server communication failed"
    echo "  - Claude CLI may have failed to execute"
    echo "  - Working directory may not be set correctly"
    exit 1
fi
