# システムアーキテクチャ

AI Agent Project Managerの技術アーキテクチャ設計。

---

## システム全体像

```
┌─────────────────────────────────────────────────────────────────────────┐
│                           ユーザー環境                                   │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  ┌──────────────────────┐         ┌──────────────────────┐             │
│  │   AI Agent PM.app    │         │     Claude Code      │             │
│  │      (SwiftUI)       │         │    (AI Assistant)    │             │
│  │                      │         │                      │             │
│  │  ┌────────────────┐  │         │  ┌────────────────┐  │             │
│  │  │  Presentation  │  │         │  │   MCP Client   │  │             │
│  │  │    (Views)     │  │         │  └───────┬────────┘  │             │
│  │  └───────┬────────┘  │         │          │           │             │
│  │          │           │         │          │ stdio     │             │
│  │  ┌───────▼────────┐  │         │          │           │             │
│  │  │   Interface    │  │         └──────────┼───────────┘             │
│  │  │  (ViewModels)  │  │                    │                          │
│  │  └───────┬────────┘  │                    ▼                          │
│  │          │           │         ┌──────────────────────┐             │
│  │  ┌───────▼────────┐  │         │   mcp-server-pm      │             │
│  │  │    UseCases    │  │         │      (CLI)           │             │
│  │  └───────┬────────┘  │         │                      │             │
│  │          │           │         │  ┌────────────────┐  │             │
│  │  ┌───────▼────────┐  │         │  │  MCP Protocol  │  │             │
│  │  │     Domain     │  │         │  │    Handler     │  │             │
│  │  │   (Entities)   │  │         │  └───────┬────────┘  │             │
│  │  └───────┬────────┘  │         │          │           │             │
│  │          │           │         │  ┌───────▼────────┐  │             │
│  │  ┌───────▼────────┐  │         │  │    UseCases    │  │             │
│  │  │ Infrastructure │  │         │  └───────┬────────┘  │             │
│  │  │  (Repository)  │  │         │          │           │             │
│  │  └───────┬────────┘  │         │  ┌───────▼────────┐  │             │
│  │          │           │         │  │     Domain     │  │             │
│  └──────────┼───────────┘         │  └───────┬────────┘  │             │
│             │                      │          │           │             │
│             │                      │  ┌───────▼────────┐  │             │
│             │                      │  │ Infrastructure │  │             │
│             │                      │  └───────┬────────┘  │             │
│             │                      └──────────┼───────────┘             │
│             │                                  │                         │
│             │         ┌────────────────────────┘                         │
│             │         │                                                  │
│             ▼         ▼                                                  │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │                      SQLite Database                             │   │
│  │         ~/Library/Application Support/AI Agent PM/data.db       │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## コンポーネント構成

### 1. Macアプリ（AI Agent PM.app）

| レイヤー | 責務 |
|---------|------|
| Presentation | SwiftUI Views、状態管理 |
| Interface | ViewModel、Presenter |
| UseCases | ビジネスロジック |
| Domain | Entity、Value Object |
| Infrastructure | Repository実装、SQLiteアクセス |

### 2. MCPサーバー（mcp-server-pm）

| レイヤー | 責務 |
|---------|------|
| MCP Handler | stdio通信、JSON-RPC処理 |
| UseCases | ビジネスロジック（アプリと共有） |
| Domain | Entity（アプリと共有） |
| Infrastructure | SQLiteアクセス（アプリと共有） |

### 3. 共有コード

```
Sources/
├── Domain/          # 共有: Entity, Value Object
├── UseCases/        # 共有: ビジネスロジック
├── Infrastructure/  # 共有: Repository実装
├── App/             # アプリ専用: UI層
└── MCPServer/       # MCP専用: Protocol Handler
```

---

## ドキュメント構成

| ドキュメント | 説明 |
|-------------|------|
| [DOMAIN_MODEL.md](./DOMAIN_MODEL.md) | ドメインモデル・Entity設計 |
| [DATABASE_SCHEMA.md](./DATABASE_SCHEMA.md) | SQLiteスキーマ設計 |
| [APP_ARCHITECTURE.md](./APP_ARCHITECTURE.md) | Macアプリ内部構成 |
| [MCP_SERVER.md](./MCP_SERVER.md) | MCPサーバー設計 |
| [DATA_FLOW.md](./DATA_FLOW.md) | データフロー・状態管理 |

---

## 技術スタック

| 領域 | 技術 | 理由 |
|------|------|------|
| UI | SwiftUI | macOS標準、宣言的UI |
| データベース | SQLite | 軽量、共有可能、ファイルベース |
| SQLiteアクセス | GRDB.swift | Swift-friendly、型安全 |
| MCP通信 | stdio + JSON-RPC | Claude Code標準 |
| 非同期処理 | Swift Concurrency | async/await、Actor |
| DI | 手動コンストラクタ注入 | シンプル、テスト容易 |
| テスト | Swift Testing + XCTest | 標準フレームワーク |

---

## 設計原則

1. **共有コード最大化**: Domain/UseCase/Infrastructureはアプリ・MCPサーバーで共有
2. **依存性逆転**: Repository ProtocolをUseCase層で定義、Infrastructure層で実装
3. **イベントソーシング**: StateChangeEventで全変更を記録
4. **オフライン優先**: SQLiteローカルDB、クラウド同期なし（MVP）

---

## 変更履歴

| 日付 | バージョン | 変更内容 |
|------|-----------|----------|
| 2024-12-30 | 1.0.0 | 初版作成 |
