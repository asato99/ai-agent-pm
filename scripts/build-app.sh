#!/bin/bash
# scripts/build-app.sh
# Web UIビルド + macOSアプリビルドを一括実行

set -e

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
echo "📁 Project: $PROJECT_DIR"

# 1. Web UIビルド
echo ""
echo "🌐 Building Web UI..."
cd "$PROJECT_DIR/web-ui"

if [ ! -d "node_modules" ]; then
    echo "📦 Installing dependencies..."
    npm install
fi

npm run build
echo "✅ Web UI built: web-ui/dist/"

# 2. XcodeGenでプロジェクト生成（必要な場合）
cd "$PROJECT_DIR"
if command -v xcodegen &> /dev/null; then
    echo ""
    echo "🔧 Generating Xcode project..."
    xcodegen generate
fi

# 3. MCPサーバービルド
echo ""
echo "🔌 Building MCP server..."
xcodebuild -scheme MCPServer -destination 'platform=macOS' build 2>&1 | tail -3
if [ ${PIPESTATUS[0]} -ne 0 ]; then
    echo "❌ MCP server build failed"
    exit 1
fi
echo "✅ MCP server built"

# 4. macOSアプリビルド
echo ""
echo "🍎 Building macOS app..."
xcodebuild -scheme AIAgentPM -destination 'platform=macOS' build 2>&1 | tail -5
if [ ${PIPESTATUS[0]} -ne 0 ]; then
    echo "❌ App build failed"
    exit 1
fi

echo ""
echo "✅ Build complete!"
echo ""
echo "📍 App location:"
echo "   $(find ~/Library/Developer/Xcode/DerivedData -name 'AIAgentPM.app' -type d 2>/dev/null | head -1)"
