# AI Agent PM - セットアップガイド

## クイックインストール

```bash
cd /Users/kazuasato/Documents/dev/business/pm
./install.sh
```

これだけでOK。Claude Codeを再起動すれば使えます。

---

## 手動インストール

### 1. ビルド

```bash
swift build -c release
```

### 2. バイナリをインストール

```bash
mkdir -p ~/.local/bin
cp .build/release/mcp-server-pm ~/.local/bin/
chmod +x ~/.local/bin/mcp-server-pm
```

### 3. Claude Code CLIに登録

```bash
~/.local/bin/mcp-server-pm install
```

または直接:
```bash
claude mcp add -s user agent-pm ~/.local/bin/mcp-server-pm
```

### 4. 確認

```bash
claude mcp list | grep agent-pm
```

---

## コマンド一覧

| コマンド | 説明 |
|---------|------|
| `mcp-server-pm setup` | DB作成、デフォルトデータ投入 |
| `mcp-server-pm setup --with-sample-tasks` | サンプルタスク付きでセットアップ |
| `mcp-server-pm install` | Claude Code CLIにMCPサーバーを登録 |
| `mcp-server-pm install --force` | 既存の登録を上書き |
| `mcp-server-pm status` | 現在の状態を表示 |
| `mcp-server-pm serve` | MCPサーバー起動（通常は自動） |
| `mcp-server-pm --help` | ヘルプ表示 |

---

## 動作確認

Claude Codeで以下を試してください:

```
get_my_profileを呼び出して
```

期待結果:
```json
{
  "id": "agt_claude",
  "name": "Claude Code",
  "role": "AI Assistant",
  "type": "ai"
}
```

---

## データ保存場所

| 種類 | パス |
|------|------|
| データベース | `~/Library/Application Support/AIAgentPM/data.db` |
| MCPサーバー設定 | `~/.claude.json` (Claude Code CLI) |

---

## トラブルシューティング

### MCPサーバーが認識されない

```bash
# 状態確認
claude mcp list | grep agent-pm

# 再登録
mcp-server-pm install --force

# Claude Codeを再起動
```

### 接続に失敗する場合

```bash
# サーバーの動作テスト
echo '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}' | ~/.local/bin/mcp-server-pm

# デバッグモードで実行
MCP_DEBUG=1 ~/.local/bin/mcp-server-pm
```

### データベースをリセットしたい

```bash
rm -rf ~/Library/Application\ Support/AIAgentPM
mcp-server-pm setup --with-sample-tasks
```

---

## 関連ドキュメント

- [Phase 1 実装プラン](./docs/plan/PHASE1_MCP_VERIFICATION.md)
- [Phase 2 実装プラン](./docs/plan/PHASE2_FULL_IMPLEMENTATION.md)
- [MCP設計](./docs/prd/MCP_DESIGN.md)
- [アーキテクチャ](./docs/architecture/README.md)
