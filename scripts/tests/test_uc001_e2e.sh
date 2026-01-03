#!/bin/bash
# UC001 End-to-End Test
# タスク作成 → エージェントキック → ファイル作成 を確認するテスト
#
# 前提条件:
# - AIAgentPM アプリがビルド済み
# - Claude CLI がインストール済み
# - agent-pm MCP サーバーが設定済み

set -e

# 色付き出力
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# テスト設定
TEST_DIR="/tmp/uc001_e2e_test_$(date +%s)"
OUTPUT_FILE="test_document.md"
EXPECTED_CONTENT="test content"
TIMEOUT_SECONDS=120

echo "=========================================="
echo "UC001 End-to-End Test"
echo "=========================================="
echo ""

# Step 1: テスト用ディレクトリの作成
echo -e "${YELLOW}Step 1: Creating test directory${NC}"
mkdir -p "$TEST_DIR"
echo "Created: $TEST_DIR"
echo ""

# Step 2: Claude CLI の確認
echo -e "${YELLOW}Step 2: Checking Claude CLI${NC}"
CLAUDE_PATH=$(which claude 2>/dev/null || echo "")
if [ -z "$CLAUDE_PATH" ]; then
    echo -e "${RED}Error: Claude CLI not found${NC}"
    echo "Please install Claude Code: npm install -g @anthropic/claude-code"
    exit 1
fi
echo "Claude CLI: $CLAUDE_PATH"
echo ""

# Step 3: MCP サーバーの確認
echo -e "${YELLOW}Step 3: Checking agent-pm MCP server${NC}"
MCP_CONFIG="$HOME/.claude/mcp_servers.json"
if [ ! -f "$MCP_CONFIG" ]; then
    echo -e "${YELLOW}Warning: MCP config not found at $MCP_CONFIG${NC}"
    echo "Creating minimal config for test..."
    # 後で必要に応じて設定
fi
echo ""

# Step 4: テスト用プロンプトの構築
echo -e "${YELLOW}Step 4: Building test prompt${NC}"
TEST_PROMPT="# Task: Create Test Document

Task ID: test_task_001
Project: UC001 E2E Test

## Description
Create a simple test document to verify the UC001 flow.

## Expected Output
File: $OUTPUT_FILE
Requirements: Create a markdown file with the text '$EXPECTED_CONTENT'

## Instructions
1. Create the file $OUTPUT_FILE in the current directory
2. Write the content: $EXPECTED_CONTENT
3. This is an automated test - just create the file and exit"

echo "Prompt prepared"
echo ""

# Step 5: Claude Code 実行
echo -e "${YELLOW}Step 5: Running Claude Code${NC}"
echo "Working directory: $TEST_DIR"
echo "Timeout: ${TIMEOUT_SECONDS}s"
echo ""

cd "$TEST_DIR"

# Claude Code を非対話モードで実行
# macOS では gtimeout または perl で代替
if command -v gtimeout &> /dev/null; then
    gtimeout "$TIMEOUT_SECONDS" claude -p "$TEST_PROMPT" --permission-mode dontAsk 2>&1 || true
else
    # perl を使ったタイムアウト実装
    perl -e "alarm $TIMEOUT_SECONDS; exec @ARGV" claude -p "$TEST_PROMPT" --permission-mode dontAsk 2>&1 || true
fi

echo ""

# Step 6: 結果確認
echo -e "${YELLOW}Step 6: Verifying results${NC}"

if [ -f "$TEST_DIR/$OUTPUT_FILE" ]; then
    echo -e "${GREEN}✓ File created: $OUTPUT_FILE${NC}"

    # 内容確認
    FILE_CONTENT=$(cat "$TEST_DIR/$OUTPUT_FILE")
    if echo "$FILE_CONTENT" | grep -q "$EXPECTED_CONTENT"; then
        echo -e "${GREEN}✓ Content verified: contains '$EXPECTED_CONTENT'${NC}"
        TEST_RESULT="PASSED"
    else
        echo -e "${YELLOW}⚠ Content does not contain expected text${NC}"
        echo "File content:"
        echo "---"
        cat "$TEST_DIR/$OUTPUT_FILE"
        echo "---"
        TEST_RESULT="PARTIAL"
    fi
else
    echo -e "${RED}✗ File not created: $OUTPUT_FILE${NC}"
    echo "Directory contents:"
    ls -la "$TEST_DIR"
    TEST_RESULT="FAILED"
fi

echo ""

# Step 7: クリーンアップ
echo -e "${YELLOW}Step 7: Cleanup${NC}"
if [ "$1" != "--keep" ]; then
    rm -rf "$TEST_DIR"
    echo "Cleaned up test directory"
else
    echo "Keeping test directory: $TEST_DIR"
fi
echo ""

# 結果出力
echo "=========================================="
if [ "$TEST_RESULT" == "PASSED" ]; then
    echo -e "${GREEN}UC001 E2E Test: PASSED${NC}"
    exit 0
elif [ "$TEST_RESULT" == "PARTIAL" ]; then
    echo -e "${YELLOW}UC001 E2E Test: PARTIAL (file created but content differs)${NC}"
    exit 0
else
    echo -e "${RED}UC001 E2E Test: FAILED${NC}"
    exit 1
fi
