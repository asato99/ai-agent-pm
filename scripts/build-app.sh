#!/bin/bash
# scripts/build-app.sh
# Web UIビルド + macOSアプリビルドを一括実行
#
# オプション:
#   --clean    DerivedDataをクリーンしてからビルド
#   --launch   ビルド後にアプリを起動
#   --help     ヘルプを表示

set -e

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

# オプション解析
CLEAN_BUILD=false
LAUNCH_AFTER=false

for arg in "$@"; do
    case $arg in
        --clean)
            CLEAN_BUILD=true
            ;;
        --launch)
            LAUNCH_AFTER=true
            ;;
        --help)
            echo "Usage: $0 [--clean] [--launch]"
            echo "  --clean   Clean DerivedData before build"
            echo "  --launch  Launch app after build (※Xcodeでデバッグ中は使用不可)"
            exit 0
            ;;
    esac
done

echo "📁 Project: $PROJECT_DIR"

# 0. 古いプロセスを終了（最新のビルドを確実に反映するため）
echo ""
echo "🛑 Stopping existing processes..."

# AIAgentPM.appを終了
if pgrep -f "AIAgentPM.app" > /dev/null 2>&1; then
    pkill -f "AIAgentPM.app" 2>/dev/null || true
    echo "   Stopped: AIAgentPM.app"
    sleep 1
fi

# rest-server-pmを終了
if pgrep -f "rest-server-pm" > /dev/null 2>&1; then
    pkill -f "rest-server-pm" 2>/dev/null || true
    echo "   Stopped: rest-server-pm"
fi

# mcp-server-pm daemonを終了（Claude Codeで使用中のものは除外）
# 注意: .build/debug/mcp-server-pm はClaude Code MCPで使用中なので終了しない
if pgrep -f "DerivedData.*mcp-server-pm daemon" > /dev/null 2>&1; then
    pkill -f "DerivedData.*mcp-server-pm daemon" 2>/dev/null || true
    echo "   Stopped: mcp-server-pm daemon (DerivedData)"
fi

echo "   Done"

# クリーンビルドオプション
if [ "$CLEAN_BUILD" = true ]; then
    echo ""
    echo "🧹 Cleaning DerivedData..."
    DERIVED_DATA_PATH=$(find ~/Library/Developer/Xcode/DerivedData -maxdepth 1 -name "AIAgentPM-*" -type d 2>/dev/null | head -1)
    if [ -n "$DERIVED_DATA_PATH" ]; then
        rm -rf "$DERIVED_DATA_PATH"
        echo "   Removed: $DERIVED_DATA_PATH"
    else
        echo "   No DerivedData found"
    fi
fi

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

# Find the app (exclude Index.noindex path which may have incomplete builds)
APP_PATH=$(find ~/Library/Developer/Xcode/DerivedData -path "*/Build/Products/Debug/AIAgentPM.app" -not -path "*/Index.noindex/*" -type d 2>/dev/null | head -1)
echo ""
echo "📍 App location:"
echo "   $APP_PATH"

# --launch オプションでアプリを起動
if [ "$LAUNCH_AFTER" = true ] && [ -n "$APP_PATH" ]; then
    echo ""
    echo "🚀 Launching app..."
    open "$APP_PATH"
    echo "   App started"
fi
