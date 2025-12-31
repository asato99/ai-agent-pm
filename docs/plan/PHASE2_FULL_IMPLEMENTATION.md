# Phase 2: フル実装

本番利用可能な完全なアプリケーションを完成させる。

---

## 関連ドキュメント

実装時に参照すべきドキュメント：

| カテゴリ | ドキュメント | 参照タイミング |
|---------|-------------|---------------|
| **アーキテクチャ** | [README.md](../architecture/README.md) | 全体設計理解 |
| **アーキテクチャ** | [DOMAIN_MODEL.md](../architecture/DOMAIN_MODEL.md) | Entity/Aggregate実装時 |
| **アーキテクチャ** | [DATABASE_SCHEMA.md](../architecture/DATABASE_SCHEMA.md) | Repository実装時 |
| **アーキテクチャ** | [APP_ARCHITECTURE.md](../architecture/APP_ARCHITECTURE.md) | SwiftUIアプリ実装時 |
| **アーキテクチャ** | [MCP_SERVER.md](../architecture/MCP_SERVER.md) | MCPサーバー拡張時 |
| **アーキテクチャ** | [DATA_FLOW.md](../architecture/DATA_FLOW.md) | 状態管理・イベント実装時 |
| **設計** | [MCP_DESIGN.md](../prd/MCP_DESIGN.md) | 全Tool/Resource/Prompt実装時 |
| **設計** | [AGENT_CONCEPT.md](../prd/AGENT_CONCEPT.md) | セッション管理実装時 |
| **設計** | [STATE_HISTORY.md](../prd/STATE_HISTORY.md) | イベントソーシング実装時 |
| **設計** | [TASK_MANAGEMENT.md](../prd/TASK_MANAGEMENT.md) | タスクステータス管理時 |
| **設計** | [SETUP_FLOW.md](../prd/SETUP_FLOW.md) | セットアップウィザード実装時 |
| **UI設計** | [01_project_list.md](../ui/01_project_list.md) | プロジェクト一覧画面 |
| **UI設計** | [02_task_board.md](../ui/02_task_board.md) | タスクボード画面 |
| **UI設計** | [03_agent_management.md](../ui/03_agent_management.md) | エージェント管理画面 |
| **UI設計** | [04_task_detail.md](../ui/04_task_detail.md) | タスク詳細画面 |
| **UI設計** | [05_handoff.md](../ui/05_handoff.md) | ハンドオフ画面 |
| **UI設計** | [06_settings.md](../ui/06_settings.md) | 設定画面 |
| **ガイドライン** | [CLEAN_ARCHITECTURE.md](../guide/CLEAN_ARCHITECTURE.md) | レイヤー設計全般 |
| **ガイドライン** | [TDD.md](../guide/TDD.md) | テスト実装時 |
| **ガイドライン** | [DEPENDENCY_INJECTION.md](../guide/DEPENDENCY_INJECTION.md) | DI設計時 |

---

## 目標

```
┌─────────────────────────────────────────────────────────────────────────┐
│                          Phase 2 Goal                                    │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  ┌──────────────────────────────────────────────────────────────────┐   │
│  │                        Mac App (SwiftUI)                          │   │
│  │                                                                   │   │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐              │   │
│  │  │ Project     │  │ Task Board  │  │ Agent       │              │   │
│  │  │ List        │  │             │  │ Management  │              │   │
│  │  └─────────────┘  └─────────────┘  └─────────────┘              │   │
│  │                                                                   │   │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐              │   │
│  │  │ Task Detail │  │ Handoff     │  │ Settings    │              │   │
│  │  │             │  │             │  │             │              │   │
│  │  └─────────────┘  └─────────────┘  └─────────────┘              │   │
│  │                                                                   │   │
│  └──────────────────────────────────────────────────────────────────┘   │
│                           │                                              │
│                           │ SQLite (共有)                               │
│                           │                                              │
│                           ▼                                              │
│  ┌──────────────────────────────────────────────────────────────────┐   │
│  │                    MCP Server (mcp-server-pm)                     │   │
│  │                                                                   │   │
│  │  • Full Tools (20+)                                               │   │
│  │  • Resources (project://, agent://, task://)                      │   │
│  │  • Prompts (handoff, context-summary)                             │   │
│  │  • Event Sourcing                                                 │   │
│  │  • Session Management                                             │   │
│  │                                                                   │   │
│  └──────────────────────────────────────────────────────────────────┘   │
│                                                                          │
│  ┌──────────────────────────────────────────────────────────────────┐   │
│  │                     Claude Code / AI Agents                       │   │
│  └──────────────────────────────────────────────────────────────────┘   │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## 前提条件

Phase 1で確認済みであること:
- MCPサーバーとClaude Codeの接続が動作する
- stdio通信が安定している
- SQLiteの基本操作が動作する
- Phase 1で発生した問題と解決策が記録されている

---

## 実装ステップ概要

| Step | 内容 | 成果物 |
|------|------|--------|
| 1 | プロジェクト再構成 | Xcodeプロジェクト + Swift Package |
| 2 | Domain層完成 | 全Entity + ValueObject + Aggregate |
| 3 | Infrastructure層完成 | 全Repository + Event記録 |
| 4 | UseCase層 | ビジネスロジック実装 |
| 5 | App層 - 基盤 | Navigation + DI + 状態管理 |
| 6 | App層 - 画面実装 | 6画面実装 |
| 7 | MCP Server拡張 | 全Tool + Resource + Prompt |
| 8 | アプリバンドル | 配布可能なパッケージ作成 |

---

## Step 1: プロジェクト再構成

**目標**: Xcodeプロジェクトと共有Swift Packageを適切に構成

### ディレクトリ構造

```
AIAgentPM/
├── AIAgentPM.xcodeproj/          # Xcodeプロジェクト
├── AIAgentPM/                    # Macアプリ本体
│   ├── App/
│   │   ├── AIAgentPMApp.swift
│   │   └── AppDelegate.swift
│   ├── Features/
│   │   ├── ProjectList/
│   │   ├── TaskBoard/
│   │   ├── AgentManagement/
│   │   ├── TaskDetail/
│   │   ├── Handoff/
│   │   └── Settings/
│   ├── Core/
│   │   ├── Navigation/
│   │   ├── DependencyContainer/
│   │   └── Extensions/
│   └── Resources/
│       └── Assets.xcassets
│
├── Packages/                      # Swift Package (共有)
│   ├── Domain/
│   │   ├── Sources/
│   │   │   ├── Entities/
│   │   │   ├── ValueObjects/
│   │   │   ├── Aggregates/
│   │   │   └── Repositories/     # Protocol定義
│   │   └── Tests/
│   │
│   ├── Infrastructure/
│   │   ├── Sources/
│   │   │   ├── Database/
│   │   │   ├── Repositories/
│   │   │   └── EventStore/
│   │   └── Tests/
│   │
│   └── MCPServer/
│       ├── Sources/
│       │   ├── Transport/
│       │   ├── Handlers/
│       │   └── Tools/
│       └── Tests/
│
└── Scripts/
    └── setup.sh
```

### Package.swift（更新版）

```swift
// Packages/Package.swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AIAgentPMCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "Domain", targets: ["Domain"]),
        .library(name: "Infrastructure", targets: ["Infrastructure"]),
        .library(name: "UseCase", targets: ["UseCase"]),
        .executable(name: "mcp-server-pm", targets: ["MCPServer"])
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "6.24.0"),
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.3.0")
    ],
    targets: [
        // Domain層
        .target(name: "Domain"),
        .testTarget(name: "DomainTests", dependencies: ["Domain"]),

        // UseCase層
        .target(name: "UseCase", dependencies: ["Domain"]),
        .testTarget(name: "UseCaseTests", dependencies: ["UseCase"]),

        // Infrastructure層
        .target(
            name: "Infrastructure",
            dependencies: [
                "Domain",
                .product(name: "GRDB", package: "GRDB.swift")
            ]
        ),
        .testTarget(name: "InfrastructureTests", dependencies: ["Infrastructure"]),

        // MCPサーバー
        .executableTarget(
            name: "MCPServer",
            dependencies: [
                "Domain",
                "UseCase",
                "Infrastructure",
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ]
        ),
        .testTarget(name: "MCPServerTests", dependencies: ["MCPServer"])
    ]
)
```

**成果物**:
- [ ] Xcodeプロジェクト作成
- [ ] Swift Package構成
- [ ] アプリとパッケージの依存関係設定
- [ ] ビルド成功

---

## Step 2: Domain層完成

**目標**: Phase 1のEntity定義を完全版に拡張

### 完全なEntity定義

#### Agent（完全版）

```swift
// Packages/Domain/Sources/Entities/Agent.swift
public struct Agent: Identifiable, Equatable, Sendable {
    public let id: AgentID
    public var name: String
    public var role: String
    public var type: AgentType
    public var roleType: AgentRoleType
    public var capabilities: [String]
    public var systemPrompt: String?
    public var status: AgentStatus
    public let createdAt: Date
    public var updatedAt: Date

    public init(
        id: AgentID,
        name: String,
        role: String,
        type: AgentType,
        roleType: AgentRoleType,
        capabilities: [String] = [],
        systemPrompt: String? = nil,
        status: AgentStatus = .active,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.role = role
        self.type = type
        self.roleType = roleType
        self.capabilities = capabilities
        self.systemPrompt = systemPrompt
        self.status = status
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public enum AgentType: String, Codable, Sendable, CaseIterable {
    case human
    case ai
}

public enum AgentRoleType: String, Codable, Sendable, CaseIterable {
    case developer
    case reviewer
    case tester
    case architect
    case manager
    case writer
    case designer
    case analyst
}

public enum AgentStatus: String, Codable, Sendable, CaseIterable {
    case active
    case inactive
    case suspended
}
```

#### Task（完全版）

```swift
// Packages/Domain/Sources/Entities/Task.swift
public struct Task: Identifiable, Equatable, Sendable {
    public let id: TaskID
    public let projectId: ProjectID
    public var title: String
    public var description: String
    public var status: TaskStatus
    public var priority: TaskPriority
    public var assigneeId: AgentID?
    public var parentTaskId: TaskID?
    public var dependencies: [TaskID]
    public var estimatedMinutes: Int?
    public var actualMinutes: Int?
    public let createdAt: Date
    public var updatedAt: Date
    public var completedAt: Date?

    public init(
        id: TaskID,
        projectId: ProjectID,
        title: String,
        description: String = "",
        status: TaskStatus = .backlog,
        priority: TaskPriority = .medium,
        assigneeId: AgentID? = nil,
        parentTaskId: TaskID? = nil,
        dependencies: [TaskID] = [],
        estimatedMinutes: Int? = nil,
        actualMinutes: Int? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        completedAt: Date? = nil
    ) {
        self.id = id
        self.projectId = projectId
        self.title = title
        self.description = description
        self.status = status
        self.priority = priority
        self.assigneeId = assigneeId
        self.parentTaskId = parentTaskId
        self.dependencies = dependencies
        self.estimatedMinutes = estimatedMinutes
        self.actualMinutes = actualMinutes
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.completedAt = completedAt
    }
}

public enum TaskStatus: String, Codable, Sendable, CaseIterable {
    case backlog
    case todo
    case inProgress = "in_progress"
    case inReview = "in_review"
    case blocked
    case done
    case cancelled
}

public enum TaskPriority: String, Codable, Sendable, CaseIterable {
    case critical
    case high
    case medium
    case low
}
```

#### Session

```swift
// Packages/Domain/Sources/Entities/Session.swift
public struct Session: Identifiable, Equatable, Sendable {
    public let id: SessionID
    public let projectId: ProjectID
    public let agentId: AgentID
    public let startedAt: Date
    public var endedAt: Date?
    public var status: SessionStatus

    public init(
        id: SessionID,
        projectId: ProjectID,
        agentId: AgentID,
        startedAt: Date = Date(),
        endedAt: Date? = nil,
        status: SessionStatus = .active
    ) {
        self.id = id
        self.projectId = projectId
        self.agentId = agentId
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.status = status
    }
}

public enum SessionStatus: String, Codable, Sendable, CaseIterable {
    case active
    case completed
    case abandoned
}
```

#### StateChangeEvent

```swift
// Packages/Domain/Sources/Entities/StateChangeEvent.swift
public struct StateChangeEvent: Identifiable, Equatable, Sendable {
    public let id: EventID
    public let projectId: ProjectID
    public let entityType: EntityType
    public let entityId: String
    public let eventType: EventType
    public let agentId: AgentID?
    public let sessionId: SessionID?
    public let previousState: String?
    public let newState: String?
    public let reason: String?
    public let metadata: [String: String]?
    public let timestamp: Date

    public init(
        id: EventID,
        projectId: ProjectID,
        entityType: EntityType,
        entityId: String,
        eventType: EventType,
        agentId: AgentID? = nil,
        sessionId: SessionID? = nil,
        previousState: String? = nil,
        newState: String? = nil,
        reason: String? = nil,
        metadata: [String: String]? = nil,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.projectId = projectId
        self.entityType = entityType
        self.entityId = entityId
        self.eventType = eventType
        self.agentId = agentId
        self.sessionId = sessionId
        self.previousState = previousState
        self.newState = newState
        self.reason = reason
        self.metadata = metadata
        self.timestamp = timestamp
    }
}

public enum EntityType: String, Codable, Sendable {
    case project
    case task
    case agent
    case session
    case context
    case handoff
}

public enum EventType: String, Codable, Sendable {
    case created
    case updated
    case deleted
    case statusChanged = "status_changed"
    case assigned
    case unassigned
    case started
    case completed
}
```

#### Context, Handoff, Subtask

```swift
// Packages/Domain/Sources/Entities/Context.swift
public struct Context: Identifiable, Equatable, Sendable {
    public let id: ContextID
    public let taskId: TaskID
    public let sessionId: SessionID
    public let agentId: AgentID
    public var progress: String?
    public var findings: String?
    public var blockers: String?
    public var nextSteps: String?
    public let createdAt: Date
    public var updatedAt: Date
}

// Packages/Domain/Sources/Entities/Handoff.swift
public struct Handoff: Identifiable, Equatable, Sendable {
    public let id: HandoffID
    public let taskId: TaskID
    public let fromAgentId: AgentID
    public let toAgentId: AgentID?
    public var summary: String
    public var context: String?
    public var recommendations: String?
    public var acceptedAt: Date?
    public let createdAt: Date
}

// Packages/Domain/Sources/Entities/Subtask.swift
public struct Subtask: Identifiable, Equatable, Sendable {
    public let id: SubtaskID
    public let taskId: TaskID
    public var title: String
    public var isCompleted: Bool
    public var order: Int
    public let createdAt: Date
    public var completedAt: Date?
}
```

### Repository Protocol

```swift
// Packages/Domain/Sources/Repositories/Protocols.swift
public protocol AgentRepositoryProtocol: Sendable {
    func findById(_ id: AgentID) async throws -> Agent?
    func findAll(projectId: ProjectID) async throws -> [Agent]
    func save(_ agent: Agent, projectId: ProjectID) async throws
    func delete(_ id: AgentID) async throws
}

public protocol TaskRepositoryProtocol: Sendable {
    func findById(_ id: TaskID) async throws -> Task?
    func findAll(projectId: ProjectID) async throws -> [Task]
    func findByAssignee(_ agentId: AgentID) async throws -> [Task]
    func findByStatus(_ status: TaskStatus, projectId: ProjectID) async throws -> [Task]
    func save(_ task: Task) async throws
    func delete(_ id: TaskID) async throws
}

public protocol SessionRepositoryProtocol: Sendable {
    func findById(_ id: SessionID) async throws -> Session?
    func findActive(agentId: AgentID) async throws -> Session?
    func findByProject(_ projectId: ProjectID) async throws -> [Session]
    func save(_ session: Session) async throws
}

public protocol EventRepositoryProtocol: Sendable {
    func findByProject(_ projectId: ProjectID, limit: Int?) async throws -> [StateChangeEvent]
    func findByEntity(type: EntityType, id: String) async throws -> [StateChangeEvent]
    func save(_ event: StateChangeEvent) async throws
}
```

**成果物**:
- [ ] 全Entity定義
- [ ] 全ValueObject定義
- [ ] Repository Protocol定義
- [ ] 単体テスト作成

---

## Step 3: Infrastructure層完成

**目標**: 全Repositoryの実装とEvent記録機能

### 完全なDBスキーマ

```swift
// Packages/Infrastructure/Sources/Database/DatabaseMigrations.swift
import GRDB

public struct DatabaseMigrations {
    public static func apply(to db: Database) throws {
        // projects
        try db.create(table: "projects", ifNotExists: true) { t in
            t.column("id", .text).primaryKey()
            t.column("name", .text).notNull()
            t.column("description", .text)
            t.column("status", .text).notNull().defaults(to: "active")
            t.column("created_at", .datetime).notNull()
            t.column("updated_at", .datetime).notNull()
        }

        // agents
        try db.create(table: "agents", ifNotExists: true) { t in
            t.column("id", .text).primaryKey()
            t.column("project_id", .text).notNull()
                .references("projects", onDelete: .cascade)
            t.column("name", .text).notNull()
            t.column("role", .text).notNull()
            t.column("type", .text).notNull()
            t.column("role_type", .text).notNull()
            t.column("capabilities", .text) // JSON array
            t.column("system_prompt", .text)
            t.column("status", .text).notNull().defaults(to: "active")
            t.column("created_at", .datetime).notNull()
            t.column("updated_at", .datetime).notNull()
        }
        try db.create(indexOn: "agents", columns: ["project_id"])

        // tasks
        try db.create(table: "tasks", ifNotExists: true) { t in
            t.column("id", .text).primaryKey()
            t.column("project_id", .text).notNull()
                .references("projects", onDelete: .cascade)
            t.column("title", .text).notNull()
            t.column("description", .text)
            t.column("status", .text).notNull().defaults(to: "backlog")
            t.column("priority", .text).notNull().defaults(to: "medium")
            t.column("assignee_id", .text)
                .references("agents", onDelete: .setNull)
            t.column("parent_task_id", .text)
                .references("tasks", onDelete: .cascade)
            t.column("dependencies", .text) // JSON array
            t.column("estimated_minutes", .integer)
            t.column("actual_minutes", .integer)
            t.column("created_at", .datetime).notNull()
            t.column("updated_at", .datetime).notNull()
            t.column("completed_at", .datetime)
        }
        try db.create(indexOn: "tasks", columns: ["project_id", "status"])
        try db.create(indexOn: "tasks", columns: ["assignee_id"])

        // sessions
        try db.create(table: "sessions", ifNotExists: true) { t in
            t.column("id", .text).primaryKey()
            t.column("project_id", .text).notNull()
                .references("projects", onDelete: .cascade)
            t.column("agent_id", .text).notNull()
                .references("agents", onDelete: .cascade)
            t.column("started_at", .datetime).notNull()
            t.column("ended_at", .datetime)
            t.column("status", .text).notNull().defaults(to: "active")
        }
        try db.create(indexOn: "sessions", columns: ["agent_id", "status"])

        // contexts
        try db.create(table: "contexts", ifNotExists: true) { t in
            t.column("id", .text).primaryKey()
            t.column("task_id", .text).notNull()
                .references("tasks", onDelete: .cascade)
            t.column("session_id", .text).notNull()
                .references("sessions", onDelete: .cascade)
            t.column("agent_id", .text).notNull()
                .references("agents", onDelete: .cascade)
            t.column("progress", .text)
            t.column("findings", .text)
            t.column("blockers", .text)
            t.column("next_steps", .text)
            t.column("created_at", .datetime).notNull()
            t.column("updated_at", .datetime).notNull()
        }

        // handoffs
        try db.create(table: "handoffs", ifNotExists: true) { t in
            t.column("id", .text).primaryKey()
            t.column("task_id", .text).notNull()
                .references("tasks", onDelete: .cascade)
            t.column("from_agent_id", .text).notNull()
                .references("agents", onDelete: .cascade)
            t.column("to_agent_id", .text)
                .references("agents", onDelete: .setNull)
            t.column("summary", .text).notNull()
            t.column("context", .text)
            t.column("recommendations", .text)
            t.column("accepted_at", .datetime)
            t.column("created_at", .datetime).notNull()
        }

        // subtasks
        try db.create(table: "subtasks", ifNotExists: true) { t in
            t.column("id", .text).primaryKey()
            t.column("task_id", .text).notNull()
                .references("tasks", onDelete: .cascade)
            t.column("title", .text).notNull()
            t.column("is_completed", .boolean).notNull().defaults(to: false)
            t.column("order", .integer).notNull()
            t.column("created_at", .datetime).notNull()
            t.column("completed_at", .datetime)
        }

        // state_change_events
        try db.create(table: "state_change_events", ifNotExists: true) { t in
            t.column("id", .text).primaryKey()
            t.column("project_id", .text).notNull()
                .references("projects", onDelete: .cascade)
            t.column("entity_type", .text).notNull()
            t.column("entity_id", .text).notNull()
            t.column("event_type", .text).notNull()
            t.column("agent_id", .text)
            t.column("session_id", .text)
            t.column("previous_state", .text)
            t.column("new_state", .text)
            t.column("reason", .text)
            t.column("metadata", .text) // JSON
            t.column("timestamp", .datetime).notNull()
        }
        try db.create(indexOn: "state_change_events", columns: ["project_id", "timestamp"])
        try db.create(indexOn: "state_change_events", columns: ["entity_type", "entity_id"])
    }
}
```

### EventRecorder

```swift
// Packages/Infrastructure/Sources/EventStore/EventRecorder.swift
import GRDB
import Domain

public actor EventRecorder {
    private let db: DatabaseQueue

    public init(database: DatabaseQueue) {
        self.db = database
    }

    public func recordTaskStatusChange(
        task: Task,
        previousStatus: TaskStatus,
        agentId: AgentID?,
        sessionId: SessionID?,
        reason: String?
    ) async throws {
        let event = StateChangeEvent(
            id: EventID.generate(),
            projectId: task.projectId,
            entityType: .task,
            entityId: task.id.value,
            eventType: .statusChanged,
            agentId: agentId,
            sessionId: sessionId,
            previousState: previousStatus.rawValue,
            newState: task.status.rawValue,
            reason: reason
        )
        try await save(event)
    }

    public func recordTaskAssignment(
        task: Task,
        previousAssignee: AgentID?,
        agentId: AgentID?,
        sessionId: SessionID?
    ) async throws {
        let eventType: EventType = task.assigneeId != nil ? .assigned : .unassigned
        let event = StateChangeEvent(
            id: EventID.generate(),
            projectId: task.projectId,
            entityType: .task,
            entityId: task.id.value,
            eventType: eventType,
            agentId: agentId,
            sessionId: sessionId,
            previousState: previousAssignee?.value,
            newState: task.assigneeId?.value
        )
        try await save(event)
    }

    private func save(_ event: StateChangeEvent) async throws {
        try await db.write { db in
            try EventRecord.fromDomain(event).insert(db)
        }
    }
}
```

**成果物**:
- [ ] 全Repository実装
- [ ] EventRecorder実装
- [ ] ValueObservation対応
- [ ] 単体テスト・統合テスト

---

## Step 4: UseCase層

**目標**: ビジネスロジックの実装

### UseCase例

```swift
// Packages/UseCase/Sources/TaskUseCases.swift
import Domain

public actor UpdateTaskStatusUseCase {
    private let taskRepository: TaskRepositoryProtocol
    private let eventRecorder: EventRecorderProtocol

    public init(
        taskRepository: TaskRepositoryProtocol,
        eventRecorder: EventRecorderProtocol
    ) {
        self.taskRepository = taskRepository
        self.eventRecorder = eventRecorder
    }

    public func execute(
        taskId: TaskID,
        newStatus: TaskStatus,
        agentId: AgentID?,
        sessionId: SessionID?,
        reason: String?
    ) async throws -> Task {
        guard var task = try await taskRepository.findById(taskId) else {
            throw UseCaseError.taskNotFound(taskId)
        }

        let previousStatus = task.status

        // ステータス遷移の検証
        guard canTransition(from: previousStatus, to: newStatus) else {
            throw UseCaseError.invalidStatusTransition(from: previousStatus, to: newStatus)
        }

        task.status = newStatus
        task.updatedAt = Date()

        if newStatus == .done {
            task.completedAt = Date()
        }

        try await taskRepository.save(task)

        // イベント記録
        try await eventRecorder.recordTaskStatusChange(
            task: task,
            previousStatus: previousStatus,
            agentId: agentId,
            sessionId: sessionId,
            reason: reason
        )

        return task
    }

    private func canTransition(from: TaskStatus, to: TaskStatus) -> Bool {
        switch (from, to) {
        case (.backlog, .todo), (.backlog, .cancelled):
            return true
        case (.todo, .inProgress), (.todo, .backlog), (.todo, .cancelled):
            return true
        case (.inProgress, .inReview), (.inProgress, .blocked), (.inProgress, .todo):
            return true
        case (.inReview, .done), (.inReview, .inProgress):
            return true
        case (.blocked, .inProgress), (.blocked, .cancelled):
            return true
        case (.done, _), (.cancelled, _):
            return false // 完了・キャンセル済みからは遷移不可
        default:
            return false
        }
    }
}

public enum UseCaseError: Error {
    case taskNotFound(TaskID)
    case agentNotFound(AgentID)
    case projectNotFound(ProjectID)
    case invalidStatusTransition(from: TaskStatus, to: TaskStatus)
    case sessionNotActive
    case unauthorized
}
```

**成果物**:
- [ ] タスク関連UseCase
- [ ] エージェント関連UseCase
- [ ] セッション関連UseCase
- [ ] ハンドオフ関連UseCase
- [ ] 単体テスト

---

## Step 5: App層 - 基盤

**目標**: SwiftUIアプリの基盤構築

### DependencyContainer

```swift
// AIAgentPM/Core/DependencyContainer/DependencyContainer.swift
import SwiftUI
import Domain
import Infrastructure
import UseCase

@MainActor
final class DependencyContainer: ObservableObject {
    // Repositories
    let projectRepository: ProjectRepository
    let agentRepository: AgentRepository
    let taskRepository: TaskRepository
    let sessionRepository: SessionRepository
    let eventRepository: EventRepository

    // Event Recorder
    let eventRecorder: EventRecorder

    // UseCases
    lazy var updateTaskStatusUseCase: UpdateTaskStatusUseCase = {
        UpdateTaskStatusUseCase(
            taskRepository: taskRepository,
            eventRecorder: eventRecorder
        )
    }()

    // ... 他のUseCase

    init(databasePath: String) throws {
        let database = try DatabaseSetup.createDatabase(at: databasePath)

        self.projectRepository = ProjectRepository(database: database)
        self.agentRepository = AgentRepository(database: database)
        self.taskRepository = TaskRepository(database: database)
        self.sessionRepository = SessionRepository(database: database)
        self.eventRepository = EventRepository(database: database)
        self.eventRecorder = EventRecorder(database: database)
    }
}
```

### Router

```swift
// AIAgentPM/Core/Navigation/Router.swift
import SwiftUI

@Observable
final class Router {
    var selectedProject: ProjectID?
    var selectedTask: TaskID?
    var selectedAgent: AgentID?
    var currentSheet: SheetDestination?
    var path: NavigationPath = NavigationPath()

    enum SheetDestination: Identifiable {
        case newProject
        case newTask(ProjectID)
        case newAgent(ProjectID)
        case taskDetail(TaskID)
        case agentDetail(AgentID)
        case handoff(TaskID)
        case settings

        var id: String {
            switch self {
            case .newProject: return "newProject"
            case .newTask(let id): return "newTask-\(id.value)"
            case .newAgent(let id): return "newAgent-\(id.value)"
            case .taskDetail(let id): return "taskDetail-\(id.value)"
            case .agentDetail(let id): return "agentDetail-\(id.value)"
            case .handoff(let id): return "handoff-\(id.value)"
            case .settings: return "settings"
            }
        }
    }
}
```

**成果物**:
- [ ] DependencyContainer
- [ ] Router
- [ ] アプリエントリポイント
- [ ] 基本的なNavigation構造

---

## Step 6: App層 - 画面実装

**目標**: 6画面の実装

### 実装順序

1. **プロジェクト一覧** (01_project_list.md)
2. **タスクボード** (02_task_board.md)
3. **エージェント管理** (03_agent_management.md)
4. **タスク詳細** (04_task_detail.md)
5. **ハンドオフ** (05_handoff.md)
6. **設定** (06_settings.md)

### 画面実装パターン

```swift
// 例: ProjectListView
// AIAgentPM/Features/ProjectList/ProjectListView.swift
import SwiftUI
import Domain

struct ProjectListView: View {
    @Environment(\.dependencyContainer) private var container
    @State private var viewModel: ProjectListViewModel

    init() {
        _viewModel = State(initialValue: ProjectListViewModel())
    }

    var body: some View {
        List(viewModel.projects) { project in
            ProjectRow(project: project, summary: viewModel.summaries[project.id])
                .onTapGesture {
                    viewModel.selectProject(project.id)
                }
        }
        .navigationTitle("Projects")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: viewModel.showNewProjectSheet) {
                    Image(systemName: "plus")
                }
            }
        }
        .task {
            await viewModel.load(using: container)
        }
    }
}

// AIAgentPM/Features/ProjectList/ProjectListViewModel.swift
@Observable
final class ProjectListViewModel {
    var projects: [Project] = []
    var summaries: [ProjectID: ProjectSummary] = [:]
    var selectedProjectId: ProjectID?
    var isLoading = false
    var error: Error?

    @MainActor
    func load(using container: DependencyContainer) async {
        isLoading = true
        defer { isLoading = false }

        do {
            projects = try await container.projectRepository.findAll()
            // サマリー取得
            for project in projects {
                summaries[project.id] = try await loadSummary(for: project.id, using: container)
            }
        } catch {
            self.error = error
        }
    }

    private func loadSummary(for projectId: ProjectID, using container: DependencyContainer) async throws -> ProjectSummary {
        let tasks = try await container.taskRepository.findAll(projectId: projectId)
        let agents = try await container.agentRepository.findAll(projectId: projectId)
        let events = try await container.eventRepository.findByProject(projectId, limit: 1)

        return ProjectSummary(
            taskCount: tasks.count,
            completedCount: tasks.filter { $0.status == .done }.count,
            inProgressCount: tasks.filter { $0.status == .inProgress }.count,
            blockedCount: tasks.filter { $0.status == .blocked }.count,
            agentCount: agents.count,
            aiAgentCount: agents.filter { $0.type == .ai }.count,
            humanAgentCount: agents.filter { $0.type == .human }.count,
            lastEvent: events.first.map { LastEventInfo(from: $0) }
        )
    }
}
```

**成果物**:
- [ ] ProjectListView + ViewModel
- [ ] TaskBoardView + ViewModel
- [ ] AgentManagementView + ViewModel
- [ ] TaskDetailView + ViewModel
- [ ] HandoffView + ViewModel
- [ ] SettingsView + ViewModel
- [ ] 各画面のプレビュー
- [ ] UIテスト

---

## Step 7: MCP Server拡張

**目標**: 全Tool/Resource/Promptの実装

### Tool一覧（完全版）

```swift
// Packages/MCPServer/Sources/Tools/AllTools.swift

// === Session ===
// start_session - セッション開始
// end_session - セッション終了

// === Profile ===
// get_my_profile - 自分のプロファイル取得

// === Tasks ===
// list_tasks - タスク一覧取得
// get_task - タスク詳細取得
// get_my_tasks - 自分のタスク取得
// create_task - タスク作成
// update_task - タスク更新
// update_task_status - ステータス更新
// assign_task - タスク割り当て
// add_subtask - サブタスク追加
// complete_subtask - サブタスク完了

// === Context ===
// save_context - コンテキスト保存
// get_task_context - タスクコンテキスト取得

// === Handoff ===
// create_handoff - ハンドオフ作成
// accept_handoff - ハンドオフ承認
// get_pending_handoffs - 未処理ハンドオフ取得
```

### Resource一覧

```swift
// Packages/MCPServer/Sources/Resources/AllResources.swift

// project://{project_id}/overview - プロジェクト概要
// project://{project_id}/tasks - タスク一覧
// project://{project_id}/agents - エージェント一覧
// agent://{agent_id}/profile - エージェントプロファイル
// agent://{agent_id}/tasks - 担当タスク
// agent://{agent_id}/sessions - セッション履歴
// task://{task_id}/detail - タスク詳細
// task://{task_id}/history - タスク履歴
// task://{task_id}/context - コンテキスト情報
```

### Prompt一覧

```swift
// Packages/MCPServer/Sources/Prompts/AllPrompts.swift

// handoff - ハンドオフ作成支援プロンプト
// context-summary - コンテキスト要約プロンプト
// task-breakdown - タスク分解支援プロンプト
// status-report - 状況報告生成プロンプト
```

**成果物**:
- [ ] 全Tool実装（20+）
- [ ] 全Resource実装
- [ ] 全Prompt実装
- [ ] セッション管理機能
- [ ] MCPサーバーテスト

---

## Step 8: アプリバンドル

**目標**: 配布可能なMacアプリパッケージの作成

### アプリバンドル構造

```
AIAgentPM.app/
├── Contents/
│   ├── Info.plist
│   ├── MacOS/
│   │   └── AIAgentPM          # メインバイナリ
│   ├── Resources/
│   │   ├── Assets.car
│   │   └── mcp-server-pm      # MCPサーバーバイナリ
│   └── Frameworks/
```

### セットアップ自動化

```swift
// AIAgentPM/Features/Settings/SetupManager.swift
final class SetupManager {
    func generateClaudeCodeConfig(for agent: Agent) -> String {
        let serverPath = Bundle.main.path(forResource: "mcp-server-pm", ofType: nil)!
        let dbPath = getDatabasePath()

        return """
        {
          "mcpServers": {
            "agent-pm": {
              "command": "\(serverPath)",
              "args": [
                "--db", "\(dbPath)",
                "--agent-id", "\(agent.id.value)"
              ]
            }
          }
        }
        """
    }

    func installToClaudeCode(config: String) throws {
        let configPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/claude_desktop_config.json")

        // 既存設定とマージ
        // ...
    }
}
```

**成果物**:
- [ ] アプリバンドル作成
- [ ] MCPサーバーバイナリ組み込み
- [ ] セットアップ自動化機能
- [ ] 配布用DMG作成

---

## チェックリスト

### 完了条件

#### 機能要件
- [ ] プロジェクトCRUDが動作する
- [ ] タスクCRUDが動作する
- [ ] ステータス管理が動作する
- [ ] エージェント管理が動作する
- [ ] セッション管理が動作する
- [ ] コンテキスト記録が動作する
- [ ] ハンドオフ機能が動作する
- [ ] 全MCP Toolが動作する
- [ ] 全MCP Resourceが動作する
- [ ] 全MCP Promptが動作する

#### 品質要件
- [ ] イベントソーシングでログ記録される
- [ ] UIがリアルタイムで更新される
- [ ] エラーハンドリングが適切
- [ ] パフォーマンスが許容範囲
- [ ] 単体テストカバレッジ80%以上

#### 配布要件
- [ ] アプリバンドルが作成できる
- [ ] セットアップウィザードが動作する
- [ ] Claude Code設定が自動生成される
- [ ] MCPサーバーが正しく起動する

---

## リスクと対策

| リスク | 影響 | 対策 |
|--------|------|------|
| SQLite同時アクセス問題 | データ破損 | WALモード + 適切なトランザクション |
| MCPプロトコル変更 | 互換性破損 | バージョン固定 + 抽象化層 |
| UI性能問題 | UX劣化 | ValueObservation最適化 |
| アプリ署名 | 配布不可 | Developer ID取得 |

---

## 変更履歴

| 日付 | バージョン | 変更内容 |
|------|-----------|----------|
| 2024-12-30 | 1.0.0 | 初版作成 |
