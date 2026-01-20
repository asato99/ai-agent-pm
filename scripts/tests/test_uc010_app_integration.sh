#!/bin/bash
# UC010 App Integration Test - Chat Timeout Error Display E2E Test
# チャットタイムアウトエラー表示テスト
#
# 設計: 1プロジェクト + 1エージェント（認証失敗用）+ TTL=10秒
# - ユーザーがメッセージを送信
# - エージェントが認証失敗（パスキーなし）
# - TTL経過後にシステムエラーメッセージが表示される
#
# フロー:
#   1. テスト環境準備
#   2. アプリビルド
#   3. MCPサーバービルド
#   4. Runner確認
#   5. Coordinator起動（間違ったパスキーで認証失敗させる）
#   6. XCUITest実行（アプリ起動→MCP自動起動→シードデータ→チャット送信→タイムアウト待機）
#   7. 結果検証（チャットファイルにシステムエラーメッセージ）

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
WORKING_DIR="/tmp/uc010"
CHAT_FILE=".ai-pm/agents/agt_uc010_timeout/chat.jsonl"
TTL_SECONDS=10

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
        rm -f /tmp/uc010_coordinator.log
        rm -f /tmp/uc010_uitest.log
        rm -f /tmp/coordinator_uc010_config.yaml
        rm -rf /tmp/coordinator_logs_uc010
        rm -f "$SHARED_DB_PATH" "$SHARED_DB_PATH-shm" "$SHARED_DB_PATH-wal"
    fi
}

trap 'if [ $? -ne 0 ]; then TEST_FAILED=true; fi; cleanup' EXIT

echo "=========================================="
echo -e "${BLUE}UC010 App Integration Test${NC}"
echo -e "${BLUE}(Chat Timeout Error Display E2E)${NC}"
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
mkdir -p "$WORKING_DIR/.ai-pm/agents/agt_uc010_timeout"
rm -f "$SHARED_DB_PATH" "$SHARED_DB_PATH-shm" "$SHARED_DB_PATH-wal"
rm -f "$HOME/Library/Application Support/AIAgentPM/mcp.sock" 2>/dev/null
rm -f "$HOME/Library/Application Support/AIAgentPM/daemon.pid" 2>/dev/null
echo "Test directory: $WORKING_DIR"
echo "Expected chat file: $WORKING_DIR/$CHAT_FILE"
echo "Shared DB: $SHARED_DB_PATH"
echo "TTL: ${TTL_SECONDS} seconds"
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

# CRITICAL: Copy daemon binary to Application Support
APP_SUPPORT_DIR="$HOME/Library/Application Support/AIAgentPM"
DAEMON_SRC="$PROJECT_ROOT/.build/debug/mcp-server-pm"
DAEMON_DST="$APP_SUPPORT_DIR/mcp-server-pm"
mkdir -p "$APP_SUPPORT_DIR"
echo "Copying daemon binary to Application Support (required for app to start daemon)..."
cp "$DAEMON_SRC" "$DAEMON_DST"
chmod +x "$DAEMON_DST"
echo "Daemon binary copied to: $DAEMON_DST"
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

# Step 5: Coordinator起動（間違ったパスキーで認証失敗させる）
echo -e "${YELLOW}Step 5: Starting Coordinator (with WRONG passkey to cause auth failure)${NC}"
echo "  Architecture: Chat Timeout Error Test"
echo "  - Coordinator starts FIRST and waits for MCP socket"
echo "  - App will start daemon, Coordinator will connect"
echo "  - User sends chat message via UI"
echo "  - Agent starts but authentication FAILS (wrong passkey)"
echo "  - TTL expires (${TTL_SECONDS}s), system error message appears"
echo "  Agent:"
echo "    - agt_uc010_timeout (timeout-test-agent) - NO valid passkey"
echo ""

# Coordinator設定（間違ったパスキー）
cat > /tmp/coordinator_uc010_config.yaml << EOF
# UC010 Coordinator Configuration
polling_interval: 2
max_concurrent: 1

# Phase 5: Coordinator token for authorization
coordinator_token: ${MCP_COORDINATOR_TOKEN}

# MCP socket path
mcp_socket_path: $HOME/Library/Application Support/AIAgentPM/mcp.sock

# AI providers
ai_providers:
  claude:
    cli_command: claude
    cli_args:
      - "--dangerously-skip-permissions"
      - "--max-turns"
      - "5"

# Agents - WRONG passkey to cause authentication failure
agents:
  agt_uc010_timeout:
    passkey: WRONG_PASSKEY_FOR_TIMEOUT_TEST

log_directory: /tmp/coordinator_logs_uc010
EOF

mkdir -p /tmp/coordinator_logs_uc010

# Coordinator起動
$PYTHON -m aiagent_runner --coordinator -c /tmp/coordinator_uc010_config.yaml -v > /tmp/uc010_coordinator.log 2>&1 &
COORDINATOR_PID=$!
echo "Coordinator started (PID: $COORDINATOR_PID)"
echo "Coordinator is waiting for MCP socket at: $HOME/Library/Application Support/AIAgentPM/mcp.sock"

sleep 2
if ! kill -0 "$COORDINATOR_PID" 2>/dev/null; then
    echo -e "${RED}Coordinator failed to start${NC}"
    cat /tmp/uc010_coordinator.log
    exit 1
fi
echo -e "${GREEN}Coordinator is running and waiting for MCP socket${NC}"
echo ""

# Step 6: XCUITest実行
echo -e "${YELLOW}Step 6: Running XCUITest (app + MCP auto-start + seed data + chat + timeout)${NC}"
echo "  This will:"
echo "    1. Launch app with -UITesting -UITestScenario:UC010"
echo "    2. App auto-starts MCP daemon (Coordinator will connect)"
echo "    3. Seed test data (1 project, 1 agent, TTL=${TTL_SECONDS}s)"
echo "    4. Click agent avatar to open chat"
echo "    5. Send message: 'テストメッセージ'"
echo "    6. Wait for TTL to expire (${TTL_SECONDS}s + buffer)"
echo "    7. Verify system error message appears"
echo ""

cd "$PROJECT_ROOT"
xcodebuild test \
    -scheme AIAgentPM \
    -destination "platform=macOS" \
    -only-testing:AIAgentPMUITests/UC010_ChatTimeoutTests/testChatTimeout_ShowsSystemError \
    2>&1 | tee /tmp/uc010_uitest.log | grep -E "(Test Case|passed|failed|Phase|error:)" || true

# テスト結果確認
if grep -q "Test Suite 'UC010_ChatTimeoutTests' passed" /tmp/uc010_uitest.log; then
    echo -e "${GREEN}XCUITest passed - Timeout error displayed${NC}"
elif grep -q "passed" /tmp/uc010_uitest.log; then
    echo -e "${GREEN}XCUITest passed${NC}"
else
    echo -e "${RED}XCUITest failed${NC}"
    grep -E "(error:|failed|FAIL)" /tmp/uc010_uitest.log | tail -20
    echo ""
    echo "Coordinator log (last 30 lines):"
    tail -30 /tmp/uc010_coordinator.log 2>/dev/null || echo "(no log)"
    TEST_FAILED=true
    exit 1
fi
echo ""

# Step 7: 結果検証
echo -e "${YELLOW}Step 7: Verifying outputs${NC}"

# チャットファイル存在確認
FULL_CHAT_PATH="$WORKING_DIR/$CHAT_FILE"
if [ -f "$FULL_CHAT_PATH" ]; then
    echo "chat.jsonl found"
    echo -e "${GREEN}chat.jsonl created${NC}"

    # ユーザーメッセージ確認
    if grep -q '"sender":"user"' "$FULL_CHAT_PATH"; then
        echo -e "${GREEN}  User message recorded${NC}"
    else
        echo -e "${RED}  User message NOT found${NC}"
    fi

    # システムエラーメッセージ確認
    if grep -q '"sender":"system"' "$FULL_CHAT_PATH"; then
        echo -e "${GREEN}  System error message recorded${NC}"
    else
        echo -e "${RED}  System error message NOT found${NC}"
    fi

    # タイムアウトメッセージ確認
    if grep -q 'タイムアウト' "$FULL_CHAT_PATH"; then
        echo -e "${GREEN}  Timeout keyword found in message${NC}"
    else
        echo -e "${RED}  Timeout keyword NOT found${NC}"
    fi

    echo ""
    echo "Chat file contents:"
    cat "$FULL_CHAT_PATH"
else
    echo -e "${RED}chat.jsonl not found at $FULL_CHAT_PATH${NC}"
    echo "Directory contents:"
    ls -la "$WORKING_DIR/.ai-pm/agents/agt_uc010_timeout/" 2>/dev/null || echo "(directory not found)"
fi
echo ""

# Coordinator ログ表示
echo -e "${YELLOW}Coordinator log (last 30 lines):${NC}"
tail -30 /tmp/uc010_coordinator.log 2>/dev/null || echo "(no log)"
echo ""

# 結果判定
echo "=========================================="
echo -e "${YELLOW}Final Result: UC010 Specification Verification${NC}"
echo ""

PASS_COUNT=0
FAIL_COUNT=0

# アサーション確認
check_assertion() {
    local num=$1
    local name=$2
    local result=$3
    if [ "$result" = "true" ]; then
        echo -e "${GREEN}  [$num] $name${NC}"
        PASS_COUNT=$((PASS_COUNT + 1))
    else
        echo -e "${RED}  [$num] $name${NC}"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
}

# 検証項目
V1_CHAT_FILE_EXISTS=false
V2_USER_MESSAGE=false
V3_SYSTEM_ERROR=false
V4_TIMEOUT_KEYWORD=false

if [ -f "$FULL_CHAT_PATH" ]; then
    V1_CHAT_FILE_EXISTS=true
    grep -q '"sender":"user"' "$FULL_CHAT_PATH" && V2_USER_MESSAGE=true
    grep -q '"sender":"system"' "$FULL_CHAT_PATH" && V3_SYSTEM_ERROR=true
    grep -q 'タイムアウト' "$FULL_CHAT_PATH" && V4_TIMEOUT_KEYWORD=true
fi

echo "UC010 Specification (4 assertions):"
check_assertion 1 "Chat file created" "$V1_CHAT_FILE_EXISTS"
check_assertion 2 "User message recorded" "$V2_USER_MESSAGE"
check_assertion 3 "System error message recorded" "$V3_SYSTEM_ERROR"
check_assertion 4 "Timeout keyword in message" "$V4_TIMEOUT_KEYWORD"

echo ""
echo "Result: $PASS_COUNT/4 assertions passed"
echo ""

# 全4項目がパスした場合のみ成功
if [ "$PASS_COUNT" -eq 4 ]; then
    echo -e "${GREEN}UC010 App Integration Test: PASSED${NC}"
    echo ""
    echo "All 4 assertions verified:"
    echo "  Chat file created"
    echo "  User message recorded"
    echo "  System error message recorded"
    echo "  Timeout keyword in message"
    exit 0
else
    echo -e "${RED}UC010 App Integration Test: FAILED${NC}"
    echo ""
    echo "Failed assertions: $FAIL_COUNT/4"
    echo ""
    echo "Debug info:"
    echo "  - XCUITest log: /tmp/uc010_uitest.log"
    echo "  - Coordinator log: /tmp/uc010_coordinator.log"
    echo "  - Coordinator logs dir: /tmp/coordinator_logs_uc010/"
    echo "  - Shared DB: $SHARED_DB_PATH"
    echo "  - Working dir: $WORKING_DIR"
    TEST_FAILED=true
    exit 1
fi
