#!/bin/bash
# scripts/cross-platform/start-dev.sh
# AI Agent PM 開発環境起動スクリプト（macOS / Linux / WSL2 共通）
#
# 使用方法:
#   ./start-dev.sh                    # デフォルト設定で起動
#   ./start-dev.sh --port 8085        # REST APIポートを指定
#   ./start-dev.sh --db /tmp/test.db  # DBパスを指定
#   ./start-dev.sh --no-webui         # Web UI なしで起動
#
# 起動されるサービス:
#   1. REST API サーバー (デフォルト: localhost:8080)
#   2. Web UI 開発サーバー (デフォルト: localhost:5173)

set -e

# -----------------------------------------------
# Configuration
# -----------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$SCRIPT_DIR/../.."

# Defaults
REST_PORT="${AIAGENTPM_WEBSERVER_PORT:-8080}"
DB_PATH="${AIAGENTPM_DB_PATH:-}"
START_WEBUI=true
WEBUI_PORT=5173

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --port)
            REST_PORT="$2"
            shift 2
            ;;
        --db)
            DB_PATH="$2"
            shift 2
            ;;
        --no-webui)
            START_WEBUI=false
            shift
            ;;
        --webui-port)
            WEBUI_PORT="$2"
            shift 2
            ;;
        --help|-h)
            echo "使用方法: $0 [オプション]"
            echo ""
            echo "オプション:"
            echo "  --port <port>       REST APIポート (デフォルト: 8080)"
            echo "  --db <path>         データベースパス"
            echo "  --no-webui          Web UI を起動しない"
            echo "  --webui-port <port> Web UI ポート (デフォルト: 5173)"
            echo "  -h, --help          このヘルプを表示"
            exit 0
            ;;
        *)
            echo "不明なオプション: $1"
            exit 1
            ;;
    esac
done

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# PID tracking for cleanup
PIDS=()

cleanup() {
    echo ""
    echo -e "${YELLOW}=== サーバーを停止中 ===${NC}"
    for pid in "${PIDS[@]}"; do
        if kill -0 "$pid" 2>/dev/null; then
            kill "$pid" 2>/dev/null || true
            wait "$pid" 2>/dev/null || true
        fi
    done
    echo -e "${GREEN}停止完了${NC}"
}

trap cleanup EXIT INT TERM

# -----------------------------------------------
# Step 1: Find server binaries
# -----------------------------------------------
echo -e "${CYAN}=== AI Agent PM 開発環境 ===${NC}"
echo ""

REST_SERVER_BIN=""

# Check SPM release build
if [ -f "$PROJECT_ROOT/.build/release/rest-server-pm" ]; then
    REST_SERVER_BIN="$PROJECT_ROOT/.build/release/rest-server-pm"
fi

# Check SPM debug build
if [ -z "$REST_SERVER_BIN" ] && [ -f "$PROJECT_ROOT/.build/debug/rest-server-pm" ]; then
    REST_SERVER_BIN="$PROJECT_ROOT/.build/debug/rest-server-pm"
fi

# macOS: Check Xcode DerivedData
if [ -z "$REST_SERVER_BIN" ] && [ "$(uname)" = "Darwin" ]; then
    DERIVED_DATA_DIR=$(find ~/Library/Developer/Xcode/DerivedData -maxdepth 1 -name "AIAgentPM-*" -type d 2>/dev/null | head -1)
    if [ -n "$DERIVED_DATA_DIR" ]; then
        for config in Debug Release; do
            candidate="$DERIVED_DATA_DIR/Build/Products/$config/rest-server-pm"
            if [ -x "$candidate" ]; then
                REST_SERVER_BIN="$candidate"
                break
            fi
        done
    fi
fi

if [ -z "$REST_SERVER_BIN" ]; then
    echo -e "${RED}✗ REST サーバーバイナリが見つかりません${NC}"
    echo ""
    echo "ビルドしてください:"
    echo "  swift build -c release --product rest-server-pm"
    exit 1
fi

echo -e "${GREEN}✓ REST サーバー: $REST_SERVER_BIN${NC}"

# -----------------------------------------------
# Step 2: Setup database
# -----------------------------------------------
if [ -z "$DB_PATH" ]; then
    # Use platform-appropriate default
    if [ "$(uname)" = "Darwin" ]; then
        DB_PATH="$HOME/Library/Application Support/AIAgentPM/pm.db"
    else
        DB_PATH="${XDG_DATA_HOME:-$HOME/.local/share}/AIAgentPM/pm.db"
    fi
fi

export AIAGENTPM_DB_PATH="$DB_PATH"

# Create directory if needed
DB_DIR=$(dirname "$DB_PATH")
mkdir -p "$DB_DIR"

if [ ! -f "$DB_PATH" ]; then
    echo -e "${YELLOW}データベースが見つかりません: $DB_PATH${NC}"
    echo "初期セットアップを実行します..."

    # Find MCP server binary (same search logic)
    MCP_SERVER_BIN=""
    if [ -f "$PROJECT_ROOT/.build/release/mcp-server-pm" ]; then
        MCP_SERVER_BIN="$PROJECT_ROOT/.build/release/mcp-server-pm"
    elif [ -f "$PROJECT_ROOT/.build/debug/mcp-server-pm" ]; then
        MCP_SERVER_BIN="$PROJECT_ROOT/.build/debug/mcp-server-pm"
    fi

    if [ -n "$MCP_SERVER_BIN" ]; then
        AIAGENTPM_DB_PATH="$DB_PATH" "$MCP_SERVER_BIN" setup
        echo -e "${GREEN}✓ 初期セットアップ完了${NC}"
    else
        echo -e "${RED}✗ MCP サーバーバイナリが見つかりません（セットアップスキップ）${NC}"
    fi
fi

echo -e "${GREEN}✓ データベース: $DB_PATH${NC}"

# -----------------------------------------------
# Step 3: Start REST server
# -----------------------------------------------
echo ""
echo -e "${YELLOW}REST サーバーを起動中 (port: $REST_PORT)...${NC}"

export AIAGENTPM_WEBSERVER_PORT="$REST_PORT"

"$REST_SERVER_BIN" &
REST_PID=$!
PIDS+=($REST_PID)

# Wait for REST server to be ready
for i in $(seq 1 30); do
    if curl -s "http://localhost:$REST_PORT/health" > /dev/null 2>&1; then
        echo -e "${GREEN}✓ REST サーバー起動完了 (PID: $REST_PID)${NC}"
        break
    fi
    if [ $i -eq 30 ]; then
        echo -e "${RED}✗ REST サーバーの起動に失敗しました${NC}"
        exit 1
    fi
    sleep 1
done

# -----------------------------------------------
# Step 4: Start Web UI (optional)
# -----------------------------------------------
if [ "$START_WEBUI" = true ] && [ -d "$PROJECT_ROOT/web-ui" ]; then
    echo ""
    echo -e "${YELLOW}Web UI を起動中 (port: $WEBUI_PORT)...${NC}"

    cd "$PROJECT_ROOT/web-ui"

    # Check if node_modules exists
    if [ ! -d "node_modules" ]; then
        echo "npm install を実行中..."
        npm install
    fi

    # Start Vite dev server
    VITE_API_PORT=$REST_PORT npx vite --port $WEBUI_PORT &
    WEBUI_PID=$!
    PIDS+=($WEBUI_PID)

    cd "$PROJECT_ROOT"

    # Wait for Web UI to be ready
    for i in $(seq 1 20); do
        if curl -s "http://localhost:$WEBUI_PORT" > /dev/null 2>&1; then
            echo -e "${GREEN}✓ Web UI 起動完了 (PID: $WEBUI_PID)${NC}"
            break
        fi
        if [ $i -eq 20 ]; then
            echo -e "${YELLOW}⚠ Web UI の起動を確認できませんでした（バックグラウンドで起動中かもしれません）${NC}"
        fi
        sleep 1
    done
fi

# -----------------------------------------------
# Summary
# -----------------------------------------------
echo ""
echo -e "${GREEN}=== 開発環境が起動しました ===${NC}"
echo ""
echo -e "  REST API:  ${CYAN}http://localhost:$REST_PORT${NC}"
if [ "$START_WEBUI" = true ]; then
    echo -e "  Web UI:    ${CYAN}http://localhost:$WEBUI_PORT${NC}"
fi
echo -e "  DB:        ${CYAN}$DB_PATH${NC}"
echo ""
echo -e "${YELLOW}Ctrl+C で停止${NC}"
echo ""

# Wait for all processes
wait
