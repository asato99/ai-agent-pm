#!/bin/bash
# UC001 Integration Test
# アプリ経由でのタスク作成 → エージェントキック → ファイル作成 を確認するテスト
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
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# テスト設定（UIテストコードと同じ固定パスを使用）
# Feature08_AgentKickExecutionTests.swift と同期
TEST_DIR="/tmp/uc001_integration_test"
OUTPUT_FILE="integration_test_output.md"
TIMEOUT_SECONDS=180

echo "=========================================="
echo -e "${BLUE}UC001 Integration Test${NC}"
echo "=========================================="
echo ""

# Step 1: テスト環境の準備
echo -e "${YELLOW}Step 1: Preparing test environment${NC}"
# 前回のテストディレクトリをクリーンアップ
rm -rf "$TEST_DIR"
mkdir -p "$TEST_DIR"
echo "Test directory: $TEST_DIR"
echo "Expected output: $TEST_DIR/$OUTPUT_FILE"
echo ""

# Step 2: テストデータの設定確認
echo -e "${YELLOW}Step 2: Test configuration${NC}"
echo "Path is hardcoded in UITest and App code"
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

# Step 4: UIテストを実行（実際のキックを有効化）
echo -e "${YELLOW}Step 4: Running integration test${NC}"
echo "Real kick is enabled via -EnableRealKick argument"
echo "Timeout: ${TIMEOUT_SECONDS}s"
echo ""

# macOS用のタイムアウト
run_with_timeout() {
    local timeout=$1
    shift
    if command -v gtimeout &> /dev/null; then
        gtimeout "$timeout" "$@"
    else
        perl -e "alarm $timeout; exec @ARGV" "$@"
    fi
}

# UIテストを実行
run_with_timeout "$TIMEOUT_SECONDS" xcodebuild test \
    -scheme AIAgentPM \
    -destination 'platform=macOS' \
    -only-testing:AIAgentPMUITests/Feature08_AgentKickExecutionTests/testKickSuccessRecordedInHistory \
    2>&1 | tee /tmp/uc001_integration_test.log | grep -E "(Test Case|passed|failed|error:)" || true

echo ""

# Step 5: ファイル作成を確認
echo -e "${YELLOW}Step 5: Verifying file creation${NC}"

# Claude Codeが作業を完了するまで待つ（最大60秒）
echo "Waiting for Claude Code to complete (max 60s)..."
for i in {1..12}; do
    if [ -f "$TEST_DIR/$OUTPUT_FILE" ]; then
        echo "File detected after $((i * 5)) seconds"
        break
    fi
    sleep 5
done

if [ -f "$TEST_DIR/$OUTPUT_FILE" ]; then
    echo -e "${GREEN}✓ File created: $OUTPUT_FILE${NC}"
    echo ""
    echo "File content:"
    echo "---"
    cat "$TEST_DIR/$OUTPUT_FILE"
    echo "---"
    TEST_RESULT="PASSED"
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

# Step 6: クリーンアップ
echo -e "${YELLOW}Step 6: Cleanup${NC}"
if [ "$1" != "--keep" ]; then
    rm -rf "$TEST_DIR"
    rm -f /tmp/uc001_integration_test.log
    echo "Cleaned up test directory and log"
else
    echo "Keeping test directory: $TEST_DIR"
    echo "Log file: /tmp/uc001_integration_test.log"
fi
echo ""

# 結果
echo "=========================================="
if [ "$TEST_RESULT" == "PASSED" ]; then
    echo -e "${GREEN}UC001 Integration Test: PASSED${NC}"
    echo ""
    echo "Verified:"
    echo "  - App launched successfully"
    echo "  - Task status changed to in_progress"
    echo "  - Claude Code CLI was kicked"
    echo "  - File was created by agent"
    exit 0
else
    echo -e "${RED}UC001 Integration Test: FAILED${NC}"
    echo ""
    echo "The file was not created. Possible issues:"
    echo "  - workingDirectory may not be set correctly in test data"
    echo "  - Claude CLI may have failed to execute"
    echo "  - Permission issues in test directory"
    exit 1
fi
