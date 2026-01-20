#!/bin/bash
# UC009 App Integration Test - Agent Chat Communication E2E Test
# エージェントとのチャット通信テスト
#
# 設計: 1プロジェクト + 1エージェント（チャット応答用）
# - ユーザーがメッセージを送信
# - エージェントが名前を含む応答を返す
#
# フロー:
#   1. テスト環境準備
#   2. アプリビルド
#   3. MCPサーバービルド
#   4. Runner確認
#   5. Coordinator起動（ソケット待機状態で起動）
#   6. XCUITest実行（アプリ起動→MCP自動起動→シードデータ→チャット送信→応答待機）
#   7. 結果検証（チャットファイル）

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
WORKING_DIR="/tmp/uc009"
CHAT_FILE=".ai-pm/agents/agt_uc009_chat/chat.jsonl"

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
        rm -f /tmp/uc009_coordinator.log
        rm -f /tmp/uc009_uitest.log
        rm -f /tmp/coordinator_uc009_config.yaml
        rm -rf /tmp/coordinator_logs_uc009
        rm -f "$SHARED_DB_PATH" "$SHARED_DB_PATH-shm" "$SHARED_DB_PATH-wal"
    fi
}

trap 'if [ $? -ne 0 ]; then TEST_FAILED=true; fi; cleanup' EXIT

echo "=========================================="
echo -e "${BLUE}UC009 App Integration Test${NC}"
echo -e "${BLUE}(Agent Chat Communication E2E)${NC}"
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
mkdir -p "$WORKING_DIR/.ai-pm/agents/agt_uc009_chat"
rm -f "$SHARED_DB_PATH" "$SHARED_DB_PATH-shm" "$SHARED_DB_PATH-wal"
rm -f "$HOME/Library/Application Support/AIAgentPM/mcp.sock" 2>/dev/null
rm -f "$HOME/Library/Application Support/AIAgentPM/daemon.pid" 2>/dev/null
echo "Test directory: $WORKING_DIR"
echo "Expected chat file: $WORKING_DIR/$CHAT_FILE"
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

# CRITICAL: Copy daemon binary to Application Support
# This works around a macOS issue where file access to .build directory blocks
# when the app is running (dyld blocking issue)
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

# Step 5: Coordinator起動
echo -e "${YELLOW}Step 5: Starting Coordinator (waits for MCP socket)${NC}"
echo "  Architecture: Chat Communication Test"
echo "  - Coordinator starts FIRST and waits for MCP socket"
echo "  - App will start daemon, Coordinator will connect"
echo "  - User sends chat message via UI"
echo "  - Agent starts with purpose=chat"
echo "  - Agent responds with its name"
echo "  Agent:"
echo "    - agt_uc009_chat (chat-responder)"
echo ""

# Coordinator設定
cat > /tmp/coordinator_uc009_config.yaml << EOF
# UC009 Coordinator Configuration
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
      - "10"

# Agents
agents:
  agt_uc009_chat:
    passkey: test_passkey_uc009_chat

log_directory: /tmp/coordinator_logs_uc009
EOF

mkdir -p /tmp/coordinator_logs_uc009

# Coordinator起動
$PYTHON -m aiagent_runner --coordinator -c /tmp/coordinator_uc009_config.yaml -v > /tmp/uc009_coordinator.log 2>&1 &
COORDINATOR_PID=$!
echo "Coordinator started (PID: $COORDINATOR_PID)"
echo "Coordinator is waiting for MCP socket at: $HOME/Library/Application Support/AIAgentPM/mcp.sock"

sleep 2
if ! kill -0 "$COORDINATOR_PID" 2>/dev/null; then
    echo -e "${RED}Coordinator failed to start${NC}"
    cat /tmp/uc009_coordinator.log
    exit 1
fi
echo -e "${GREEN}Coordinator is running and waiting for MCP socket${NC}"
echo ""

# Step 6: XCUITest実行
echo -e "${YELLOW}Step 6: Running XCUITest (app + MCP auto-start + seed data + chat)${NC}"
echo "  This will:"
echo "    1. Launch app with -UITesting -UITestScenario:UC009"
echo "    2. App auto-starts MCP daemon (Coordinator will connect)"
echo "    3. Seed test data (1 project, 1 agent)"
echo "    4. Click agent avatar to open chat"
echo "    5. Send message: 'あなたの名前を教えてください'"
echo "    6. Wait for agent response containing 'chat-responder' (max 60s)"
echo ""

cd "$PROJECT_ROOT"
xcodebuild test \
    -scheme AIAgentPM \
    -destination "platform=macOS" \
    -only-testing:AIAgentPMUITests/UC009_ChatCommunicationTests/testChatWithAgent_AskName \
    2>&1 | tee /tmp/uc009_uitest.log | grep -E "(Test Case|passed|failed|Phase|error:)" || true

# テスト結果確認
if grep -q "Test Suite 'UC009_ChatCommunicationTests' passed" /tmp/uc009_uitest.log; then
    echo -e "${GREEN}XCUITest passed - Chat communication completed${NC}"
elif grep -q "passed" /tmp/uc009_uitest.log; then
    echo -e "${GREEN}XCUITest passed${NC}"
else
    echo -e "${RED}XCUITest failed${NC}"
    grep -E "(error:|failed|FAIL)" /tmp/uc009_uitest.log | tail -20
    echo ""
    echo "Coordinator log (last 30 lines):"
    tail -30 /tmp/uc009_coordinator.log 2>/dev/null || echo "(no log)"
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

    # エージェント応答確認
    if grep -q '"sender":"agent"' "$FULL_CHAT_PATH"; then
        echo -e "${GREEN}  Agent response recorded${NC}"
    else
        echo -e "${RED}  Agent response NOT found${NC}"
    fi

    echo ""
    echo "Chat file contents:"
    cat "$FULL_CHAT_PATH"
else
    echo -e "${RED}chat.jsonl not found at $FULL_CHAT_PATH${NC}"
    echo "Directory contents:"
    ls -la "$WORKING_DIR/.ai-pm/agents/agt_uc009_chat/" 2>/dev/null || echo "(directory not found)"
fi
echo ""

# Coordinator ログ表示
echo -e "${YELLOW}Coordinator log (last 30 lines):${NC}"
tail -30 /tmp/uc009_coordinator.log 2>/dev/null || echo "(no log)"
echo ""

# 結果判定
echo "=========================================="
echo -e "${YELLOW}Final Result: UC009 Specification Verification${NC}"
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
V3_AGENT_RESPONSE=false

if [ -f "$FULL_CHAT_PATH" ]; then
    V1_CHAT_FILE_EXISTS=true
    grep -q '"sender":"user"' "$FULL_CHAT_PATH" && V2_USER_MESSAGE=true
    grep -q '"sender":"agent"' "$FULL_CHAT_PATH" && V3_AGENT_RESPONSE=true
fi

echo "UC009 Specification (3 assertions):"
check_assertion 1 "Chat file created" "$V1_CHAT_FILE_EXISTS"
check_assertion 2 "User message recorded" "$V2_USER_MESSAGE"
check_assertion 3 "Agent response recorded" "$V3_AGENT_RESPONSE"

echo ""
echo "Result: $PASS_COUNT/3 assertions passed"
echo ""

# 全3項目がパスした場合のみ成功
if [ "$PASS_COUNT" -eq 3 ]; then
    echo -e "${GREEN}UC009 App Integration Test: PASSED${NC}"
    echo ""
    echo "All 3 assertions verified:"
    echo "  Chat file created"
    echo "  User message recorded"
    echo "  Agent response recorded"
    exit 0
else
    echo -e "${RED}UC009 App Integration Test: FAILED${NC}"
    echo ""
    echo "Failed assertions: $FAIL_COUNT/3"
    echo ""
    echo "Debug info:"
    echo "  - XCUITest log: /tmp/uc009_uitest.log"
    echo "  - Coordinator log: /tmp/uc009_coordinator.log"
    echo "  - Coordinator logs dir: /tmp/coordinator_logs_uc009/"
    echo "  - Shared DB: $SHARED_DB_PATH"
    echo "  - Working dir: $WORKING_DIR"
    TEST_FAILED=true
    exit 1
fi
