#!/bin/bash
# Passkey Error Integration Test
# パスキー認証失敗時のエラー応答を確認する統合テスト
#
# 目的:
#   1. MCP Serverが間違ったパスキーでの認証を正しく拒否することを確認
#   2. エラー応答に "action": "exit" が含まれることを確認
#
# フロー:
#   1. テスト用DBを作成
#   2. エージェントとプロジェクトをDBにシード
#   3. MCPデーモンを起動
#   4. 正しいパスキーで認証 → 成功を確認
#   5. 間違ったパスキーで認証 → 失敗とaction:exitを確認

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
TEST_DB="/tmp/passkey_test.db"
MCP_SOCKET="/tmp/passkey_test.sock"
TEST_AGENT_ID="agt_passkey_test"
TEST_PROJECT_ID="prj_passkey_test"
CORRECT_PASSKEY="correct_passkey_12345"
WRONG_PASSKEY="wrong_passkey_99999"

DAEMON_PID=""
TEST_FAILED=false

# クリーンアップ関数
cleanup() {
    echo ""
    echo -e "${YELLOW}Cleanup${NC}"
    if [ -n "$DAEMON_PID" ] && kill -0 "$DAEMON_PID" 2>/dev/null; then
        kill "$DAEMON_PID" 2>/dev/null || true
        wait "$DAEMON_PID" 2>/dev/null || true
        echo "Daemon stopped"
    fi
    rm -f "$TEST_DB" "$TEST_DB-shm" "$TEST_DB-wal"
    rm -f "$MCP_SOCKET"
    rm -f /tmp/passkey_test_daemon.log
}

trap 'if [ $? -ne 0 ]; then TEST_FAILED=true; fi; cleanup' EXIT

echo "=========================================="
echo -e "${BLUE}Passkey Error Integration Test${NC}"
echo "=========================================="
echo ""

# Step 1: MCPサーバービルド
echo -e "${YELLOW}Step 1: Building MCP server${NC}"
cd "$PROJECT_ROOT"
xcodebuild -scheme MCPServer -destination 'platform=macOS' build 2>&1 | tail -3 || {
    echo -e "${RED}Failed to build MCP server${NC}"
    exit 1
}
MCP_SERVER="$PROJECT_ROOT/.build/debug/mcp-server-pm"
echo "MCP server built: $MCP_SERVER"
echo ""

# Step 2: テストDB作成とシード
echo -e "${YELLOW}Step 2: Creating test database with seed data${NC}"
rm -f "$TEST_DB" "$TEST_DB-shm" "$TEST_DB-wal"

# SQLiteでDBを初期化
sqlite3 "$TEST_DB" << 'SCHEMA'
-- Projects table
CREATE TABLE projects (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    description TEXT,
    status TEXT NOT NULL DEFAULT 'active',
    working_directory TEXT,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- Agents table
CREATE TABLE agents (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    role TEXT NOT NULL,
    type TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'inactive',
    system_prompt TEXT,
    provider TEXT,
    model TEXT,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- Agent credentials table (Phase 3)
CREATE TABLE agent_credentials (
    agent_id TEXT PRIMARY KEY,
    passkey_hash TEXT NOT NULL,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY(agent_id) REFERENCES agents(id)
);

-- Agent sessions table (Phase 3)
CREATE TABLE agent_sessions (
    session_token TEXT PRIMARY KEY,
    agent_id TEXT NOT NULL,
    project_id TEXT NOT NULL,
    expires_at DATETIME NOT NULL,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY(agent_id) REFERENCES agents(id),
    FOREIGN KEY(project_id) REFERENCES projects(id)
);

-- Project-Agent Assignments table (Phase 4)
CREATE TABLE project_agent_assignments (
    project_id TEXT NOT NULL,
    agent_id TEXT NOT NULL,
    assigned_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY(project_id, agent_id),
    FOREIGN KEY(project_id) REFERENCES projects(id),
    FOREIGN KEY(agent_id) REFERENCES agents(id)
);

-- App settings table (for coordinator token)
CREATE TABLE app_settings (
    id TEXT PRIMARY KEY,
    coordinator_token TEXT,
    pending_purpose_ttl_seconds INTEGER NOT NULL DEFAULT 300,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- Tasks table
CREATE TABLE tasks (
    id TEXT PRIMARY KEY,
    project_id TEXT NOT NULL,
    title TEXT NOT NULL,
    description TEXT,
    status TEXT NOT NULL DEFAULT 'backlog',
    priority TEXT NOT NULL DEFAULT 'medium',
    assignee_id TEXT,
    acceptance_criteria TEXT,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY(project_id) REFERENCES projects(id),
    FOREIGN KEY(assignee_id) REFERENCES agents(id)
);

-- Pending agent purposes table (for chat)
CREATE TABLE pending_agent_purposes (
    agent_id TEXT NOT NULL,
    project_id TEXT NOT NULL,
    purpose TEXT NOT NULL,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    started_at DATETIME,
    PRIMARY KEY(agent_id, project_id)
);
SCHEMA

# シードデータ挿入
sqlite3 "$TEST_DB" << SEED
-- プロジェクト
INSERT INTO projects (id, name, description, status, working_directory)
VALUES ('$TEST_PROJECT_ID', 'Passkey Test Project', 'Test project for passkey verification', 'active', '/tmp/passkey_test');

-- エージェント
INSERT INTO agents (id, name, role, type, status)
VALUES ('$TEST_AGENT_ID', 'Passkey Test Agent', 'tester', 'executor', 'inactive');

-- パスキー（SHA256ハッシュ）
INSERT INTO agent_credentials (agent_id, passkey_hash)
VALUES ('$TEST_AGENT_ID', '$(echo -n "$CORRECT_PASSKEY" | shasum -a 256 | cut -d' ' -f1)');

-- プロジェクト-エージェント割り当て
INSERT INTO project_agent_assignments (project_id, agent_id)
VALUES ('$TEST_PROJECT_ID', '$TEST_AGENT_ID');

-- アプリ設定（Coordinatorトークン）
INSERT INTO app_settings (id, coordinator_token)
VALUES ('app_settings', 'test_coordinator_token');
SEED

echo "Test database created: $TEST_DB"
echo "  Agent: $TEST_AGENT_ID"
echo "  Project: $TEST_PROJECT_ID"
echo "  Correct passkey: $CORRECT_PASSKEY"
echo ""

# Step 3: MCPデーモン起動
echo -e "${YELLOW}Step 3: Starting MCP daemon${NC}"
rm -f "$MCP_SOCKET"

MCP_DB_PATH="$TEST_DB" "$MCP_SERVER" --daemon --socket-path "$MCP_SOCKET" > /tmp/passkey_test_daemon.log 2>&1 &
DAEMON_PID=$!
echo "Daemon started (PID: $DAEMON_PID)"

# ソケット待機
for i in {1..30}; do
    if [ -S "$MCP_SOCKET" ]; then
        echo -e "${GREEN}MCP socket ready: $MCP_SOCKET${NC}"
        break
    fi
    if ! kill -0 "$DAEMON_PID" 2>/dev/null; then
        echo -e "${RED}Daemon died unexpectedly${NC}"
        cat /tmp/passkey_test_daemon.log
        exit 1
    fi
    sleep 0.5
done

if [ ! -S "$MCP_SOCKET" ]; then
    echo -e "${RED}Socket not created within timeout${NC}"
    cat /tmp/passkey_test_daemon.log
    exit 1
fi
echo ""

# Step 4: 正しいパスキーでの認証テスト
echo -e "${YELLOW}Step 4: Testing authentication with CORRECT passkey${NC}"

# MCP JSON-RPC リクエスト送信関数
send_request() {
    local request="$1"
    echo "$request" | nc -U "$MCP_SOCKET" | head -1
}

AUTH_REQUEST_CORRECT=$(cat << EOF
{"jsonrpc":"2.0","method":"tools/call","params":{"name":"authenticate","arguments":{"agent_id":"$TEST_AGENT_ID","passkey":"$CORRECT_PASSKEY","project_id":"$TEST_PROJECT_ID"}},"id":1}
EOF
)

CORRECT_RESPONSE=$(send_request "$AUTH_REQUEST_CORRECT")
echo "Response: $CORRECT_RESPONSE"

# 成功確認
if echo "$CORRECT_RESPONSE" | grep -q '"success":true\|"success": true'; then
    echo -e "${GREEN}Correct passkey authentication: SUCCESS${NC}"
    CORRECT_AUTH_PASSED=true
else
    echo -e "${RED}Correct passkey authentication: FAILED (unexpected)${NC}"
    CORRECT_AUTH_PASSED=false
fi
echo ""

# Step 5: 間違ったパスキーでの認証テスト
echo -e "${YELLOW}Step 5: Testing authentication with WRONG passkey${NC}"

AUTH_REQUEST_WRONG=$(cat << EOF
{"jsonrpc":"2.0","method":"tools/call","params":{"name":"authenticate","arguments":{"agent_id":"$TEST_AGENT_ID","passkey":"$WRONG_PASSKEY","project_id":"$TEST_PROJECT_ID"}},"id":2}
EOF
)

WRONG_RESPONSE=$(send_request "$AUTH_REQUEST_WRONG")
echo "Response: $WRONG_RESPONSE"

# 失敗確認
WRONG_AUTH_FAILED=false
WRONG_AUTH_HAS_EXIT=false

if echo "$WRONG_RESPONSE" | grep -q '"success":false\|"success": false'; then
    echo -e "${GREEN}Wrong passkey authentication: CORRECTLY REJECTED${NC}"
    WRONG_AUTH_FAILED=true
else
    echo -e "${RED}Wrong passkey authentication: NOT REJECTED (unexpected)${NC}"
fi

# action: exit 確認
if echo "$WRONG_RESPONSE" | grep -q '"action":"exit"\|"action": "exit"'; then
    echo -e "${GREEN}Response contains action: exit${NC}"
    WRONG_AUTH_HAS_EXIT=true
else
    echo -e "${RED}Response does NOT contain action: exit${NC}"
fi
echo ""

# Step 6: 結果判定
echo "=========================================="
echo -e "${YELLOW}Final Result: Passkey Error Verification${NC}"
echo ""

PASS_COUNT=0
FAIL_COUNT=0

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

echo "Assertions (3 items):"
check_assertion 1 "Correct passkey authentication succeeds" "$CORRECT_AUTH_PASSED"
check_assertion 2 "Wrong passkey authentication is rejected" "$WRONG_AUTH_FAILED"
check_assertion 3 "Error response contains action: exit" "$WRONG_AUTH_HAS_EXIT"

echo ""
echo "Result: $PASS_COUNT/3 assertions passed"
echo ""

if [ "$PASS_COUNT" -eq 3 ]; then
    echo -e "${GREEN}Passkey Error Integration Test: PASSED${NC}"
    exit 0
else
    echo -e "${RED}Passkey Error Integration Test: FAILED${NC}"
    echo ""
    echo "Debug info:"
    echo "  - Daemon log: /tmp/passkey_test_daemon.log"
    tail -30 /tmp/passkey_test_daemon.log
    TEST_FAILED=true
    exit 1
fi
