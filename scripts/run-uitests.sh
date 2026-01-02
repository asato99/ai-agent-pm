#!/bin/bash
# scripts/run-uitests.sh
# UIテスト実行スクリプト - Aquaセッション内で実行する必要があります
#
# 使用方法:
#   方法1: Terminal.appから直接実行
#     ./scripts/run-uitests.sh
#
#   方法2: 任意のターミナルからAquaセッションで実行
#     osascript -e 'tell application "Terminal" to do script "cd /path/to/project && ./scripts/run-uitests.sh"'

set -e

# プロジェクトディレクトリに移動
cd "$(dirname "$0")/.."
PROJECT_DIR=$(pwd)

echo "=========================================="
echo "AIAgentPM UITest Runner"
echo "=========================================="
echo "Project: $PROJECT_DIR"
echo "Date: $(date)"
echo ""

# 環境チェック
echo "=== Environment Check ==="
echo "User: $(whoami)"
echo "UID: $(id -u)"

# WindowServerの確認
if pgrep -x WindowServer > /dev/null; then
    echo "WindowServer: Running (required for XCUITest)"
else
    echo "ERROR: WindowServer is not running. GUI session required."
    exit 1
fi

# GUIセッションの確認
if launchctl print gui/$(id -u) 2>&1 | grep -q "session = Aqua"; then
    echo "Session: Aqua (GUI session)"
else
    echo "WARNING: May not be in Aqua session. XCUITest may fail."
fi

echo ""

# xcodegen確認・実行
echo "=== Generating Xcode Project ==="
if command -v xcodegen &> /dev/null; then
    xcodegen generate
else
    echo "ERROR: xcodegen not found. Install with: brew install xcodegen"
    exit 1
fi

echo ""

# ビルドとテスト実行
echo "=== Running UI Tests ==="
RESULT_BUNDLE="/tmp/AIAgentPM-UITestResults-$(date +%Y%m%d-%H%M%S).xcresult"

xcodebuild test \
    -project AIAgentPM.xcodeproj \
    -scheme AIAgentPM \
    -destination 'platform=macOS' \
    -resultBundlePath "$RESULT_BUNDLE" \
    2>&1 | tee /tmp/uitest-output.log

EXIT_CODE=${PIPESTATUS[0]}

echo ""
echo "=========================================="
echo "Test Complete"
echo "=========================================="
echo "Exit code: $EXIT_CODE"
echo "Result bundle: $RESULT_BUNDLE"
echo "Log file: /tmp/uitest-output.log"

if [ $EXIT_CODE -eq 0 ]; then
    echo "Status: SUCCESS"
else
    echo "Status: FAILED"
    echo ""
    echo "=== Last 50 lines of output ==="
    tail -50 /tmp/uitest-output.log
fi

exit $EXIT_CODE
