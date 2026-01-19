# リモートMCPサーバー + Web UI 計画

## 概要

ローカルネットワーク内の複数端末からAI Agent PMにアクセス可能にするための計画。

### 目標

```
[Mac A: Claude Code] ──┐
                       │  HTTP (Streamable HTTP)
[Mac B: Claude Code] ──┼──→ [リモートMCPサーバー] ──→ [SQLite DB]
                       │           │
[ブラウザ] ────────────┘           │
       ↑                          │
       └──── Web UI ←─────────────┘
```

---

## Phase 1: リモートMCPサーバー

### 1.1 トランスポート層の追加

**新規ファイル**: `Sources/MCPServer/Transport/StreamableHTTPTransport.swift`

| 項目 | 仕様 |
|------|------|
| プロトコル | Streamable HTTP (MCP 2025-06-18) |
| エンドポイント | `POST /mcp` (単一エンドポイント) |
| レスポンス形式 | `application/json` または `text/event-stream` |
| ヘッダー | `MCP-Protocol-Version: 2025-06-18` |

**実装方針**:
- Swift NIO または Vapor を使用
- 既存の `MCPServer` クラスを再利用（トランスポート層のみ差し替え）

### 1.2 認証

**Phase 1（開発用）**: API Key認証

```
Authorization: Bearer <api-key>
```

- API Keyはアプリ設定で生成・管理
- ローカルネット内を想定し、シンプルな認証から開始

**将来（Phase 2以降）**: OAuth 2.1 + PKCE

### 1.3 起動モード

```bash
# 既存: stdio（Claude Code直接連携）
mcp-server-pm serve

# 既存: Unix Socket（ローカルデーモン）
mcp-server-pm daemon

# 新規: HTTP（リモートMCPサーバー）
mcp-server-pm http --port 8080 --api-key <key>
```

### 1.4 Claude Code接続設定

```bash
claude mcp add --transport http --scope local agent-pm http://192.168.x.x:8080/mcp \
  --header "Authorization: Bearer <api-key>"
```

---

## Phase 2: Web UI

### 2.1 技術選定

| 項目 | 選定 | 理由 |
|------|------|------|
| フロントエンド | **React** | 複雑なUI対応（D&D、リアルタイム更新） |
| バックエンド | **Vapor** | REST API + MCPエンドポイント提供 |
| 通信 | REST API (JSON) | React標準的なデータ取得方式 |
| リアルタイム | SSE / WebSocket | タスク状態変更の即座反映 |

**構成**:
```
[Vapor サーバー :8080]
├── POST /mcp              # MCPエンドポイント（AIエージェント用）
├── GET  /api/projects     # REST API（Web UI用）
├── GET  /api/tasks
├── ...
├── GET  /events           # SSE（リアルタイム更新）
└── GET  /*                # React SPA配信（静的ファイル）

[React SPA]
└── ビルド成果物 → Vaporの Public/ から配信
```

**メリット**:
- 既存macOSアプリと同等の操作性（D&D、カンバン）
- リアルタイム更新との相性が良い
- コンポーネント再利用性
- 豊富なエコシステム（UIライブラリ等）

### 2.2 Web UI機能

**Phase 2a: 読み取り専用**
- プロジェクト一覧表示
- タスクボード表示（カンバン）
- エージェント状態表示
- 実行ログ表示

**Phase 2b: 編集機能**
- タスク作成・編集
- エージェント管理
- プロジェクト設定

### 2.3 エンドポイント設計

```
GET  /                     # Web UI トップ
GET  /projects             # プロジェクト一覧
GET  /projects/:id         # プロジェクト詳細（タスクボード）
GET  /projects/:id/tasks   # タスク一覧（JSON）
GET  /agents               # エージェント一覧
GET  /agents/:id           # エージェント詳細

POST /mcp                  # MCP JSON-RPC エンドポイント
```

---

## Phase 3: 高度な機能

### 3.1 リアルタイム更新

- SSE (Server-Sent Events) でタスク状態変更を配信
- Web UIでリアルタイム反映

### 3.2 OAuth 2.1認証

- 外部ネットワーク公開時のセキュリティ強化
- PKCEフロー実装

### 3.3 マルチDB対応

- 複数プロジェクトのDB切り替え
- プロジェクト単位の認証

---

## 実装順序

```
Phase 1.1: HTTPトランスポート基盤 (Vapor/SwiftNIO導入)
    ↓
Phase 1.2: API Key認証
    ↓
Phase 1.3: httpコマンド追加
    ↓
Phase 1.4: Claude Code接続テスト
    ↓
Phase 2a: Web UI（読み取り専用）
    ↓
Phase 2b: Web UI（編集機能）
    ↓
Phase 3: 高度な機能
```

---

## 依存ライブラリ

### バックエンド (Swift)

| ライブラリ | 用途 | 追加方法 |
|-----------|------|----------|
| **Vapor** | HTTPサーバー、REST API | SPM |

**project.yml への追加**:
```yaml
packages:
  Vapor:
    url: https://github.com/vapor/vapor.git
    from: 4.99.0
```

### フロントエンド (React)

| ライブラリ | 用途 |
|-----------|------|
| **React** | UIフレームワーク |
| **React Router** | ルーティング |
| **TanStack Query** | データフェッチ・キャッシュ |
| **dnd-kit** | ドラッグ&ドロップ |
| **Tailwind CSS** | スタイリング |

**ディレクトリ構成**:
```
ai-agent-pm/
├── Sources/           # Swift (既存)
├── web-ui/            # React プロジェクト (新規)
│   ├── src/
│   ├── package.json
│   └── ...
└── project.yml
```

**ビルド・配信**:
```bash
# React ビルド
cd web-ui && npm run build

# ビルド成果物を Vapor の Public/ にコピー
cp -r dist/* ../Sources/MCPServer/Public/
```

---

## セキュリティ考慮事項

### ローカルネット限定時

- [ ] API Key認証
- [ ] Originヘッダー検証
- [ ] Rate limiting

### 外部公開時（将来）

- [ ] HTTPS必須
- [ ] OAuth 2.1 + PKCE
- [ ] CORS設定
- [ ] IP制限

---

## 作業見積もり

| Phase | 作業内容 | 見積もり |
|-------|----------|----------|
| 1.1 | HTTPトランスポート基盤 | 中 |
| 1.2 | API Key認証 | 小 |
| 1.3 | httpコマンド追加 | 小 |
| 1.4 | 接続テスト | 小 |
| 2a | Web UI（読み取り） | 中〜大 |
| 2b | Web UI（編集） | 中 |
| 3 | 高度な機能 | 大 |

---

## 次のアクション

1. [ ] Vapor依存の追加とビルド確認
2. [ ] StreamableHTTPTransport の雛形作成
3. [ ] `/mcp` エンドポイントの実装
4. [ ] API Key認証の実装
5. [ ] Claude Code からの接続テスト
