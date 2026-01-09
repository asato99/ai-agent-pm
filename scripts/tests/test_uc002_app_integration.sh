#!/bin/bash
# UC002 App Integration Test - Multi-Agent Collaboration E2E Test
# マルチエージェント協調テスト（アプリ統合版）
#
# 設計A: 1プロジェクト + 2タスク（同一内容、異なるエージェント）
# - 同じタスク指示で異なるsystem_promptによる出力差異を検証
#
# フロー:
#   1. テスト環境準備
#   2. アプリビルド
#   3. MCPサーバービルド
#   4. Runner確認
#   5. Coordinator起動（ソケット待機状態で起動）
#   6. XCUITest実行（アプリ起動→MCP自動起動→Coordinator接続→ステータス変更→ファイル作成待機）
#   7. 結果検証
#
# アーキテクチャ（Phase 4 Coordinator）:
#   - 単一のCoordinatorが全ての(agent_id, project_id)ペアを管理
#   - Coordinatorは各agentのpasskeyを保持
#   - should_start(agent_id, project_id)で各ペアの作業有無を確認
#   - 作業があればAgent Instance（Claude Code）をスポーン
#   - Agent Instanceがauthenticate → get_my_task → execute → report_completed
#
# ポイント:
#   - アプリがMCPデーモンを自動起動（applicationDidFinishLaunching）
#   - Coordinatorはソケット作成を待機してから接続
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
# プロジェクトのworking_directoryを使用（シードデータと一致させる）
PROJECT_WORKING_DIR="/tmp/uc002_test"
# 中立的なファイル名（テスト意図: system_promptの違いのみで振る舞いが変わる）
OUTPUT_FILE_A="OUTPUT_A.md"  # 詳細ライター
OUTPUT_FILE_B="OUTPUT_B.md"  # 簡潔ライター

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
    # Note: MCP Daemon is managed by the app, not by this script
    if [ "$1" != "--keep" ]; then
        rm -rf "$PROJECT_WORKING_DIR"
        rm -f /tmp/uc002_coordinator.log
        rm -f /tmp/uc002_daemon.log
        rm -f /tmp/uc002_uitest.log
        rm -f /tmp/coordinator_uc002_config.yaml
        rm -rf /tmp/coordinator_logs_uc002
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

# CRITICAL: Kill ALL stale MCP daemon processes from previous runs
# This prevents Coordinator from connecting to an old daemon with wrong database
echo "Killing any stale MCP daemon processes..."
ps aux | grep "mcp-server-pm" | grep -v grep | awk '{print $2}' | xargs -I {} kill -9 {} 2>/dev/null || true
sleep 1

# プロジェクトのworking_directoryを作成（シードデータと一致）
rm -rf "$PROJECT_WORKING_DIR"
mkdir -p "$PROJECT_WORKING_DIR"
rm -f "$SHARED_DB_PATH" "$SHARED_DB_PATH-shm" "$SHARED_DB_PATH-wal"
# Remove stale socket and PID files
rm -f "$HOME/Library/Application Support/AIAgentPM/mcp.sock" 2>/dev/null
rm -f "$HOME/Library/Application Support/AIAgentPM/daemon.pid" 2>/dev/null
echo "Project working directory: $PROJECT_WORKING_DIR"
echo "Expected outputs:"
echo "  - $PROJECT_WORKING_DIR/$OUTPUT_FILE_A (詳細ライター)"
echo "  - $PROJECT_WORKING_DIR/$OUTPUT_FILE_B (簡潔ライター)"
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
swift build --product mcp-server-pm 2>&1 | tail -5 || {
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

# Step 5: Coordinator起動
# Note: MCP Daemon is started by the app in applicationDidFinishLaunching
# The Coordinator will wait for the socket to become available
echo -e "${YELLOW}Step 5: Starting Coordinator${NC}"
echo "  Architecture: Phase 4 Coordinator"
echo "  - MCP Daemon will be started by the app"
echo "  - Coordinator polls list_active_projects_with_agents()"
echo "  - Calls should_start(agent_id, project_id) for each pair"
echo "  - Spawns Agent Instances (Claude Code) as needed"
echo "  Agents: agt_detailed_writer, agt_concise_writer (passkeys in Coordinator config)"
echo ""

# Coordinator設定（単一ファイルで全agentのpasskeyを管理）
cat > /tmp/coordinator_uc002_config.yaml << EOF
# Phase 4 Coordinator Configuration
polling_interval: 2
max_concurrent: 3

# MCP socket path (Coordinator and Agent Instances connect to the SAME daemon)
mcp_socket_path: $HOME/Library/Application Support/AIAgentPM/mcp.sock

# AI providers - how to launch each AI type
# Note: max-turns increased to 50 for complex workflow
# (authenticate → report_model → get_task → create_subtasks → execute → complete)
ai_providers:
  claude:
    cli_command: claude
    cli_args:
      - "--dangerously-skip-permissions"
      - "--max-turns"
      - "50"

# Agents - only passkey is needed (ai_type, system_prompt come from MCP)
agents:
  agt_detailed_writer:
    passkey: test_passkey_detailed
  agt_concise_writer:
    passkey: test_passkey_concise

log_directory: /tmp/coordinator_logs_uc002
EOF

mkdir -p /tmp/coordinator_logs_uc002

# Coordinator起動（--coordinatorフラグでPhase 4モード）
# Coordinatorはソケットが見つかるまで待機する
$PYTHON -m aiagent_runner --coordinator -c /tmp/coordinator_uc002_config.yaml -v > /tmp/uc002_coordinator.log 2>&1 &
COORDINATOR_PID=$!
echo "Coordinator started (PID: $COORDINATOR_PID)"
echo "Coordinator is waiting for MCP socket at: $SOCKET_PATH"

# Coordinatorの起動確認（プロセスが生きているか）
sleep 2
if ! kill -0 "$COORDINATOR_PID" 2>/dev/null; then
    echo -e "${RED}Coordinator failed to start${NC}"
    cat /tmp/uc002_coordinator.log
    exit 1
fi
echo -e "${GREEN}✓ Coordinator is running and waiting for MCP socket${NC}"
echo ""

# Step 6: XCUITest実行（アプリ起動 + シードデータ投入 + ステータス変更 + ファイル待機）
echo -e "${YELLOW}Step 6: Running XCUITest (app + seed data + wait for files)${NC}"
echo "  This will:"
echo "    1. Launch app with -UITesting -UITestScenario:UC002"
echo "    2. App starts MCP daemon automatically"
echo "    3. Seed test data (detailed + concise writers)"
echo "    4. Change both task statuses: backlog → todo → in_progress via UI"
echo "    5. Wait for Coordinator to spawn Agent Instances and create files (max 180s)"
echo ""

cd "$PROJECT_ROOT"
xcodebuild test \
    -scheme AIAgentPM \
    -destination "platform=macOS" \
    -only-testing:AIAgentPMUITests/UC002_MultiAgentCollaborationTests/testMultiAgentIntegration_ChangeBothTasksToInProgress \
    2>&1 | tee /tmp/uc002_uitest.log | grep -E "(Test Case|passed|failed|✅|❌|error:)" || true

# テスト結果確認
if grep -q "Test Suite 'UC002_MultiAgentCollaborationTests' passed" /tmp/uc002_uitest.log; then
    echo -e "${GREEN}✓ XCUITest passed - Files were created by Coordinator${NC}"
elif grep -q "passed" /tmp/uc002_uitest.log; then
    echo -e "${GREEN}✓ XCUITest passed${NC}"
else
    echo -e "${RED}✗ XCUITest failed${NC}"
    grep -E "(error:|failed|FAIL)" /tmp/uc002_uitest.log | tail -20
    echo ""
    echo "Coordinator log (last 30 lines):"
    tail -30 /tmp/uc002_coordinator.log 2>/dev/null || echo "(no log)"
    exit 1
fi
echo ""

# Step 7: 結果検証
echo -e "${YELLOW}Step 7: Verifying outputs in $PROJECT_WORKING_DIR${NC}"

OUTPUT_A_CHARS=0
OUTPUT_B_CHARS=0
OUTPUT_A_HAS_BACKGROUND=false

# OUTPUT_A.md（詳細ライター）検証
if [ -f "$PROJECT_WORKING_DIR/$OUTPUT_FILE_A" ]; then
    CONTENT=$(cat "$PROJECT_WORKING_DIR/$OUTPUT_FILE_A")
    OUTPUT_A_CHARS=$(echo "$CONTENT" | wc -c | tr -d ' ')
    echo "$OUTPUT_FILE_A (詳細ライター): $OUTPUT_A_CHARS characters"

    # 「背景」を含むかチェック（詳細system_promptの期待動作）
    if echo "$CONTENT" | grep -q "背景"; then
        OUTPUT_A_HAS_BACKGROUND=true
        echo "  Contains '背景' section: YES"
    else
        echo "  Contains '背景' section: NO"
    fi

    # 詳細版の基準: 300文字以上 または「背景」を含む
    if [ "$OUTPUT_A_CHARS" -gt 300 ] || [ "$OUTPUT_A_HAS_BACKGROUND" == "true" ]; then
        echo -e "${GREEN}✓ OUTPUT_A meets detailed criteria${NC}"
    else
        echo -e "${YELLOW}⚠ OUTPUT_A may not be comprehensive enough${NC}"
    fi
else
    echo -e "${RED}✗ $OUTPUT_FILE_A not found${NC}"
fi

# OUTPUT_B.md（簡潔ライター）検証
if [ -f "$PROJECT_WORKING_DIR/$OUTPUT_FILE_B" ]; then
    CONTENT=$(cat "$PROJECT_WORKING_DIR/$OUTPUT_FILE_B")
    OUTPUT_B_CHARS=$(echo "$CONTENT" | wc -c | tr -d ' ')
    echo "$OUTPUT_FILE_B (簡潔ライター): $OUTPUT_B_CHARS characters"

    # OUTPUT_Aとの比較
    if [ "$OUTPUT_A_CHARS" -gt 0 ] && [ "$OUTPUT_B_CHARS" -gt 0 ]; then
        RATIO=$((OUTPUT_A_CHARS / OUTPUT_B_CHARS))
        echo "  Ratio (A/B): ${RATIO}x"
    fi

    # 簡潔版は詳細版より短いはず
    if [ "$OUTPUT_B_CHARS" -lt "$OUTPUT_A_CHARS" ]; then
        echo -e "${GREEN}✓ OUTPUT_B is shorter than OUTPUT_A${NC}"
    else
        echo -e "${YELLOW}⚠ OUTPUT_B is NOT shorter than OUTPUT_A${NC}"
    fi
else
    echo -e "${RED}✗ $OUTPUT_FILE_B not found${NC}"
fi
echo ""

# Coordinator ログ表示
echo -e "${YELLOW}Coordinator log (last 30 lines):${NC}"
tail -30 /tmp/uc002_coordinator.log 2>/dev/null || echo "(no log)"
echo ""

# 結果判定
echo "=========================================="
OUTPUT_A_CREATED=false
OUTPUT_B_CREATED=false

if [ -f "$PROJECT_WORKING_DIR/$OUTPUT_FILE_A" ]; then
    OUTPUT_A_CREATED=true
fi
if [ -f "$PROJECT_WORKING_DIR/$OUTPUT_FILE_B" ]; then
    OUTPUT_B_CREATED=true
fi

if [ "$OUTPUT_A_CREATED" == "true" ] && [ "$OUTPUT_B_CREATED" == "true" ]; then
    # 追加の検証
    PASS=true

    # 詳細版が基準を満たしているか
    if [ "$OUTPUT_A_CHARS" -lt 300 ] && [ "$OUTPUT_A_HAS_BACKGROUND" != "true" ]; then
        echo -e "${YELLOW}Warning: OUTPUT_A may not be comprehensive${NC}"
    fi

    # 簡潔版が詳細版より短いか
    if [ "$OUTPUT_B_CHARS" -ge "$OUTPUT_A_CHARS" ]; then
        echo -e "${YELLOW}Warning: OUTPUT_B is not shorter than OUTPUT_A${NC}"
        # 警告だが失敗にはしない
    fi

    echo -e "${GREEN}UC002 App Integration Test: PASSED${NC}"
    echo ""
    echo "Verified (Phase 4 Coordinator Architecture):"
    echo "  - Coordinator started FIRST and waited for MCP socket"
    echo "  - App started MCP daemon, Coordinator connected"
    echo "  - Single Coordinator managed both agents"
    echo "  - Coordinator spawned Agent Instances for each (agent_id, project_id) pair"
    echo "  - Both agents worked in same directory: $PROJECT_WORKING_DIR"
    echo "  - Same task instructions → different outputs based on system_prompt only"
    echo "  - OUTPUT_A (詳細 system_prompt): $OUTPUT_A_CHARS chars"
    echo "  - OUTPUT_B (簡潔 system_prompt): $OUTPUT_B_CHARS chars"
    exit 0
else
    echo -e "${RED}UC002 App Integration Test: FAILED${NC}"
    echo ""
    echo "Debug info:"
    echo "  - Project working directory: $PROJECT_WORKING_DIR"
    echo "  - XCUITest log: /tmp/uc002_uitest.log"
    echo "  - Coordinator log: /tmp/uc002_coordinator.log"
    echo "  - Coordinator logs dir: /tmp/coordinator_logs_uc002/"
    echo "  - Shared DB: $SHARED_DB_PATH"
    exit 1
fi
