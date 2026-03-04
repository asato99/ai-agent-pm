#!/bin/bash
# scripts/cross-platform/setup-wsl2.sh
# WSL2 (Ubuntu) 上に AI Agent PM 開発環境をセットアップ
#
# 使用方法:
#   chmod +x setup-wsl2.sh
#   ./setup-wsl2.sh
#
# 前提条件:
#   - WSL2 が有効化されていること
#   - Ubuntu がインストールされていること

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}=== AI Agent PM - WSL2 開発環境セットアップ ===${NC}"
echo ""

# Check if running on WSL2
if ! grep -qi microsoft /proc/version 2>/dev/null; then
    echo -e "${YELLOW}注意: WSL2環境ではないようです。Linux環境として続行します。${NC}"
fi

# -----------------------------------------------
# Step 1: System packages
# -----------------------------------------------
echo -e "${YELLOW}Step 1: システムパッケージのインストール...${NC}"
sudo apt-get update
sudo apt-get install -y \
    curl \
    git \
    sqlite3 \
    libsqlite3-dev \
    python3 \
    python3-pip \
    python3-venv \
    build-essential \
    clang \
    libicu-dev \
    libcurl4-openssl-dev \
    libssl-dev \
    libxml2-dev \
    pkg-config \
    binutils

echo -e "${GREEN}✓ システムパッケージ完了${NC}"
echo ""

# -----------------------------------------------
# Step 2: Swift Installation
# -----------------------------------------------
echo -e "${YELLOW}Step 2: Swift のインストール...${NC}"

SWIFT_VERSION="5.10.1"
UBUNTU_VERSION=$(lsb_release -rs 2>/dev/null || echo "22.04")

if command -v swift &> /dev/null; then
    INSTALLED_SWIFT=$(swift --version 2>&1 | grep -oP 'Swift version \K[0-9.]+' || echo "unknown")
    echo -e "${GREEN}✓ Swift ${INSTALLED_SWIFT} が既にインストールされています${NC}"
else
    echo "Swift ${SWIFT_VERSION} をインストールしています..."

    # swiftly を使ったインストール（公式推奨方法）
    if command -v swiftly &> /dev/null; then
        swiftly install ${SWIFT_VERSION}
    else
        echo "swiftly をインストールしています..."
        curl -L https://swiftlang.github.io/swiftly/swiftly-install.sh | bash
        # Reload PATH
        export PATH="$HOME/.local/share/swiftly/toolchains/swift-${SWIFT_VERSION}/usr/bin:$PATH"
        source "$HOME/.local/share/swiftly/env.sh" 2>/dev/null || true
        swiftly install ${SWIFT_VERSION}
    fi

    echo -e "${GREEN}✓ Swift インストール完了${NC}"
fi

echo ""

# -----------------------------------------------
# Step 3: Node.js Installation
# -----------------------------------------------
echo -e "${YELLOW}Step 3: Node.js のインストール...${NC}"

if command -v node &> /dev/null; then
    NODE_VERSION=$(node --version)
    echo -e "${GREEN}✓ Node.js ${NODE_VERSION} が既にインストールされています${NC}"
else
    echo "Node.js をインストールしています..."

    # nvm を使ったインストール
    if [ ! -d "$HOME/.nvm" ]; then
        curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash
    fi

    export NVM_DIR="$HOME/.nvm"
    [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"

    nvm install --lts
    nvm use --lts

    echo -e "${GREEN}✓ Node.js インストール完了${NC}"
fi

echo ""

# -----------------------------------------------
# Step 4: Python Dependencies
# -----------------------------------------------
echo -e "${YELLOW}Step 4: Python 依存パッケージのインストール...${NC}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$SCRIPT_DIR/../.."

if [ -f "$PROJECT_ROOT/runner/pyproject.toml" ]; then
    cd "$PROJECT_ROOT/runner"
    python3 -m pip install -e ".[http]" 2>/dev/null || \
    pip3 install -e ".[http]" 2>/dev/null || \
    echo -e "${YELLOW}⚠ Python依存のインストールをスキップ（手動でインストールしてください）${NC}"
    cd "$PROJECT_ROOT"
    echo -e "${GREEN}✓ Python 依存パッケージ完了${NC}"
else
    echo -e "${YELLOW}⚠ runner/pyproject.toml が見つかりません（スキップ）${NC}"
fi

echo ""

# -----------------------------------------------
# Step 5: Web UI Dependencies
# -----------------------------------------------
echo -e "${YELLOW}Step 5: Web UI 依存パッケージのインストール...${NC}"

if [ -d "$PROJECT_ROOT/web-ui" ]; then
    cd "$PROJECT_ROOT/web-ui"
    npm install
    cd "$PROJECT_ROOT"
    echo -e "${GREEN}✓ Web UI 依存パッケージ完了${NC}"
else
    echo -e "${YELLOW}⚠ web-ui/ が見つかりません（スキップ）${NC}"
fi

echo ""

# -----------------------------------------------
# Step 6: Build Swift Servers
# -----------------------------------------------
echo -e "${YELLOW}Step 6: Swift サーバーのビルド...${NC}"

cd "$PROJECT_ROOT"

echo "MCPServer をビルド中..."
swift build -c release --product mcp-server-pm 2>&1 | tail -5

echo "RESTServer をビルド中..."
swift build -c release --product rest-server-pm 2>&1 | tail -5

if [ -f ".build/release/mcp-server-pm" ] && [ -f ".build/release/rest-server-pm" ]; then
    echo -e "${GREEN}✓ サーバーバイナリのビルド完了${NC}"
else
    echo -e "${RED}✗ ビルドに失敗しました。エラーを確認してください${NC}"
    echo "  手動でビルド: swift build -c release --product mcp-server-pm"
    echo "  手動でビルド: swift build -c release --product rest-server-pm"
fi

echo ""

# -----------------------------------------------
# Step 7: Create data directory
# -----------------------------------------------
echo -e "${YELLOW}Step 7: データディレクトリの作成...${NC}"

DATA_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/AIAgentPM"
mkdir -p "$DATA_DIR"
echo -e "${GREEN}✓ データディレクトリ: $DATA_DIR${NC}"

echo ""

# -----------------------------------------------
# Summary
# -----------------------------------------------
echo -e "${GREEN}=== セットアップ完了 ===${NC}"
echo ""
echo "次のステップ:"
echo "  1. サーバー起動:  ./scripts/cross-platform/start-dev.sh"
echo "  2. ブラウザで:     http://localhost:5173"
echo ""
echo "環境変数のカスタマイズ:"
echo "  AIAGENTPM_DB_PATH        - データベースパス (デフォルト: $DATA_DIR/pm.db)"
echo "  AIAGENTPM_WEBSERVER_PORT - REST APIポート (デフォルト: 8080)"
echo ""
echo -e "${YELLOW}注意: 新しいターミナルを開く場合は source ~/.bashrc を実行してください${NC}"
