# Phase 1: MCP連携検証

Claude CodeからMCPサーバーに接続し、基本操作ができることを最短で確認する。

---

## 関連ドキュメント

実装時に参照すべきドキュメント：

| カテゴリ | ドキュメント | 参照タイミング |
|---------|-------------|---------------|
| **アーキテクチャ** | [DOMAIN_MODEL.md](../architecture/DOMAIN_MODEL.md) | Entity定義時 |
| **アーキテクチャ** | [DATABASE_SCHEMA.md](../architecture/DATABASE_SCHEMA.md) | DB設計時 |
| **アーキテクチャ** | [MCP_SERVER.md](../architecture/MCP_SERVER.md) | MCPサーバー実装時 |
| **設計** | [MCP_DESIGN.md](../prd/MCP_DESIGN.md) | Tool/Resource設計時 |
| **設計** | [AGENT_CONCEPT.md](../prd/AGENT_CONCEPT.md) | Agent概念理解 |
| **ガイドライン** | [CLEAN_ARCHITECTURE.md](../guide/CLEAN_ARCHITECTURE.md) | レイヤー設計時 |
| **ガイドライン** | [NAMING_CONVENTIONS.md](../guide/NAMING_CONVENTIONS.md) | 命名規則確認時 |

---

## 目標

```
┌─────────────────────────────────────────────────────────────────────────┐
│                          Phase 1 Goal                                    │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│   Claude Code                    mcp-server-pm                           │
│       │                              │                                   │
│       │  1. 接続                     │                                   │
│       │─────────────────────────────>│                                   │
│       │                              │                                   │
│       │  2. get_my_profile           │                                   │
│       │─────────────────────────────>│                                   │
│       │<─────────────────────────────│  Agent情報                        │
│       │                              │                                   │
│       │  3. list_tasks               │                                   │
│       │─────────────────────────────>│                                   │
│       │<─────────────────────────────│  Task一覧                         │
│       │                              │                                   │
│       │  4. update_task_status       │                                   │
│       │─────────────────────────────>│                                   │
│       │<─────────────────────────────│  更新結果                         │
│       │                              │                                   │
│                                      ▼                                   │
│                              ┌─────────────┐                            │
│                              │   SQLite    │  永続化確認                 │
│                              └─────────────┘                            │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## 実装ステップ

### Step 1: プロジェクトセットアップ

**目標**: Swift Packageプロジェクトを作成し、依存関係を設定する

```swift
// Package.swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AIAgentPM",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "mcp-server-pm", targets: ["MCPServer"])
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "6.24.0"),
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.3.0")
    ],
    targets: [
        // Domain層（共有）
        .target(
            name: "Domain",
            dependencies: []
        ),
        // Infrastructure層（共有）
        .target(
            name: "Infrastructure",
            dependencies: [
                "Domain",
                .product(name: "GRDB", package: "GRDB.swift")
            ]
        ),
        // MCPサーバー
        .executableTarget(
            name: "MCPServer",
            dependencies: [
                "Domain",
                "Infrastructure",
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ]
        )
    ]
)
```

**成果物**:
- [ ] Package.swift 作成
- [ ] 基本ディレクトリ構造作成
- [ ] `swift build` が成功する

---

### Step 2: Domain層（最小限）

**目標**: 必要最小限のEntity定義

**ファイル**:

```swift
// Sources/Domain/Entities/Agent.swift
public struct Agent: Identifiable, Equatable, Sendable {
    public let id: AgentID
    public var name: String
    public var role: String
    public var type: AgentType

    public init(id: AgentID, name: String, role: String, type: AgentType) {
        self.id = id
        self.name = name
        self.role = role
        self.type = type
    }
}

public enum AgentType: String, Codable, Sendable {
    case human
    case ai
}
```

```swift
// Sources/Domain/Entities/Task.swift
public struct Task: Identifiable, Equatable, Sendable {
    public let id: TaskID
    public let projectId: ProjectID
    public var title: String
    public var status: TaskStatus
    public var assigneeId: AgentID?

    public init(id: TaskID, projectId: ProjectID, title: String,
                status: TaskStatus, assigneeId: AgentID?) {
        self.id = id
        self.projectId = projectId
        self.title = title
        self.status = status
        self.assigneeId = assigneeId
    }
}

public enum TaskStatus: String, Codable, CaseIterable, Sendable {
    case backlog
    case todo
    case inProgress = "in_progress"
    case done
}
```

```swift
// Sources/Domain/Entities/Project.swift
public struct Project: Identifiable, Equatable, Sendable {
    public let id: ProjectID
    public var name: String

    public init(id: ProjectID, name: String) {
        self.id = id
        self.name = name
    }
}
```

```swift
// Sources/Domain/ValueObjects/IDs.swift
public struct AgentID: Hashable, Codable, Sendable {
    public let value: String

    public init(value: String) {
        self.value = value
    }

    public static func generate() -> AgentID {
        AgentID(value: "agt_\(UUID().uuidString.prefix(12).lowercased())")
    }
}

public struct ProjectID: Hashable, Codable, Sendable {
    public let value: String

    public init(value: String) {
        self.value = value
    }

    public static func generate() -> ProjectID {
        ProjectID(value: "prj_\(UUID().uuidString.prefix(12).lowercased())")
    }
}

public struct TaskID: Hashable, Codable, Sendable {
    public let value: String

    public init(value: String) {
        self.value = value
    }

    public static func generate() -> TaskID {
        TaskID(value: "tsk_\(UUID().uuidString.prefix(12).lowercased())")
    }
}
```

**成果物**:
- [ ] Agent, Task, Project Entity
- [ ] AgentID, TaskID, ProjectID Value Object
- [ ] コンパイル成功

---

### Step 3: Infrastructure層（DB + Repository）

**目標**: SQLiteセットアップと基本的なCRUD操作

**ファイル**:

```swift
// Sources/Infrastructure/Database/DatabaseSetup.swift
import GRDB

public final class DatabaseSetup {
    public static func createDatabase(at path: String) throws -> DatabaseQueue {
        let dbQueue = try DatabaseQueue(path: path)

        try dbQueue.write { db in
            // projects
            try db.create(table: "projects", ifNotExists: true) { t in
                t.column("id", .text).primaryKey()
                t.column("name", .text).notNull()
            }

            // agents
            try db.create(table: "agents", ifNotExists: true) { t in
                t.column("id", .text).primaryKey()
                t.column("project_id", .text).notNull()
                    .references("projects", onDelete: .cascade)
                t.column("name", .text).notNull()
                t.column("role", .text).notNull()
                t.column("type", .text).notNull()
            }

            // tasks
            try db.create(table: "tasks", ifNotExists: true) { t in
                t.column("id", .text).primaryKey()
                t.column("project_id", .text).notNull()
                    .references("projects", onDelete: .cascade)
                t.column("title", .text).notNull()
                t.column("status", .text).notNull().defaults(to: "backlog")
                t.column("assignee_id", .text)
                    .references("agents", onDelete: .setNull)
            }
        }

        return dbQueue
    }
}
```

```swift
// Sources/Infrastructure/Repositories/AgentRepository.swift
import GRDB
import Domain

public final class AgentRepository: Sendable {
    private let db: DatabaseQueue

    public init(database: DatabaseQueue) {
        self.db = database
    }

    public func findById(_ id: AgentID) throws -> Agent? {
        try db.read { db in
            try AgentRecord
                .filter(Column("id") == id.value)
                .fetchOne(db)?
                .toDomain()
        }
    }

    public func findAll(projectId: ProjectID) throws -> [Agent] {
        try db.read { db in
            try AgentRecord
                .filter(Column("project_id") == projectId.value)
                .fetchAll(db)
                .map { $0.toDomain() }
        }
    }

    public func save(_ agent: Agent, projectId: ProjectID) throws {
        try db.write { db in
            try AgentRecord.fromDomain(agent, projectId: projectId).save(db)
        }
    }
}

// Record
struct AgentRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "agents"

    var id: String
    var projectId: String
    var name: String
    var role: String
    var type: String

    func toDomain() -> Agent {
        Agent(
            id: AgentID(value: id),
            name: name,
            role: role,
            type: AgentType(rawValue: type) ?? .ai
        )
    }

    static func fromDomain(_ agent: Agent, projectId: ProjectID) -> AgentRecord {
        AgentRecord(
            id: agent.id.value,
            projectId: projectId.value,
            name: agent.name,
            role: agent.role,
            type: agent.type.rawValue
        )
    }
}
```

```swift
// Sources/Infrastructure/Repositories/TaskRepository.swift
import GRDB
import Domain

public final class TaskRepository: Sendable {
    private let db: DatabaseQueue

    public init(database: DatabaseQueue) {
        self.db = database
    }

    public func findById(_ id: TaskID) throws -> Task? {
        try db.read { db in
            try TaskRecord
                .filter(Column("id") == id.value)
                .fetchOne(db)?
                .toDomain()
        }
    }

    public func findAll(projectId: ProjectID) throws -> [Task] {
        try db.read { db in
            try TaskRecord
                .filter(Column("project_id") == projectId.value)
                .fetchAll(db)
                .map { $0.toDomain() }
        }
    }

    public func findByAssignee(_ agentId: AgentID) throws -> [Task] {
        try db.read { db in
            try TaskRecord
                .filter(Column("assignee_id") == agentId.value)
                .fetchAll(db)
                .map { $0.toDomain() }
        }
    }

    public func save(_ task: Task) throws {
        try db.write { db in
            try TaskRecord.fromDomain(task).save(db)
        }
    }
}

// Record
struct TaskRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "tasks"

    var id: String
    var projectId: String
    var title: String
    var status: String
    var assigneeId: String?

    func toDomain() -> Task {
        Task(
            id: TaskID(value: id),
            projectId: ProjectID(value: projectId),
            title: title,
            status: TaskStatus(rawValue: status) ?? .backlog,
            assigneeId: assigneeId.map { AgentID(value: $0) }
        )
    }

    static func fromDomain(_ task: Task) -> TaskRecord {
        TaskRecord(
            id: task.id.value,
            projectId: task.projectId.value,
            title: task.title,
            status: task.status.rawValue,
            assigneeId: task.assigneeId?.value
        )
    }
}
```

**成果物**:
- [ ] DatabaseSetup（テーブル作成）
- [ ] AgentRepository
- [ ] TaskRepository
- [ ] ProjectRepository（最小限）
- [ ] コンパイル成功

---

### Step 4: MCPサーバー基盤

**目標**: stdio通信とJSON-RPC処理の基盤

**ファイル**:

```swift
// Sources/MCPServer/main.swift
import ArgumentParser
import Foundation
import Infrastructure

@main
struct MCPServerCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "mcp-server-pm",
        abstract: "AI Agent PM MCP Server"
    )

    @Option(name: .long, help: "Path to SQLite database")
    var db: String

    @Option(name: .long, help: "Agent ID")
    var agentId: String

    func run() throws {
        let database = try DatabaseSetup.createDatabase(at: db)
        let server = MCPServer(
            database: database,
            agentId: agentId
        )
        try server.run()
    }
}
```

```swift
// Sources/MCPServer/Transport/StdioTransport.swift
import Foundation

actor StdioTransport {
    private let input = FileHandle.standardInput
    private let output = FileHandle.standardOutput

    func readMessage() throws -> JSONRPCRequest {
        // Content-Length ヘッダー読み取り
        var headerLine = ""
        while let char = readChar(), char != "\n" {
            headerLine.append(char)
        }
        headerLine = headerLine.trimmingCharacters(in: .whitespacesAndNewlines)

        guard headerLine.hasPrefix("Content-Length: "),
              let length = Int(headerLine.dropFirst(16)) else {
            throw MCPError.invalidHeader
        }

        // 空行スキップ
        _ = readChar() // \r or \n
        if let c = readChar(), c == "\r" { _ = readChar() } // \n

        // ボディ読み取り
        let data = input.readData(ofLength: length)
        return try JSONDecoder().decode(JSONRPCRequest.self, from: data)
    }

    func writeMessage(_ response: JSONRPCResponse) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let data = try encoder.encode(response)
        let header = "Content-Length: \(data.count)\r\n\r\n"

        output.write(header.data(using: .utf8)!)
        output.write(data)
    }

    private func readChar() -> Character? {
        let data = input.readData(ofLength: 1)
        guard let byte = data.first else { return nil }
        return Character(UnicodeScalar(byte))
    }
}

// JSON-RPC Types
struct JSONRPCRequest: Codable {
    let jsonrpc: String
    let id: Int?
    let method: String
    let params: [String: AnyCodable]?
}

struct JSONRPCResponse: Codable {
    let jsonrpc: String
    let id: Int?
    let result: AnyCodable?
    let error: JSONRPCError?

    init(id: Int?, result: Any) {
        self.jsonrpc = "2.0"
        self.id = id
        self.result = AnyCodable(result)
        self.error = nil
    }

    init(id: Int?, error: JSONRPCError) {
        self.jsonrpc = "2.0"
        self.id = id
        self.result = nil
        self.error = error
    }
}

struct JSONRPCError: Codable {
    let code: Int
    let message: String
}

// AnyCodable helper (簡易版)
struct AnyCodable: Codable {
    let value: Any

    init(_ value: Any) {
        self.value = value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let string = try? container.decode(String.self) {
            value = string
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let dict = try? container.decode([String: AnyCodable].self) {
            value = dict.mapValues { $0.value }
        } else if let array = try? container.decode([AnyCodable].self) {
            value = array.map { $0.value }
        } else {
            value = NSNull()
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch value {
        case let string as String:
            try container.encode(string)
        case let int as Int:
            try container.encode(int)
        case let dict as [String: Any]:
            try container.encode(dict.mapValues { AnyCodable($0) })
        case let array as [Any]:
            try container.encode(array.map { AnyCodable($0) })
        default:
            try container.encodeNil()
        }
    }
}
```

```swift
// Sources/MCPServer/MCPServer.swift
import Foundation
import GRDB
import Domain
import Infrastructure

final class MCPServer {
    private let transport: StdioTransport
    private let agentRepository: AgentRepository
    private let taskRepository: TaskRepository
    private let agentId: AgentID

    init(database: DatabaseQueue, agentId: String) {
        self.transport = StdioTransport()
        self.agentRepository = AgentRepository(database: database)
        self.taskRepository = TaskRepository(database: database)
        self.agentId = AgentID(value: agentId)
    }

    func run() throws {
        while true {
            do {
                let request = try await transport.readMessage()
                let response = try await handleRequest(request)
                try await transport.writeMessage(response)
            } catch {
                // エラーログ出力（stderrへ）
                FileHandle.standardError.write(
                    "Error: \(error)\n".data(using: .utf8)!
                )
            }
        }
    }

    private func handleRequest(_ request: JSONRPCRequest) async throws -> JSONRPCResponse {
        switch request.method {
        case "initialize":
            return JSONRPCResponse(id: request.id, result: [
                "protocolVersion": "2024-11-05",
                "serverInfo": [
                    "name": "mcp-server-pm",
                    "version": "0.1.0"
                ],
                "capabilities": [
                    "tools": [:]
                ]
            ])

        case "tools/list":
            return JSONRPCResponse(id: request.id, result: [
                "tools": toolDefinitions()
            ])

        case "tools/call":
            return try await handleToolCall(request)

        default:
            return JSONRPCResponse(id: request.id, error: JSONRPCError(
                code: -32601,
                message: "Method not found: \(request.method)"
            ))
        }
    }

    private func toolDefinitions() -> [[String: Any]] {
        [
            [
                "name": "get_my_profile",
                "description": "自分のエージェント情報を取得",
                "inputSchema": ["type": "object", "properties": [:]]
            ],
            [
                "name": "list_tasks",
                "description": "タスク一覧を取得",
                "inputSchema": ["type": "object", "properties": [:]]
            ],
            [
                "name": "get_my_tasks",
                "description": "自分に割り当てられたタスクを取得",
                "inputSchema": ["type": "object", "properties": [:]]
            ],
            [
                "name": "update_task_status",
                "description": "タスクのステータスを更新",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "task_id": ["type": "string", "description": "タスクID"],
                        "status": ["type": "string", "description": "新しいステータス"]
                    ],
                    "required": ["task_id", "status"]
                ]
            ]
        ]
    }

    private func handleToolCall(_ request: JSONRPCRequest) async throws -> JSONRPCResponse {
        guard let params = request.params,
              let name = params["name"]?.value as? String else {
            return JSONRPCResponse(id: request.id, error: JSONRPCError(
                code: -32602,
                message: "Invalid params"
            ))
        }

        let arguments = params["arguments"]?.value as? [String: Any] ?? [:]

        let result: Any
        switch name {
        case "get_my_profile":
            result = try getMyProfile()
        case "list_tasks":
            result = try listTasks()
        case "get_my_tasks":
            result = try getMyTasks()
        case "update_task_status":
            result = try updateTaskStatus(
                taskId: arguments["task_id"] as! String,
                status: arguments["status"] as! String
            )
        default:
            return JSONRPCResponse(id: request.id, error: JSONRPCError(
                code: -32602,
                message: "Unknown tool: \(name)"
            ))
        }

        return JSONRPCResponse(id: request.id, result: ["content": [
            ["type": "text", "text": String(describing: result)]
        ]])
    }

    // Tool implementations
    private func getMyProfile() throws -> [String: Any] {
        guard let agent = try agentRepository.findById(agentId) else {
            throw MCPError.agentNotFound(agentId.value)
        }
        return [
            "id": agent.id.value,
            "name": agent.name,
            "role": agent.role,
            "type": agent.type.rawValue
        ]
    }

    private func listTasks() throws -> [[String: Any]] {
        // 全タスク取得（Phase1では簡略化）
        // 実際にはプロジェクトIDが必要
        []
    }

    private func getMyTasks() throws -> [[String: Any]] {
        let tasks = try taskRepository.findByAssignee(agentId)
        return tasks.map { task in
            [
                "id": task.id.value,
                "title": task.title,
                "status": task.status.rawValue
            ]
        }
    }

    private func updateTaskStatus(taskId: String, status: String) throws -> [String: Any] {
        guard var task = try taskRepository.findById(TaskID(value: taskId)) else {
            throw MCPError.taskNotFound(taskId)
        }

        guard let newStatus = TaskStatus(rawValue: status) else {
            throw MCPError.invalidStatus(status)
        }

        task.status = newStatus
        try taskRepository.save(task)

        return [
            "success": true,
            "task": [
                "id": task.id.value,
                "title": task.title,
                "status": task.status.rawValue
            ]
        ]
    }
}

enum MCPError: Error {
    case invalidHeader
    case agentNotFound(String)
    case taskNotFound(String)
    case invalidStatus(String)
}
```

**成果物**:
- [ ] StdioTransport
- [ ] MCPServer（基本ハンドリング）
- [ ] 4つのTool実装
- [ ] コンパイル成功

---

### Step 5: テストデータ作成とCLI

**目標**: 動作確認用のテストデータを投入するCLI

```swift
// 簡易的なテストデータ投入スクリプト
// またはmain.swiftにサブコマンドとして追加

// swift run mcp-server-pm seed --db ./data.db
// → テスト用のProject, Agent, Taskを作成
```

**成果物**:
- [ ] テストデータ投入機能
- [ ] データ確認機能

---

### Step 6: Claude Code連携テスト

**目標**: 実際にClaude Codeから接続して動作確認

**手順**:

1. **ビルド**
   ```bash
   swift build -c release
   ```

2. **テストデータ投入**
   ```bash
   .build/release/mcp-server-pm seed --db ~/test-data.db
   ```

3. **Claude Code設定**
   ```json
   // ~/.claude/claude_desktop_config.json
   {
     "mcpServers": {
       "agent-pm-test": {
         "command": "/path/to/.build/release/mcp-server-pm",
         "args": [
           "--db", "/Users/xxx/test-data.db",
           "--agent-id", "agt_test123"
         ]
       }
     }
   }
   ```

4. **Claude Code再起動**

5. **動作確認**
   ```
   Claude Codeで:
   - "get_my_profile を呼び出して" → エージェント情報が返る
   - "get_my_tasks を呼び出して" → タスク一覧が返る
   - "タスクXXXをin_progressに更新して" → ステータスが更新される
   ```

**成果物**:
- [ ] Claude Codeからの接続成功
- [ ] get_my_profile 動作確認
- [ ] list_tasks 動作確認
- [ ] update_task_status 動作確認
- [ ] DB永続化確認

---

## チェックリスト

### 完了条件

- [ ] Swift Packageがビルドできる
- [ ] SQLiteにテーブルが作成される
- [ ] テストデータが投入できる
- [ ] mcp-server-pmが起動する
- [ ] Claude Codeから接続できる
- [ ] get_my_profileが動作する
- [ ] list_tasksが動作する
- [ ] update_task_statusが動作し、DBが更新される

### Phase 2への引き継ぎ事項

Phase 1完了時に確認・記録すべき事項：

- [ ] MCP Protocolで発生した問題と解決策
- [ ] stdio通信で注意すべき点
- [ ] SQLite同時アクセスの挙動
- [ ] エラーハンドリングで追加が必要な項目
- [ ] パフォーマンス上の懸念点

---

## 変更履歴

| 日付 | バージョン | 変更内容 |
|------|-----------|----------|
| 2024-12-30 | 1.0.0 | 初版作成 |
