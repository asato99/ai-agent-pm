#!/bin/bash
# AI Agent PM インストールスクリプト

set -e

echo "================================"
echo "AI Agent PM インストーラー"
echo "================================"
echo ""

# プロジェクトディレクトリに移動
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

# ビルド
echo "1. ビルド中..."
swift build -c release --quiet
echo "   ✓ ビルド完了"
echo ""

# インストール先
INSTALL_DIR="$HOME/.local/bin"
EXECUTABLE="$SCRIPT_DIR/.build/release/mcp-server-pm"

# インストールディレクトリ作成
mkdir -p "$INSTALL_DIR"

# コピー
echo "2. バイナリをインストール中..."
cp "$EXECUTABLE" "$INSTALL_DIR/mcp-server-pm"
chmod +x "$INSTALL_DIR/mcp-server-pm"
echo "   ✓ $INSTALL_DIR/mcp-server-pm"
echo ""

# PATHに追加されているか確認
if [[ ":$PATH:" != *":$INSTALL_DIR:"* ]]; then
    echo "⚠ $INSTALL_DIR がPATHに含まれていません"
    echo "  以下を ~/.zshrc または ~/.bashrc に追加してください:"
    echo ""
    echo "    export PATH=\"\$HOME/.local/bin:\$PATH\""
    echo ""
fi

# Claude Code CLI設定
echo "3. Claude Code CLIに登録中..."
"$INSTALL_DIR/mcp-server-pm" install --force
echo ""

echo "================================"
echo "インストール完了!"
echo "================================"
echo ""
echo "Claude Codeを再起動してください。"
echo ""
echo "動作確認:"
echo "  Claude Codeで「get_my_profileを呼び出して」と入力"
echo ""
echo "その他のコマンド:"
echo "  mcp-server-pm status   # 状態確認"
echo "  mcp-server-pm setup    # 手動セットアップ"
echo "  mcp-server-pm --help   # ヘルプ"
