# マルチデバイス対応 実装プラン

## 概要

[MULTI_DEVICE_ARCHITECTURE.md](./MULTI_DEVICE_ARCHITECTURE.md) の設計に基づく実装プラン。

**設計方針**: Coordinator側の変更を最小限に抑え、サーバー側で解決する

---

## フェーズ1: リモートアクセス基盤

### 1.1 REST API リモートアクセス対応

**目的**: 別端末からREST APIにアクセス可能にする

**変更箇所**:
- `Sources/RESTServer/RESTServer.swift`

**実装内容**:
```swift
// 変更前
configuration: .init(address: .hostname("127.0.0.1", port: port))

// 変更後（設定可能化）
let bindAddress = settings.allowRemoteAccess ? "0.0.0.0" : "127.0.0.1"
configuration: .init(address: .hostname(bindAddress, port: port))
```

**追加設定**:
- `AppSettings` に `allowRemoteAccess: Bool` を追加
- 設定画面にトグル追加（デフォルト: OFF）
- CORS設定の拡張（動的オリジン許可）

**成果物**:
- [ ] `AppSettings.allowRemoteAccess` フィールド追加
- [ ] `RESTServer` バインドアドレス設定可能化
- [ ] 設定画面UI追加
- [ ] CORS動的設定

---

### 1.2 MCP HTTP Transport

**目的**: リモートCoordinatorからMCPサーバーにアクセス可能にする

**変更箇所**:
- `Sources/MCPServer/Transport/` に新規ファイル追加
- `Sources/RESTServer/` にMCPエンドポイント追加

**実装内容**:

```
POST /mcp
Content-Type: application/json
Authorization: Bearer <coordinator_token>

{
  "jsonrpc": "2.0",
  "method": "tools/call",
  "params": { "name": "authenticate", "arguments": {...} },
  "id": 1
}
```

**アーキテクチャ選択肢**:

| 選択肢 | 説明 | メリット | デメリット |
|--------|------|----------|------------|
| A. REST API統合 | 既存REST APIにMCPエンドポイント追加 | 実装シンプル、ポート共有 | REST/MCPの混在 |
| B. 別ポート | MCP専用HTTPサーバー起動 | 分離が明確 | ポート管理複雑 |

**推奨**: 選択肢A（REST API統合）

**成果物**:
- [ ] `MCPHTTPHandler` 実装
- [ ] `/mcp` エンドポイント追加
- [ ] JSON-RPC リクエスト/レスポンス処理
- [ ] `coordinator_token` 認証

---

## フェーズ2: Working Directory 対応

### 2.1 データモデル拡張

**目的**: humanエージェントごとのworking_directoryを管理

**変更箇所**:
- `Sources/Domain/Entities/` に新規エンティティ
- `Sources/Infrastructure/Database/` にテーブル追加
- `Sources/Infrastructure/Repositories/` にリポジトリ追加

**エンティティ**:
```swift
public struct AgentWorkingDirectory: Identifiable, Equatable, Sendable {
    public let id: AgentWorkingDirectoryID
    public let agentId: AgentID
    public let projectId: ProjectID
    public var workingDirectory: String
    public let createdAt: Date
    public var updatedAt: Date
}
```

**DBスキーマ**:
```sql
CREATE TABLE agent_working_directories (
    id TEXT PRIMARY KEY,
    agent_id TEXT NOT NULL,
    project_id TEXT NOT NULL,
    working_directory TEXT NOT NULL,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL,
    UNIQUE(agent_id, project_id),
    FOREIGN KEY (agent_id) REFERENCES agents(id),
    FOREIGN KEY (project_id) REFERENCES projects(id)
);
```

**成果物**:
- [ ] `AgentWorkingDirectory` エンティティ
- [ ] `AgentWorkingDirectoryID` 値オブジェクト
- [ ] DBマイグレーション
- [ ] `AgentWorkingDirectoryRepository` 実装

---

### 2.2 REST API 拡張

**目的**: Web UIからworking_directoryを管理可能にする

**エンドポイント**:

```
GET /projects/{project_id}
→ レスポンスに my_working_directory を追加

PUT /projects/{project_id}/my-working-directory
Body: { "working_directory": "/path/to/dir" }

DELETE /projects/{project_id}/my-working-directory
```

**成果物**:
- [ ] `GET /projects/{id}` レスポンス拡張
- [ ] `PUT /projects/{id}/my-working-directory` 実装
- [ ] `DELETE /projects/{id}/my-working-directory` 実装

---

### 2.3 MCP API 拡張

**目的**: Coordinatorが適切なworking_directoryを取得できるようにする

**変更箇所**:
- `Sources/MCPServer/MCPServer.swift`

**実装内容**:

`list_active_projects_with_agents` の変更:
```swift
// 認証済みセッションからhumanエージェントIDを取得
let humanAgentId = session.agentId

// AgentWorkingDirectoryを参照
let agentWorkingDir = try agentWorkingDirectoryRepository
    .findByAgentAndProject(humanAgentId, projectId)

// 優先順位: AgentWorkingDirectory > Project.workingDirectory
let workingDirectory = agentWorkingDir?.workingDirectory
    ?? project.workingDirectory
```

**成果物**:
- [ ] セッションからhumanエージェントID取得ロジック
- [ ] `list_active_projects_with_agents` のworking_directory解決ロジック変更

---

### 2.4 Web UI 拡張

**目的**: プロジェクト詳細画面でworking_directoryを編集可能にする

**変更箇所**:
- `web-client/src/components/projects/`

**UI設計**:
```
┌─────────────────────────────────────────────────┐
│ Project: App Development                         │
├─────────────────────────────────────────────────┤
│ ...既存フィールド...                             │
│                                                 │
│ Working Directory (Server):                      │
│   /Users/owner/projects/app                     │
│                                                 │
│ My Working Directory:                            │
│   ┌─────────────────────────────────┐          │
│   │ /home/frontend/projects/app     │  [Save]  │
│   └─────────────────────────────────┘          │
│   (Leave empty to use server default)           │
└─────────────────────────────────────────────────┘
```

**成果物**:
- [ ] プロジェクト詳細コンポーネント拡張
- [ ] working_directory編集フォーム
- [ ] API呼び出し実装

---

## フェーズ3: Coordinator設定エクスポート拡張

### 3.1 管轄範囲取得ロジック

**目的**: humanエージェントの管轄AIを取得するロジック実装

**変更箇所**:
- `Sources/UseCase/` に新規ユースケース

**実装内容**:
```swift
struct GetManagedAgentsUseCase {
    func execute(rootAgentId: AgentID) throws -> [Agent] {
        let rootAgent = try agentRepository.findById(rootAgentId)
        guard rootAgent?.agentType == .human else {
            throw Error.rootMustBeHuman
        }

        var result: [Agent] = []
        traverse(rootAgentId, into: &result)
        return result
    }

    private func traverse(_ agentId: AgentID, into result: inout [Agent]) {
        let children = try agentRepository.findByParentId(agentId)
        for child in children {
            if child.agentType == .human {
                continue  // humanで区切り
            }
            result.append(child)
            traverse(child.id, into: &result)
        }
    }
}
```

**成果物**:
- [ ] `GetManagedAgentsUseCase` 実装
- [ ] ユニットテスト

---

### 3.2 エクスポートUI拡張

**目的**: root_agentを選択してエクスポートできるようにする

**変更箇所**:
- `Sources/App/Features/Settings/SettingsView.swift`

**UI設計**:
- エクスポートボタンクリック → シート表示
- humanエージェントのみをピッカーに表示
- 選択に応じて管轄AI一覧をプレビュー
- エクスポート時に `root_agent_id` をYAMLに含める

**成果物**:
- [ ] `CoordinatorExportSheet` View
- [ ] humanエージェントピッカー
- [ ] 管轄AIプレビュー
- [ ] `CoordinatorConfigExporter` の `root_agent_id` 対応

---

### 3.3 設定ファイルフォーマット拡張

**目的**: `root_agent_id` フィールドを追加

**変更箇所**:
- `Sources/App/Features/Settings/SettingsView.swift` (`CoordinatorConfigExporter`)

**出力例**:
```yaml
# 起点エージェント
root_agent_id: human-frontend-lead

# 既存フィールド
polling_interval: 2
max_concurrent: 3
coordinator_token: xxx

# 管轄AIのみ含む
agents:
  worker-ui:
    passkey: xxx
  worker-css:
    passkey: xxx
```

**成果物**:
- [ ] YAML出力に `root_agent_id` 追加
- [ ] 管轄AIのみをagentsセクションに出力

---

## フェーズ4: Coordinator対応

### 4.1 設定ファイル読み込み拡張

**目的**: `root_agent_id` を読み込み、認証に使用

**変更箇所**:
- `runner/src/aiagent_runner/coordinator_config.py`
- `runner/src/aiagent_runner/coordinator.py`

**実装内容**:
```python
@dataclass
class CoordinatorConfig:
    root_agent_id: Optional[str] = None  # 追加
    # 既存フィールド...

    @classmethod
    def from_yaml(cls, path: Path) -> "CoordinatorConfig":
        # ...
        return cls(
            root_agent_id=data.get("root_agent_id"),
            # 既存フィールド...
        )
```

**成果物**:
- [ ] `CoordinatorConfig.root_agent_id` フィールド追加
- [ ] YAML読み込み対応

---

### 4.2 認証フロー変更

**目的**: `root_agent_id` で認証

**変更箇所**:
- `runner/src/aiagent_runner/coordinator.py`

**実装内容**:
```python
async def _authenticate(self):
    if self.config.root_agent_id:
        # root_agent_id + passkey で認証
        passkey = self.config.get_agent_passkey(self.config.root_agent_id)
        result = await self.mcp_client.authenticate(
            agent_id=self.config.root_agent_id,
            passkey=passkey
        )
        self.session_token = result["session_token"]
```

**成果物**:
- [ ] `root_agent_id` 認証ロジック
- [ ] セッショントークン管理

---

### 4.3 HTTP Transport対応

**目的**: Unix Socket に加えて HTTP 接続をサポート

**変更箇所**:
- `runner/src/aiagent_runner/mcp_client.py`

**実装内容**:
```python
class MCPClient:
    def __init__(self, config: CoordinatorConfig):
        self.url = config.mcp_socket_path  # unix:// or http://

    async def call(self, method: str, params: dict):
        if self.url.startswith("http"):
            return await self._call_http(method, params)
        else:
            return await self._call_unix_socket(method, params)
```

**成果物**:
- [ ] HTTP Transport実装
- [ ] URL スキームによる自動切り替え

---

## 実装順序

```
フェーズ1: リモートアクセス基盤
├── 1.1 REST API リモートアクセス対応
└── 1.2 MCP HTTP Transport

フェーズ2: Working Directory 対応
├── 2.1 データモデル拡張
├── 2.2 REST API 拡張
├── 2.3 MCP API 拡張
└── 2.4 Web UI 拡張

フェーズ3: Coordinator設定エクスポート拡張
├── 3.1 管轄範囲取得ロジック
├── 3.2 エクスポートUI拡張
└── 3.3 設定ファイルフォーマット拡張

フェーズ4: Coordinator対応
├── 4.1 設定ファイル読み込み拡張
├── 4.2 認証フロー変更
└── 4.3 HTTP Transport対応
```

**依存関係**:
- フェーズ1 → フェーズ4（Coordinator HTTP対応にはサーバー側が必要）
- フェーズ2 → フェーズ3/4（working_directoryはサーバー側が先）
- フェーズ3 → フェーズ4（設定フォーマットが先）

---

## テスト計画

### ユニットテスト
- [ ] `GetManagedAgentsUseCase` - 管轄範囲取得ロジック
- [ ] `AgentWorkingDirectoryRepository` - CRUD操作
- [ ] `CoordinatorConfig.from_yaml` - root_agent_id読み込み

### 統合テスト
- [ ] REST API リモートアクセス（別端末シミュレーション）
- [ ] MCP HTTP Transport エンドツーエンド
- [ ] working_directory解決ロジック

### E2Eテスト
- [ ] Web UI からworking_directory設定
- [ ] Coordinatorエクスポート → 別端末で起動

---

## 変更履歴

| 日付 | 内容 |
|------|------|
| 2026-01-20 | 初版作成 |
