#!/bin/bash
# UC002 Multi-Agent Collaboration Integration Test
# 異なるsystem_promptを持つエージェントが異なる成果物を作成することを検証
#
# アーキテクチャ: UC001と同様のPull-based
#   データ投入 → Runner起動 → CLI実行 → 出力検証
#
# 注: ai_typeの切り替え検証はUC003で実施

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
TEST_DIR="/tmp/uc002_multi_agent_test"
DAEMON_PID=""
RUNNER_PID_DETAILED=""
RUNNER_PID_CONCISE=""

# テストデータ
DETAILED_AGENT_ID="agt_detailed_writer"
CONCISE_AGENT_ID="agt_concise_writer"
TEST_PROJECT_ID="prj_uc002_test"
PASSKEY="test_passkey_uc002"
# SHA256(passkey + salt)
PASSKEY_HASH="be81f80723844b4b6aaa4c496670ff523ddd8e7417fc0ebcba03462fe05d2d38"
SALT="dGVzdF9zYWx0X3VjMDAy"

# system_prompt（異なる指示で異なる出力を生成）
DETAILED_SYSTEM_PROMPT="詳細で包括的なドキュメントを作成してください。背景、目的、使用例を必ず含めてください。"
CONCISE_SYSTEM_PROMPT="簡潔に要点のみ記載してください。箇条書きで3項目以内にまとめてください。"

# クリーンアップ関数
cleanup() {
    echo ""
    echo -e "${YELLOW}Cleanup${NC}"
    if [ -n "$RUNNER_PID_DETAILED" ] && kill -0 "$RUNNER_PID_DETAILED" 2>/dev/null; then
        kill "$RUNNER_PID_DETAILED" 2>/dev/null || true
    fi
    if [ -n "$RUNNER_PID_CONCISE" ] && kill -0 "$RUNNER_PID_CONCISE" 2>/dev/null; then
        kill "$RUNNER_PID_CONCISE" 2>/dev/null || true
    fi
    if [ -n "$DAEMON_PID" ] && kill -0 "$DAEMON_PID" 2>/dev/null; then
        kill "$DAEMON_PID" 2>/dev/null || true
    fi
    rm -f "$HOME/Library/Application Support/AIAgentPM/mcp.sock" 2>/dev/null
    if [ "$1" != "--keep" ]; then
        rm -rf "$TEST_DIR"
        rm -f /tmp/uc002_daemon.log
        rm -f /tmp/runner_detailed.log
        rm -f /tmp/runner_concise.log
    fi
}

trap cleanup EXIT

echo "=========================================="
echo -e "${BLUE}UC002 Multi-Agent Integration Test${NC}"
echo -e "${BLUE}(system_prompt差異による出力検証)${NC}"
echo "=========================================="
echo ""

# Step 1: テスト環境準備
echo -e "${YELLOW}Step 1: Preparing test environment${NC}"
rm -rf "$TEST_DIR"
mkdir -p "$TEST_DIR/detailed"
mkdir -p "$TEST_DIR/concise"
echo "Test directory: $TEST_DIR"
echo ""

# Step 2: MCPサーバービルド
echo -e "${YELLOW}Step 2: Building MCP server${NC}"
cd "$PROJECT_ROOT"
xcodebuild -scheme MCPServer -destination 'platform=macOS' build 2>&1 || {
    echo -e "${RED}Failed to build mcp-server-pm${NC}"
    exit 1
}
MCP_SERVER_PATH="$PROJECT_ROOT/.build/debug/mcp-server-pm"
echo "Build complete"
echo ""

# Step 3: Runnerの確認
echo -e "${YELLOW}Step 3: Checking Runner setup${NC}"
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

# Step 4: MCPデーモン起動
echo -e "${YELLOW}Step 4: Starting MCP daemon${NC}"
TEST_DB_PATH="$HOME/Library/Application Support/AIAgentPM/uc002_test.db"
export AIAGENTPM_DB_PATH="$TEST_DB_PATH"
mkdir -p "$(dirname "$TEST_DB_PATH")"
rm -f "$TEST_DB_PATH"
rm -f "$HOME/Library/Application Support/AIAgentPM/mcp.sock" 2>/dev/null

"$MCP_SERVER_PATH" daemon --foreground > /tmp/uc002_daemon.log 2>&1 &
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
    cat /tmp/uc002_daemon.log
    exit 1
fi
echo ""

# Step 5: テストデータ投入
echo -e "${YELLOW}Step 5: Seeding test data${NC}"

CREDENTIAL_ID_1=$(uuidgen | tr '[:upper:]' '[:lower:]')
CREDENTIAL_ID_2=$(uuidgen | tr '[:upper:]' '[:lower:]')
TASK_ID_1=$(uuidgen | tr '[:upper:]' '[:lower:]')
TASK_ID_2=$(uuidgen | tr '[:upper:]' '[:lower:]')

sqlite3 "$TEST_DB_PATH" << EOSQL
-- プロジェクト
INSERT INTO projects (id, name, description, status, created_at, updated_at)
VALUES ('$TEST_PROJECT_ID', 'UC002 Test Project', 'Multi-agent test', 'active', datetime('now'), datetime('now'));

-- 詳細ライター（Claude / 詳細system_prompt）
INSERT INTO agents (id, name, role, type, ai_type, system_prompt, status, created_at, updated_at)
VALUES ('$DETAILED_AGENT_ID', '詳細ライター', 'Documentation writer', 'ai', 'claude',
        '$DETAILED_SYSTEM_PROMPT', 'active', datetime('now'), datetime('now'));

-- 簡潔ライター（Claude / 簡潔system_prompt）
INSERT INTO agents (id, name, role, type, ai_type, system_prompt, status, created_at, updated_at)
VALUES ('$CONCISE_AGENT_ID', '簡潔ライター', 'Summary writer', 'ai', 'claude',
        '$CONCISE_SYSTEM_PROMPT', 'active', datetime('now'), datetime('now'));

-- 認証情報
INSERT INTO agent_credentials (id, agent_id, passkey_hash, salt, created_at)
VALUES ('$CREDENTIAL_ID_1', '$DETAILED_AGENT_ID', '$PASSKEY_HASH', '$SALT', datetime('now'));

INSERT INTO agent_credentials (id, agent_id, passkey_hash, salt, created_at)
VALUES ('$CREDENTIAL_ID_2', '$CONCISE_AGENT_ID', '$PASSKEY_HASH', '$SALT', datetime('now'));

-- タスク（詳細ライター用）
INSERT INTO tasks (id, project_id, title, description, status, priority, assignee_id, created_at, updated_at)
VALUES ('$TASK_ID_1', '$TEST_PROJECT_ID', 'Create detailed summary',
'PROJECT_SUMMARY.md を作成してください。このプロジェクトは「タスク管理システム」です。',
        'in_progress', 'medium', '$DETAILED_AGENT_ID', datetime('now'), datetime('now'));

-- タスク（簡潔ライター用）
INSERT INTO tasks (id, project_id, title, description, status, priority, assignee_id, created_at, updated_at)
VALUES ('$TASK_ID_2', '$TEST_PROJECT_ID', 'Create concise summary',
'PROJECT_SUMMARY.md を作成してください。このプロジェクトは「タスク管理システム」です。',
        'in_progress', 'medium', '$CONCISE_AGENT_ID', datetime('now'), datetime('now'));
EOSQL

echo "  Detailed Writer: $DETAILED_AGENT_ID (system_prompt=詳細版)"
echo "  Concise Writer: $CONCISE_AGENT_ID (system_prompt=簡潔版)"
echo ""

# Step 6: Runner起動（詳細ライター）
echo -e "${YELLOW}Step 6: Starting Runner for detailed writer${NC}"

cat > /tmp/runner_detailed_config.yaml << EOF
agent_id: $DETAILED_AGENT_ID
passkey: $PASSKEY
polling_interval: 2
cli_command: claude
cli_args:
  - "--dangerously-skip-permissions"
working_directory: $TEST_DIR/detailed
log_directory: /tmp/runner_logs_detailed
EOF

$PYTHON -m aiagent_runner -c /tmp/runner_detailed_config.yaml -v > /tmp/runner_detailed.log 2>&1 &
RUNNER_PID_DETAILED=$!
echo "Detailed Runner started (PID: $RUNNER_PID_DETAILED)"
echo ""

# Step 7: Runner起動（簡潔ライター）
echo -e "${YELLOW}Step 7: Starting Runner for concise writer${NC}"

cat > /tmp/runner_concise_config.yaml << EOF
agent_id: $CONCISE_AGENT_ID
passkey: $PASSKEY
polling_interval: 2
cli_command: claude
cli_args:
  - "--dangerously-skip-permissions"
working_directory: $TEST_DIR/concise
log_directory: /tmp/runner_logs_concise
EOF

$PYTHON -m aiagent_runner -c /tmp/runner_concise_config.yaml -v > /tmp/runner_concise.log 2>&1 &
RUNNER_PID_CONCISE=$!
echo "Concise Runner started (PID: $RUNNER_PID_CONCISE)"
echo ""

# Step 8: タスク実行待機
echo -e "${YELLOW}Step 8: Waiting for task execution (max 180s)${NC}"

DETAILED_CREATED=false
CONCISE_CREATED=false

for i in $(seq 1 36); do
    if [ -f "$TEST_DIR/detailed/PROJECT_SUMMARY.md" ] && [ "$DETAILED_CREATED" == "false" ]; then
        echo -e "${GREEN}✓ Detailed writer created PROJECT_SUMMARY.md${NC}"
        DETAILED_CREATED=true
    fi

    if [ -f "$TEST_DIR/concise/PROJECT_SUMMARY.md" ] && [ "$CONCISE_CREATED" == "false" ]; then
        echo -e "${GREEN}✓ Concise writer created PROJECT_SUMMARY.md${NC}"
        CONCISE_CREATED=true
    fi

    if [ "$DETAILED_CREATED" == "true" ] && [ "$CONCISE_CREATED" == "true" ]; then
        break
    fi

    sleep 5
done
echo ""

# Step 9: 出力検証
echo -e "${YELLOW}Step 9: Verifying outputs${NC}"

DETAILED_PASS=false
CONCISE_PASS=false

# 詳細ライターの検証
if [ -f "$TEST_DIR/detailed/PROJECT_SUMMARY.md" ]; then
    DETAILED_CONTENT=$(cat "$TEST_DIR/detailed/PROJECT_SUMMARY.md")
    DETAILED_CHARS=$(echo "$DETAILED_CONTENT" | wc -c | tr -d ' ')
    echo "Detailed output: $DETAILED_CHARS characters"

    # 詳細版は長い、または「背景」「目的」を含む
    if [ "$DETAILED_CHARS" -gt 300 ] || (echo "$DETAILED_CONTENT" | grep -q "背景"); then
        echo -e "${GREEN}✓ Detailed output meets criteria${NC}"
        DETAILED_PASS=true
    fi
else
    echo -e "${RED}✗ Detailed writer did not create file${NC}"
fi

# 簡潔ライターの検証
if [ -f "$TEST_DIR/concise/PROJECT_SUMMARY.md" ]; then
    CONCISE_CONTENT=$(cat "$TEST_DIR/concise/PROJECT_SUMMARY.md")
    CONCISE_CHARS=$(echo "$CONCISE_CONTENT" | wc -c | tr -d ' ')
    echo "Concise output: $CONCISE_CHARS characters"

    # 検証: 簡潔版は詳細版より短い（異なるsystem_promptの効果を確認）
    if [ "$DETAILED_PASS" == "true" ] && [ "$CONCISE_CHARS" -lt "$DETAILED_CHARS" ]; then
        RATIO=$((DETAILED_CHARS / CONCISE_CHARS))
        echo "  Ratio (detailed/concise): ${RATIO}x"
        echo -e "${GREEN}✓ Concise output is shorter than detailed${NC}"
        CONCISE_PASS=true
    elif [ "$CONCISE_CHARS" -lt 500 ]; then
        echo -e "${GREEN}✓ Concise output meets absolute criteria${NC}"
        CONCISE_PASS=true
    else
        echo -e "${YELLOW}⚠ Concise output (${CONCISE_CHARS}) not shorter than detailed (${DETAILED_CHARS})${NC}"
    fi
else
    echo -e "${RED}✗ Concise writer did not create file${NC}"
fi
echo ""

# デバッグログ
echo -e "${YELLOW}Runner logs (last 15 lines each):${NC}"
echo "--- Detailed ---"
tail -15 /tmp/runner_detailed.log 2>/dev/null || echo "(no log)"
echo "--- Concise ---"
tail -15 /tmp/runner_concise.log 2>/dev/null || echo "(no log)"
echo ""

# 結果
echo "=========================================="
if [ "$DETAILED_PASS" == "true" ] && [ "$CONCISE_PASS" == "true" ]; then
    echo -e "${GREEN}UC002 Integration Test: PASSED${NC}"
    echo ""
    echo "Verified:"
    echo "  - Detailed writer created comprehensive output"
    echo "  - Concise writer created brief output"
    echo "  - Different system_prompts produced different outputs"
    exit 0
else
    echo -e "${RED}UC002 Integration Test: FAILED${NC}"
    echo ""
    echo "Results:"
    echo "  Detailed writer: $([ "$DETAILED_PASS" == "true" ] && echo "PASSED" || echo "FAILED")"
    echo "  Concise writer: $([ "$CONCISE_PASS" == "true" ] && echo "PASSED" || echo "FAILED")"
    exit 1
fi
