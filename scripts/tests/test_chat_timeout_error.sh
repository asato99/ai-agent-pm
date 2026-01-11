#!/bin/bash
# Chat Timeout Error Integration Test
# パスキー間違いによる認証失敗後のチャットタイムアウトエラーを確認する統合テスト
#
# シナリオ:
#   1. チャットメッセージ送信 → pending_agent_purpose作成
#   2. get_agent_action → action: "start" + started_atマーク
#   3. パスキー間違いで authenticate 失敗 → エージェント終了
#   4. pending_agent_purposeは削除されない（認証未完了）
#   5. TTL経過後の get_agent_action → タイムアウトエラー
#
# 検証項目:
#   1. 認証失敗時に action: "exit" が返される
#   2. TTL経過後に pending_purpose_expired エラーが返される
#   3. 設定したTTL値がエラーメッセージに反映される

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
TEST_DB="/tmp/chat_timeout_test.db"
MCP_SOCKET="/tmp/chat_timeout_test.sock"
TEST_AGENT_ID="agt_timeout_test"
TEST_PROJECT_ID="prj_timeout_test"
CORRECT_PASSKEY="correct_passkey_12345"
WRONG_PASSKEY="wrong_passkey_99999"
COORDINATOR_TOKEN="test_coordinator_token"

# TTL設定（テスト用に5秒）
TEST_TTL_SECONDS=5

# チャットファイルパス
WORKING_DIR="/tmp/timeout_test"
CHAT_FILE="$WORKING_DIR/.ai-pm/agents/$TEST_AGENT_ID/chat.jsonl"

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
    rm -f /tmp/chat_timeout_daemon.log
    rm -rf "$WORKING_DIR"
}

trap 'if [ $? -ne 0 ]; then TEST_FAILED=true; fi; cleanup' EXIT

echo "=========================================="
echo -e "${BLUE}Chat Timeout Error Integration Test${NC}"
echo "=========================================="
echo ""

# Step 1: MCPサーバービルド
echo -e "${YELLOW}Step 1: Building MCP server${NC}"
cd "$PROJECT_ROOT"
swift build --product mcp-server-pm 2>&1 | tail -3 || {
    echo -e "${RED}Failed to build MCP server${NC}"
    exit 1
}
MCP_SERVER="$PROJECT_ROOT/.build/debug/mcp-server-pm"
echo "MCP server built: $MCP_SERVER"
echo ""

# Step 2: テストDB作成とシード
echo -e "${YELLOW}Step 2: Creating test database with seed data${NC}"
rm -f "$TEST_DB" "$TEST_DB-shm" "$TEST_DB-wal"

# setupコマンドでDBを作成（マイグレーション込み）
AIAGENTPM_DB_PATH="$TEST_DB" "$MCP_SERVER" setup 2>&1 | tail -3 || {
    echo -e "${RED}Failed to create test database${NC}"
    exit 1
}

# シードデータ挿入
# パスキーハッシュはソルト+SHA256で計算（アプリと同じ方式）
SALT="test_salt_12345"
PASSKEY_HASH=$(echo -n "${SALT}${CORRECT_PASSKEY}" | shasum -a 256 | cut -d' ' -f1)
NOW=$(date -u +"%Y-%m-%d %H:%M:%S")

sqlite3 "$TEST_DB" << SEED
-- プロジェクト
INSERT INTO projects (id, name, description, status, working_directory, created_at, updated_at)
VALUES ('$TEST_PROJECT_ID', 'Timeout Test Project', 'Test project for timeout verification', 'active', '/tmp/timeout_test', '$NOW', '$NOW');

-- エージェント
INSERT INTO agents (id, name, role, type, status, created_at, updated_at)
VALUES ('$TEST_AGENT_ID', 'Timeout Test Agent', 'tester', 'executor', 'inactive', '$NOW', '$NOW');

-- パスキー（ソルト+SHA256ハッシュ）
INSERT INTO agent_credentials (id, agent_id, passkey_hash, salt, created_at)
VALUES ('cred_$TEST_AGENT_ID', '$TEST_AGENT_ID', '$PASSKEY_HASH', '$SALT', '$NOW');

-- プロジェクト-エージェント割り当て（テーブル名はproject_agents）
INSERT INTO project_agents (project_id, agent_id, assigned_at)
VALUES ('$TEST_PROJECT_ID', '$TEST_AGENT_ID', '$NOW');

-- アプリ設定（TTLを短く設定）
INSERT OR REPLACE INTO app_settings (id, coordinator_token, pending_purpose_ttl_seconds, created_at, updated_at)
VALUES ('app_settings', '$COORDINATOR_TOKEN', $TEST_TTL_SECONDS, '$NOW', '$NOW');
SEED

echo "Test database created: $TEST_DB"
echo "  Agent: $TEST_AGENT_ID"
echo "  Project: $TEST_PROJECT_ID"
echo "  TTL: ${TEST_TTL_SECONDS}秒"
echo ""

# Step 3: MCPデーモン起動
echo -e "${YELLOW}Step 3: Starting MCP daemon${NC}"
rm -f "$MCP_SOCKET"

# daemon サブコマンドを使用（環境変数でDBパスとcoordinator_tokenを指定）
AIAGENTPM_DB_PATH="$TEST_DB" MCP_COORDINATOR_TOKEN="$COORDINATOR_TOKEN" "$MCP_SERVER" daemon --socket-path "$MCP_SOCKET" --foreground > /tmp/chat_timeout_daemon.log 2>&1 &
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
        cat /tmp/chat_timeout_daemon.log
        exit 1
    fi
    sleep 0.5
done

if [ ! -S "$MCP_SOCKET" ]; then
    echo -e "${RED}Socket not created within timeout${NC}"
    cat /tmp/chat_timeout_daemon.log
    exit 1
fi
echo ""

# MCP JSON-RPC リクエスト送信関数
send_request() {
    local request="$1"
    echo "$request" | nc -U "$MCP_SOCKET" | head -1
}

# Step 4: チャットメッセージ送信をシミュレート（pending_agent_purpose作成 + チャットファイル作成）
echo -e "${YELLOW}Step 4: Simulating chat message (creating pending_agent_purpose and chat file)${NC}"

# チャットディレクトリ作成
mkdir -p "$(dirname "$CHAT_FILE")"

# ユーザーメッセージをチャットファイルに追記
USER_MSG_ID="msg_$(date +%s)"
USER_MSG_TIME=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
echo "{\"id\":\"$USER_MSG_ID\",\"sender\":\"user\",\"content\":\"テストメッセージ\",\"createdAt\":\"$USER_MSG_TIME\"}" >> "$CHAT_FILE"
echo "Chat file created: $CHAT_FILE"

# DBに直接pending_agent_purposeを作成
sqlite3 "$TEST_DB" << SEED
INSERT INTO pending_agent_purposes (agent_id, project_id, purpose, created_at)
VALUES ('$TEST_AGENT_ID', '$TEST_PROJECT_ID', 'chat', datetime('now'));
SEED

echo "pending_agent_purpose created (purpose=chat)"
echo ""

# Step 5: get_agent_action → action: "start"
echo -e "${YELLOW}Step 5: Calling get_agent_action (should return start)${NC}"

GET_ACTION_REQUEST=$(cat << EOF
{"jsonrpc":"2.0","method":"tools/call","params":{"name":"get_agent_action","arguments":{"agent_id":"$TEST_AGENT_ID","project_id":"$TEST_PROJECT_ID","coordinator_token":"$COORDINATOR_TOKEN"}},"id":1}
EOF
)

START_RESPONSE=$(send_request "$GET_ACTION_REQUEST")
echo "Response: $START_RESPONSE"

if echo "$START_RESPONSE" | grep -qE 'action.*start'; then
    echo -e "${GREEN}get_agent_action returned action: start${NC}"
    GOT_START_ACTION=true
else
    echo -e "${RED}get_agent_action did NOT return action: start${NC}"
    GOT_START_ACTION=false
fi
echo ""

# Step 6: パスキー間違いで認証失敗
echo -e "${YELLOW}Step 6: Authenticating with WRONG passkey (should fail with action: exit)${NC}"

AUTH_REQUEST_WRONG=$(cat << EOF
{"jsonrpc":"2.0","method":"tools/call","params":{"name":"authenticate","arguments":{"agent_id":"$TEST_AGENT_ID","passkey":"$WRONG_PASSKEY","project_id":"$TEST_PROJECT_ID"}},"id":2}
EOF
)

AUTH_RESPONSE=$(send_request "$AUTH_REQUEST_WRONG")
echo "Response: $AUTH_RESPONSE"

AUTH_FAILED=false
AUTH_HAS_EXIT=false

if echo "$AUTH_RESPONSE" | grep -qE 'success.*false'; then
    echo -e "${GREEN}Authentication correctly rejected${NC}"
    AUTH_FAILED=true
fi

if echo "$AUTH_RESPONSE" | grep -qE 'action.*exit'; then
    echo -e "${GREEN}Response contains action: exit${NC}"
    AUTH_HAS_EXIT=true
fi
echo ""

# Step 7: TTL経過を待機
echo -e "${YELLOW}Step 7: Waiting for TTL to expire (${TEST_TTL_SECONDS} seconds + 2 seconds buffer)${NC}"
sleep $((TEST_TTL_SECONDS + 2))
echo "TTL expired"
echo ""

# Step 8: 再度 get_agent_action → タイムアウト処理
echo -e "${YELLOW}Step 8: Calling get_agent_action after TTL (should trigger timeout handling)${NC}"

TIMEOUT_RESPONSE=$(send_request "$GET_ACTION_REQUEST")
echo "Response: $TIMEOUT_RESPONSE"

TIMEOUT_HOLD=false
if echo "$TIMEOUT_RESPONSE" | grep -qE 'action.*hold'; then
    echo -e "${GREEN}Response contains action: hold${NC}"
    TIMEOUT_HOLD=true
fi
echo ""

# Step 9: チャットファイルにシステムエラーメッセージが書き込まれたことを確認
echo -e "${YELLOW}Step 9: Verifying system error message in chat file${NC}"

CHAT_HAS_SYSTEM_ERROR=false
if [ -f "$CHAT_FILE" ]; then
    echo "Chat file contents:"
    cat "$CHAT_FILE"
    echo ""

    if grep -q '"sender":"system"' "$CHAT_FILE" && grep -q 'タイムアウト' "$CHAT_FILE"; then
        echo -e "${GREEN}System error message found in chat file${NC}"
        CHAT_HAS_SYSTEM_ERROR=true
    else
        echo -e "${RED}System error message NOT found in chat file${NC}"
    fi
else
    echo -e "${RED}Chat file not found: $CHAT_FILE${NC}"
fi
echo ""

# Step 10: pending_agent_purposeが削除されたことを確認
echo -e "${YELLOW}Step 10: Verifying pending_agent_purpose is deleted${NC}"

REMAINING_PURPOSES=$(sqlite3 "$TEST_DB" "SELECT COUNT(*) FROM pending_agent_purposes WHERE agent_id='$TEST_AGENT_ID' AND project_id='$TEST_PROJECT_ID';")
echo "Remaining pending_agent_purposes: $REMAINING_PURPOSES"

PURPOSE_DELETED=false
if [ "$REMAINING_PURPOSES" = "0" ]; then
    echo -e "${GREEN}pending_agent_purpose correctly deleted${NC}"
    PURPOSE_DELETED=true
else
    echo -e "${RED}pending_agent_purpose NOT deleted (count: $REMAINING_PURPOSES)${NC}"
fi
echo ""

# Step 11: 結果判定
echo "=========================================="
echo -e "${YELLOW}Final Result: Chat Timeout Error Verification${NC}"
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

echo "Assertions (6 items):"
check_assertion 1 "get_agent_action returns action: start" "$GOT_START_ACTION"
check_assertion 2 "Wrong passkey authentication is rejected" "$AUTH_FAILED"
check_assertion 3 "Auth failure response contains action: exit" "$AUTH_HAS_EXIT"
check_assertion 4 "After TTL, get_agent_action returns action: hold" "$TIMEOUT_HOLD"
check_assertion 5 "System error message written to chat file" "$CHAT_HAS_SYSTEM_ERROR"
check_assertion 6 "pending_agent_purpose is deleted after TTL" "$PURPOSE_DELETED"

echo ""
echo "Result: $PASS_COUNT/6 assertions passed"
echo ""

if [ "$PASS_COUNT" -eq 6 ]; then
    echo -e "${GREEN}Chat Timeout Error Integration Test: PASSED${NC}"
    exit 0
else
    echo -e "${RED}Chat Timeout Error Integration Test: FAILED${NC}"
    echo ""
    echo "Debug info:"
    echo "  - Daemon log: /tmp/chat_timeout_daemon.log"
    echo "  - Chat file: $CHAT_FILE"
    echo ""
    echo "Daemon log (last 50 lines):"
    tail -50 /tmp/chat_timeout_daemon.log
    TEST_FAILED=true
    exit 1
fi
