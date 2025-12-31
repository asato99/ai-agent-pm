# システム構成

アーキテクチャ概要と技術スタックの設計。

---

## アーキテクチャ概要

```
┌─────────────────────────────────────────────────────────────┐
│  Claude Code                                                │
│      ↓ stdio (MCP Protocol)                                 │
└─────────────────────────────────────────────────────────────┘
        ↓
┌─────────────────────────────────────────────────────────────┐
│  mcp-server-pm (別プロセス CLI)                             │
│  - MCP Protocol処理                                         │
│  - Tools / Resources / Prompts 提供                         │
│  - 軽量・常時起動可能                                        │
└───────────────────────────┬─────────────────────────────────┘
                            │ 共有SQLiteファイル
                            ▼
┌─────────────────────────────────────────────────────────────┐
│  ~/Library/Application Support/AI Agent PM/data.db          │
└───────────────────────────┬─────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│  AI Agent PM.app (SwiftUI)                                  │
│  ┌─────────────────────────────────────────────────────┐   │
│  │  Human UI                                            │   │
│  │  - Project View / Task Board / Agent Activity View   │   │
│  └─────────────────────────────────────────────────────┘   │
│  ┌─────────────────────────────────────────────────────┐   │
│  │  Core (Clean Architecture)                           │   │
│  │  Domain → UseCases → Interface → Infrastructure      │   │
│  └─────────────────────────────────────────────────────┘   │
│  ┌─────────────────────────────────────────────────────┐   │
│  │  Setup Service                                       │   │
│  │  - MCPサーバーのインストール                          │   │
│  │  - Claude Code設定の自動更新                          │   │
│  └─────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
```

---

## アプリバンドル構成

```
AI Agent PM.app/
└── Contents/
    ├── MacOS/
    │   └── AI Agent PM              # メインアプリ
    ├── Resources/
    │   └── mcp-server-pm            # バンドル済みMCPサーバー
    └── Info.plist
```

---

## データ配置

```
~/Library/Application Support/AI Agent PM/
├── data.db                          # SQLiteデータベース（共有）
└── config.json                      # アプリ設定

~/.claude/
└── claude_desktop_config.json       # Claude Code MCP設定（自動更新）
```

---

## 技術スタック

| コンポーネント | 技術 | 備考 |
|---------------|------|------|
| Mac App UI | SwiftUI | macOS 14+ |
| アーキテクチャ | Clean Architecture | TDD必須 |
| データ永続化 | SQLite (直接) | アプリ・MCPサーバー共有 |
| MCP Server | Swift CLI | 別プロセス、stdio通信 |
| テスト | XCTest + Swift Testing | カバレッジ80%目標 |
| ビルド | Xcode + Swift Package Manager | モノレポ構成 |

---

## プロジェクト構成（モノレポ）

```
AIAgentPM/
├── Package.swift                    # ルートパッケージ
├── Sources/
│   ├── Domain/                      # ビジネスロジック（共有）
│   ├── UseCases/                    # アプリケーションロジック（共有）
│   ├── Infrastructure/              # データアクセス（共有）
│   ├── App/                         # SwiftUI Macアプリ
│   └── MCPServer/                   # MCPサーバーCLI
├── Tests/
│   ├── DomainTests/
│   ├── UseCaseTests/
│   └── IntegrationTests/
└── docs/
```

---

## 共有コードの利点

- **Domain/UseCases/Infrastructure**はアプリとMCPサーバーで共有
- ビジネスロジックの重複を排除
- 単一のテストスイートで両方をカバー

---

## Claude Code設定（エージェントごと）

```json
// ~/.claude/claude_desktop_config.json
{
  "mcpServers": {
    "agent-pm-frontend": {
      "command": "/Applications/AI Agent PM.app/Contents/Resources/mcp-server-pm",
      "args": [
        "--db", "~/Library/Application Support/AI Agent PM/data.db",
        "--agent-id", "agt_abc123"
      ]
    },
    "agent-pm-backend": {
      "command": "/Applications/AI Agent PM.app/Contents/Resources/mcp-server-pm",
      "args": [
        "--db", "~/Library/Application Support/AI Agent PM/data.db",
        "--agent-id", "agt_def456"
      ]
    }
  }
}
```

**ポイント:**
- エージェントごとに異なるMCPサーバー設定を生成
- 同じDBを共有しつつ、`--agent-id` で認証を分離
- 1つのClaude Codeセッションは1つのエージェントとして動作

---

## 変更履歴

| 日付 | バージョン | 変更内容 |
|------|-----------|----------|
| 2024-12-30 | 1.0.0 | PRD.mdから分離して初版作成 |
