# ツール認可拡張 実装計画

設計書: [TOOL_AUTHORIZATION_ENHANCEMENT.md](../design/TOOL_AUTHORIZATION_ENHANCEMENT.md)

---

## 実装フェーズ

### Phase 1: Purpose ベース認可

#### 1.1 ToolPermission 拡張

**ファイル**: `Sources/MCPServer/Authorization/ToolAuthorization.swift`

```swift
// 追加する権限
case chatOnly = "chat_only"
case taskOnly = "task_only"

// 追加するエラー
case chatSessionRequired(String)
case taskSessionRequired(String)
```

**変更箇所**:
- `ToolPermission` enum に2つの case を追加
- `permissions` dict のチャットツールを `chatOnly` に変更
- `authorize()` 関数に chatOnly/taskOnly のチェックを追加
- `ToolAuthorizationError` に2つの case を追加

#### 1.2 ユニットテスト

**ファイル**: `Tests/MCPServerTests/ToolAuthorizationTests.swift`

```swift
// 追加するテスト
func testChatOnlyToolRequiresChatSession()
func testChatOnlyToolRejectsTaskSession()
func testChatOnlyToolRejectsUnauthenticated()
func testTaskOnlyToolRequiresTaskSession() // 将来用
```

---

### Phase 2: Help ツール基盤

#### 2.1 ツール定義

**ファイル**: `Sources/MCPServer/Tools/ToolDefinitions.swift`

```swift
// 追加
static let help: [String: Any] = [
    "name": "help",
    "description": "利用可能なMCPツールの一覧と詳細を表示します。",
    "inputSchema": [...]
]

// all() に追加
static func all() -> [[String: Any]] {
    [
        help,  // 最初に追加
        authenticate,
        // ...
    ]
}
```

#### 2.2 権限登録

**ファイル**: `Sources/MCPServer/Authorization/ToolAuthorization.swift`

```swift
static let permissions: [String: ToolPermission] = [
    "help": .unauthenticated,  // 追加
    // ...
]
```

#### 2.3 実行ロジック

**ファイル**: `Sources/MCPServer/MCPServer.swift`

```swift
// executeTool() に追加
case "help":
    let toolName = arguments["tool_name"] as? String
    return try executeHelp(caller: caller, toolName: toolName)

// 新規関数
private func executeHelp(caller: CallerType, toolName: String?) throws -> [String: Any]
```

---

### Phase 3: Help ツール詳細実装

#### 3.1 ツールメタデータ構造

**ファイル**: `Sources/MCPServer/Tools/ToolMetadata.swift`（新規）

```swift
/// ツールのメタデータ（help表示用）
struct ToolMetadata {
    let name: String
    let description: String
    let category: String
    let permission: ToolPermission
    let purposeRestriction: AgentPurpose?
    let parameters: [ParameterInfo]
    let example: [String: Any]?
}

struct ParameterInfo {
    let name: String
    let type: String
    let required: Bool
    let description: String
    let enumValues: [String]?
}
```

#### 3.2 メタデータ定義

**ファイル**: `Sources/MCPServer/Tools/ToolDefinitions.swift`

既存のツール定義を拡張してメタデータを追加:

```swift
static func metadata() -> [String: ToolMetadata] {
    [
        "authenticate": ToolMetadata(
            name: "authenticate",
            description: "エージェント認証を行います",
            category: "認証",
            permission: .unauthenticated,
            purposeRestriction: nil,
            parameters: [
                ParameterInfo(name: "agent_id", type: "string", required: true, ...),
                ParameterInfo(name: "passkey", type: "string", required: true, ...),
                ParameterInfo(name: "project_id", type: "string", required: true, ...)
            ],
            example: ["agent_id": "agent-001", "passkey": "xxx", "project_id": "proj-001"]
        ),
        // ... 他のツール
    ]
}
```

#### 3.3 executeHelp 実装

```swift
private func executeHelp(caller: CallerType, toolName: String?) throws -> [String: Any] {
    let allMetadata = ToolDefinitions.metadata()

    // 利用可能なツールをフィルタリング
    let availableTools = allMetadata.values.filter { meta in
        canAccess(permission: meta.permission, caller: caller, purpose: meta.purposeRestriction)
    }

    if let toolName = toolName {
        // 特定ツールの詳細
        return buildToolDetail(toolName: toolName, metadata: allMetadata, caller: caller)
    } else {
        // 一覧表示
        return buildToolList(availableTools: availableTools, caller: caller)
    }
}

private func canAccess(permission: ToolPermission, caller: CallerType, purpose: AgentPurpose?) -> Bool {
    // 権限チェック（ToolAuthorization.authorize と同等のロジック）
    // ...
}
```

---

### Phase 4: テストと検証

#### 4.1 ユニットテスト

**ファイル**: `Tests/MCPServerTests/HelpToolTests.swift`（新規）

```swift
final class HelpToolTests: XCTestCase {
    // 一覧表示
    func testHelpListForUnauthenticated()
    func testHelpListForWorkerTaskSession()
    func testHelpListForWorkerChatSession()
    func testHelpListForManager()
    func testHelpListForCoordinator()

    // 詳細表示
    func testHelpDetailForAvailableTool()
    func testHelpDetailForUnavailableTool()
    func testHelpDetailForUnknownTool()

    // フィルタリング
    func testChatToolsHiddenInTaskSession()
    func testChatToolsVisibleInChatSession()
}
```

#### 4.2 統合テスト

**ファイル**: `Tests/MCPServerTests/MCPServerHelpIntegrationTests.swift`（新規）

```swift
func testHelpThroughMCPServer()
func testHelpWithAuthentication()
```

---

## 実装順序

| # | Phase | 内容 | 依存 | 工数目安 |
|---|-------|------|------|---------|
| 1 | 1.1 | ToolPermission拡張 | なし | 小 |
| 2 | 1.2 | Purpose認可テスト | 1 | 小 |
| 3 | 2.1 | helpツール定義 | なし | 小 |
| 4 | 2.2 | help権限登録 | 3 | 小 |
| 5 | 2.3 | executeHelp骨格 | 4 | 小 |
| 6 | 3.1 | ToolMetadata構造 | なし | 中 |
| 7 | 3.2 | メタデータ定義 | 6 | 中 |
| 8 | 3.3 | executeHelp完成 | 5,7 | 中 |
| 9 | 4.1 | ユニットテスト | 8 | 中 |
| 10 | 4.2 | 統合テスト | 9 | 小 |

---

## 成功基準

- [ ] chatOnlyツールがtaskセッションで拒否される
- [ ] helpツールが未認証で呼び出し可能
- [ ] helpがコンテキストに応じた適切なツール一覧を返す
- [ ] help tool_name=xxx が詳細情報を返す
- [ ] 既存テストに影響なし（リグレッションなし）

---

## 注意事項

1. **後方互換性**: 既存のツール呼び出しに影響を与えない
2. **パフォーマンス**: helpはメタデータをキャッシュ or 静的定義で高速化
3. **メンテナンス性**: 新規ツール追加時はメタデータも必須（コンパイル時チェック推奨）

---

## 参照

- 設計書: `docs/design/TOOL_AUTHORIZATION_ENHANCEMENT.md`
- 現行認可: `Sources/MCPServer/Authorization/ToolAuthorization.swift`
- ツール定義: `Sources/MCPServer/Tools/ToolDefinitions.swift`
