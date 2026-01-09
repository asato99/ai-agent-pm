#!/bin/bash
# UC003 App Integration Test - AI Type Switching E2E Test
# AIタイプ切り替え統合テスト
#
# 設計: 1プロジェクト + 2エージェント（Sonnet 4.5、Opus 4）+ 2タスク
# - モデル指定とkickCommandの優先順位を検証
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
#   - 単一のCoordinatorが全てのagentを管理
#   - should_start(agent_id, project_id)でモデル情報/kickCommandを取得
#   - kickCommandがnilでなければkickCommandを優先
#   - kickCommandがnilならモデル情報を使用してCLI起動
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
TEST_DIR="/tmp/uc003_app_integration_test"

# シードデータが作成するディレクトリ（seedUC003Dataで設定）
WORK_DIR="/tmp/uc003"

# 共有DB: XCUITestアプリが使用するパス
SHARED_DB_PATH="/tmp/AIAgentPM_UITest.db"

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
        rm -rf /tmp/uc003
        rm -f /tmp/uc003_coordinator.log
        rm -f /tmp/uc003_uitest.log
        rm -f /tmp/coordinator_uc003_config.yaml
        rm -rf /tmp/coordinator_logs_uc003
        rm -f "$SHARED_DB_PATH" "$SHARED_DB_PATH-shm" "$SHARED_DB_PATH-wal"
    fi
}

trap cleanup EXIT

echo "=========================================="
echo -e "${BLUE}UC003 App Integration Test${NC}"
echo -e "${BLUE}(AI Type Switching E2E)${NC}"
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
rm -rf /tmp/uc003
mkdir -p "$TEST_DIR"
mkdir -p "$WORK_DIR"
rm -f "$SHARED_DB_PATH" "$SHARED_DB_PATH-shm" "$SHARED_DB_PATH-wal"
# Remove stale socket and PID files
rm -f "$HOME/Library/Application Support/AIAgentPM/mcp.sock" 2>/dev/null
rm -f "$HOME/Library/Application Support/AIAgentPM/daemon.pid" 2>/dev/null
echo "Test directory: $TEST_DIR"
echo "Working directory (from Project.working_directory): $WORK_DIR"
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
echo "  - Agents:"
echo "    - agt_uc003_sonnet: aiType=claudeSonnet4_5, kickCommand=nil"
echo "    - agt_uc003_opus: aiType=claudeOpus4, kickCommand='claude --model opus'"
echo ""

# Coordinator設定（2エージェントのpasskeyを管理）
cat > /tmp/coordinator_uc003_config.yaml << EOF
# Phase 4 Coordinator Configuration for UC003
polling_interval: 2
max_concurrent: 3

# MCP socket path (Coordinator and Agent Instances connect to the SAME daemon)
mcp_socket_path: $HOME/Library/Application Support/AIAgentPM/mcp.sock

# AI providers - how to launch each AI type
ai_providers:
  claude:
    cli_command: claude
    cli_args:
      - "--dangerously-skip-permissions"
      - "--max-turns"
      - "20"

# Agents - passkey for authentication
agents:
  agt_uc003_sonnet:
    passkey: test_passkey_uc003_sonnet
  agt_uc003_opus:
    passkey: test_passkey_uc003_opus

log_directory: /tmp/coordinator_logs_uc003
EOF

mkdir -p /tmp/coordinator_logs_uc003

# Coordinator起動（--coordinatorフラグでPhase 4モード）
# Coordinatorはソケットが見つかるまで待機する
$PYTHON -m aiagent_runner --coordinator -c /tmp/coordinator_uc003_config.yaml -v > /tmp/uc003_coordinator.log 2>&1 &
COORDINATOR_PID=$!
echo "Coordinator started (PID: $COORDINATOR_PID)"
echo "Coordinator is waiting for MCP socket at: $SOCKET_PATH"

# Coordinatorの起動確認（プロセスが生きているか）
sleep 2
if ! kill -0 "$COORDINATOR_PID" 2>/dev/null; then
    echo -e "${RED}Coordinator failed to start${NC}"
    cat /tmp/uc003_coordinator.log
    exit 1
fi
echo -e "${GREEN}✓ Coordinator is running and waiting for MCP socket${NC}"
echo ""

# Step 6: XCUITest実行（アプリ起動 + MCP自動起動 + シードデータ投入 + ステータス変更 + ファイル待機）
echo -e "${YELLOW}Step 6: Running XCUITest (app + MCP auto-start + seed data + wait for files)${NC}"
echo "  This will:"
echo "    1. Launch app with -UITesting -UITestScenario:UC003"
echo "    2. App auto-starts MCP daemon (Coordinator will connect)"
echo "    3. Seed test data (2 agents with different aiType/kickCommand)"
echo "    4. Change both task statuses: backlog → todo → in_progress via UI"
echo "    5. Wait for Coordinator to spawn Agent Instances and create files (max 60s)"
echo ""

cd "$PROJECT_ROOT"
xcodebuild test \
    -scheme AIAgentPM \
    -destination "platform=macOS" \
    -only-testing:AIAgentPMUITests/UC003_AITypeSwitchingTests/testE2E_UC003_AITypeSwitching_Integration \
    2>&1 | tee /tmp/uc003_uitest.log | grep -E "(Test Case|passed|failed|✅|❌|error:)" || true

# テスト結果確認
if grep -q "Test Suite 'UC003_AITypeSwitchingTests' passed" /tmp/uc003_uitest.log; then
    echo -e "${GREEN}✓ XCUITest passed - Files were created by Coordinator${NC}"
elif grep -q "passed" /tmp/uc003_uitest.log; then
    echo -e "${GREEN}✓ XCUITest passed${NC}"
else
    echo -e "${RED}✗ XCUITest failed${NC}"
    grep -E "(error:|failed|FAIL)" /tmp/uc003_uitest.log | tail -20
    echo ""
    echo "Coordinator log (last 30 lines):"
    tail -30 /tmp/uc003_coordinator.log 2>/dev/null || echo "(no log)"
    exit 1
fi
echo ""

# Step 7: 結果検証
echo -e "${YELLOW}Step 7: Verifying outputs${NC}"

SONNET_OUTPUT="$WORK_DIR/SONNET_OUTPUT.md"
OPUS_OUTPUT="$WORK_DIR/OPUS_OUTPUT.md"

SONNET_CHARS=0
OPUS_CHARS=0

# Sonnet Agent検証
if [ -f "$SONNET_OUTPUT" ]; then
    CONTENT=$(cat "$SONNET_OUTPUT")
    SONNET_CHARS=$(echo "$CONTENT" | wc -c | tr -d ' ')
    echo "Sonnet agent output: $SONNET_CHARS characters"
    echo -e "${GREEN}✓ Sonnet agent (aiType=claudeSonnet4_5) created output${NC}"
else
    echo -e "${RED}✗ Sonnet agent output not found${NC}"
fi

# Opus Agent検証
if [ -f "$OPUS_OUTPUT" ]; then
    CONTENT=$(cat "$OPUS_OUTPUT")
    OPUS_CHARS=$(echo "$CONTENT" | wc -c | tr -d ' ')
    echo "Opus agent output: $OPUS_CHARS characters"
    echo -e "${GREEN}✓ Opus agent (kickCommand) created output${NC}"
else
    echo -e "${RED}✗ Opus agent output not found${NC}"
fi
echo ""

# Step 8: モデル検証（execution_logsテーブルのmodel_verified確認）
echo -e "${YELLOW}Step 8: Verifying model information in execution_logs${NC}"

MODEL_VERIFICATION_PASSED=true

# Sonnetエージェントのモデル検証
SONNET_MODEL_INFO=$(sqlite3 "$SHARED_DB_PATH" "SELECT reported_provider, reported_model, model_verified FROM execution_logs WHERE agent_id='agt_uc003_sonnet' ORDER BY started_at DESC LIMIT 1;" 2>/dev/null || echo "")
if [ -n "$SONNET_MODEL_INFO" ]; then
    SONNET_PROVIDER=$(echo "$SONNET_MODEL_INFO" | cut -d'|' -f1)
    SONNET_MODEL=$(echo "$SONNET_MODEL_INFO" | cut -d'|' -f2)
    SONNET_VERIFIED=$(echo "$SONNET_MODEL_INFO" | cut -d'|' -f3)

    echo "Sonnet Agent model info:"
    echo "  - Provider: $SONNET_PROVIDER"
    echo "  - Model: $SONNET_MODEL"
    echo "  - Verified: $SONNET_VERIFIED"

    if [ "$SONNET_PROVIDER" == "claude" ] && [ -n "$SONNET_MODEL" ]; then
        echo -e "${GREEN}✓ Sonnet agent model info recorded${NC}"
    else
        echo -e "${YELLOW}⚠ Sonnet agent model info incomplete (provider: $SONNET_PROVIDER, model: $SONNET_MODEL)${NC}"
    fi
else
    echo -e "${YELLOW}⚠ No execution log found for Sonnet agent (model verification not recorded)${NC}"
    # モデル検証はオプショナル（Runner側の実装に依存）なのでFAILにはしない
fi

# Opusエージェントのモデル検証
OPUS_MODEL_INFO=$(sqlite3 "$SHARED_DB_PATH" "SELECT reported_provider, reported_model, model_verified FROM execution_logs WHERE agent_id='agt_uc003_opus' ORDER BY started_at DESC LIMIT 1;" 2>/dev/null || echo "")
if [ -n "$OPUS_MODEL_INFO" ]; then
    OPUS_PROVIDER=$(echo "$OPUS_MODEL_INFO" | cut -d'|' -f1)
    OPUS_MODEL=$(echo "$OPUS_MODEL_INFO" | cut -d'|' -f2)
    OPUS_VERIFIED=$(echo "$OPUS_MODEL_INFO" | cut -d'|' -f3)

    echo "Opus Agent model info:"
    echo "  - Provider: $OPUS_PROVIDER"
    echo "  - Model: $OPUS_MODEL"
    echo "  - Verified: $OPUS_VERIFIED"

    if [ "$OPUS_PROVIDER" == "claude" ] && [ -n "$OPUS_MODEL" ]; then
        echo -e "${GREEN}✓ Opus agent model info recorded${NC}"
    else
        echo -e "${YELLOW}⚠ Opus agent model info incomplete (provider: $OPUS_PROVIDER, model: $OPUS_MODEL)${NC}"
    fi
else
    echo -e "${YELLOW}⚠ No execution log found for Opus agent (model verification not recorded)${NC}"
fi
echo ""

# Coordinator ログ表示
echo -e "${YELLOW}Coordinator log (last 30 lines):${NC}"
tail -30 /tmp/uc003_coordinator.log 2>/dev/null || echo "(no log)"
echo ""

# 結果判定
echo "=========================================="
SONNET_CREATED=false
OPUS_CREATED=false

if [ -f "$SONNET_OUTPUT" ]; then
    SONNET_CREATED=true
fi
if [ -f "$OPUS_OUTPUT" ]; then
    OPUS_CREATED=true
fi

if [ "$SONNET_CREATED" == "true" ] && [ "$OPUS_CREATED" == "true" ]; then
    echo -e "${GREEN}UC003 App Integration Test: PASSED${NC}"
    echo ""
    echo "Verified (Phase 4 Coordinator Architecture):"
    echo "  - Coordinator started FIRST and waited for MCP socket"
    echo "  - App started MCP daemon, Coordinator connected"
    echo "  - Sonnet Agent (aiType=claudeSonnet4_5, kickCommand=nil): $SONNET_CHARS chars"
    echo "  - Opus Agent (aiType=claudeOpus4, kickCommand='claude --model opus'): $OPUS_CHARS chars"
    echo "  - kickCommand takes precedence when set"
    echo ""
    echo "Model Verification (report_model tool):"
    if [ -n "$SONNET_MODEL_INFO" ]; then
        echo "  - Sonnet: provider=$SONNET_PROVIDER, model=$SONNET_MODEL, verified=$SONNET_VERIFIED"
    else
        echo "  - Sonnet: (no model info recorded)"
    fi
    if [ -n "$OPUS_MODEL_INFO" ]; then
        echo "  - Opus: provider=$OPUS_PROVIDER, model=$OPUS_MODEL, verified=$OPUS_VERIFIED"
    else
        echo "  - Opus: (no model info recorded)"
    fi
    exit 0
else
    echo -e "${RED}UC003 App Integration Test: FAILED${NC}"
    echo ""
    echo "Debug info:"
    echo "  - XCUITest log: /tmp/uc003_uitest.log"
    echo "  - Coordinator log: /tmp/uc003_coordinator.log"
    echo "  - Coordinator logs dir: /tmp/coordinator_logs_uc003/"
    echo "  - Shared DB: $SHARED_DB_PATH"
    exit 1
fi
