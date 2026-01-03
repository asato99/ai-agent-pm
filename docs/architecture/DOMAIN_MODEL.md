# ドメインモデル設計

システムのコアとなるEntity、Value Object、Domain Serviceの設計。

---

## エンティティ関連図

```
┌─────────────────────────────────────────────────────────────────────────┐
│                           Domain Model                                   │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  ┌─────────────┐       ┌─────────────┐       ┌─────────────┐           │
│  │   Project   │──1:N──│    Task     │──1:N──│   Subtask   │           │
│  └──────┬──────┘       └──────┬──────┘       └─────────────┘           │
│         │                     │                                          │
│         │ 1:N                 │ N:1                                      │
│         ▼                     ▼                                          │
│  ┌─────────────┐       ┌─────────────┐                                  │
│  │    Agent    │◄──────│  assignee   │                                  │
│  └──────┬──────┘       └─────────────┘                                  │
│         │                                                                │
│         │ 1:N           ┌─────────────┐                                  │
│         ▼               │   Context   │──N:1──┐                          │
│  ┌─────────────┐       └─────────────┘       │                          │
│  │   Session   │                              │                          │
│  └─────────────┘       ┌─────────────┐       │                          │
│                         │   Handoff   │──N:1──┤                          │
│                         └─────────────┘       │                          │
│                                                │                          │
│                         ┌─────────────┐       │                          │
│                         │    Task     │◄──────┘                          │
│                         └─────────────┘                                  │
│                                                                          │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │                    StateChangeEvent                              │   │
│  │         (すべてのEntity変更を記録するイベントストア)              │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## Entity定義

### Project（プロジェクト）

```swift
struct Project: Identifiable, Equatable {
    let id: ProjectID
    var name: String
    var description: String
    var status: ProjectStatus
    let createdAt: Date
    var updatedAt: Date
    var archivedAt: Date?
}

struct ProjectID: Hashable, Codable {
    let value: String  // "prj_" + UUID

    static func generate() -> ProjectID {
        ProjectID(value: "prj_\(UUID().uuidString.prefix(12).lowercased())")
    }
}

enum ProjectStatus: String, Codable {
    case active
    case archived
}
```

### Agent（エージェント）

```swift
struct Agent: Identifiable, Equatable {
    let id: AgentID
    var name: String
    var role: String
    var type: AgentType
    var roleType: AgentRoleType
    var capabilities: [String]
    var systemPrompt: String?
    var status: AgentStatus
    let createdAt: Date
    var updatedAt: Date
}

struct AgentID: Hashable, Codable {
    let value: String  // "agt_" + UUID

    static func generate() -> AgentID {
        AgentID(value: "agt_\(UUID().uuidString.prefix(12).lowercased())")
    }
}

enum AgentType: String, Codable {
    case human
    case ai
}

enum AgentRoleType: String, Codable {
    case owner      // プロジェクト所有者
    case manager    // 管理者
    case worker     // 作業者
    case viewer     // 閲覧者
}

enum AgentStatus: String, Codable {
    case active
    case inactive
    case archived
}
```

### Session（セッション）

```swift
struct Session: Identifiable, Equatable {
    let id: SessionID
    let agentId: AgentID
    let projectId: ProjectID
    var toolType: AIToolType
    var status: SessionStatus
    let startedAt: Date
    var endedAt: Date?
    var summary: String?
}

struct SessionID: Hashable, Codable {
    let value: String  // "ses_" + UUID

    static func generate() -> SessionID {
        SessionID(value: "ses_\(UUID().uuidString.prefix(12).lowercased())")
    }
}

enum AIToolType: String, Codable {
    case claudeCode = "claude_code"
    case gemini = "gemini"
    case human = "human"
    case other = "other"
}

enum SessionStatus: String, Codable {
    case active
    case ended
}
```

### Task（タスク）

```swift
struct Task: Identifiable, Equatable {
    let id: TaskID
    let projectId: ProjectID
    var title: String
    var description: String
    var status: TaskStatus
    var priority: TaskPriority
    var assigneeId: AgentID?
    var dependencies: [TaskID]  // タスク間関係は依存関係で表現（サブタスクは不要）
    var estimatedMinutes: Int?
    var actualMinutes: Int?
    let createdAt: Date
    var updatedAt: Date
    var completedAt: Date?
}

struct TaskID: Hashable, Codable {
    let value: String  // "tsk_" + UUID

    static func generate() -> TaskID {
        TaskID(value: "tsk_\(UUID().uuidString.prefix(12).lowercased())")
    }
}

enum TaskStatus: String, Codable, CaseIterable {
    case backlog
    case todo
    case inProgress = "in_progress"
    case review
    case blocked
    case done
    case cancelled
}

enum TaskPriority: String, Codable {
    case critical
    case high
    case medium
    case low
}
```

### Subtask（サブタスク）

```swift
struct Subtask: Identifiable, Equatable {
    let id: SubtaskID
    let taskId: TaskID
    var title: String
    var isCompleted: Bool
    var order: Int
    let createdAt: Date
    var completedAt: Date?
}

struct SubtaskID: Hashable, Codable {
    let value: String  // "sub_" + UUID

    static func generate() -> SubtaskID {
        SubtaskID(value: "sub_\(UUID().uuidString.prefix(12).lowercased())")
    }
}
```

### Context（コンテキスト）

```swift
struct Context: Identifiable, Equatable {
    let id: ContextID
    let taskId: TaskID
    let agentId: AgentID
    let sessionId: SessionID?
    var content: String
    var type: ContextType
    let createdAt: Date
}

struct ContextID: Hashable, Codable {
    let value: String  // "ctx_" + UUID

    static func generate() -> ContextID {
        ContextID(value: "ctx_\(UUID().uuidString.prefix(12).lowercased())")
    }
}

enum ContextType: String, Codable {
    case note           // 自由メモ
    case decision       // 決定事項
    case assumption     // 前提条件
    case blocker        // 障害
    case reference      // 参照情報
    case artifact       // 成果物
}
```

### Handoff（ハンドオフ）

```swift
struct Handoff: Identifiable, Equatable {
    let id: HandoffID
    let taskId: TaskID
    let fromAgentId: AgentID
    let toAgentId: AgentID?
    let sessionId: SessionID?
    var summary: String
    var nextSteps: [String]
    var warnings: [String]
    var status: HandoffStatus
    let createdAt: Date
    var acknowledgedAt: Date?
}

struct HandoffID: Hashable, Codable {
    let value: String  // "hnd_" + UUID

    static func generate() -> HandoffID {
        HandoffID(value: "hnd_\(UUID().uuidString.prefix(12).lowercased())")
    }
}

enum HandoffStatus: String, Codable {
    case pending        // 未確認
    case acknowledged   // 確認済み
    case completed      // 完了
}
```

### StateChangeEvent（状態変更イベント）

```swift
struct StateChangeEvent: Identifiable, Equatable {
    let id: EventID
    let projectId: ProjectID
    let entityType: EntityType
    let entityId: String
    let eventType: EventType
    let agentId: AgentID?
    let sessionId: SessionID?
    let previousState: String?   // JSON
    let newState: String?        // JSON
    let reason: String?
    let metadata: [String: String]?
    let timestamp: Date
}

struct EventID: Hashable, Codable {
    let value: String  // "evt_" + UUID

    static func generate() -> EventID {
        EventID(value: "evt_\(UUID().uuidString.prefix(12).lowercased())")
    }
}

enum EntityType: String, Codable {
    case project
    case task
    case subtask
    case agent
    case session
    case context
    case handoff
}

enum EventType: String, Codable {
    // 共通
    case created
    case updated
    case deleted

    // Task固有
    case statusChanged = "status_changed"
    case assigned
    case unassigned
    case priorityChanged = "priority_changed"

    // Session固有
    case sessionStarted = "session_started"
    case sessionEnded = "session_ended"

    // Handoff固有
    case handoffCreated = "handoff_created"
    case handoffAcknowledged = "handoff_acknowledged"
    case handoffCompleted = "handoff_completed"

    // Context固有
    case contextAdded = "context_added"
}
```

---

## Value Object

### ID生成パターン

```swift
protocol EntityID: Hashable, Codable {
    var value: String { get }
    static var prefix: String { get }
    static func generate() -> Self
}

// 共通実装
extension EntityID {
    static func generate() -> Self where Self: EntityID {
        // "prefix_" + 12文字のランダム文字列
        let random = UUID().uuidString.prefix(12).lowercased()
        return Self(value: "\(Self.prefix)_\(random)")
    }
}
```

### IDプレフィックス一覧

| Entity | Prefix | 例 |
|--------|--------|-----|
| Project | `prj_` | `prj_a1b2c3d4e5f6` |
| Agent | `agt_` | `agt_a1b2c3d4e5f6` |
| Session | `ses_` | `ses_a1b2c3d4e5f6` |
| Task | `tsk_` | `tsk_a1b2c3d4e5f6` |
| Subtask | `sub_` | `sub_a1b2c3d4e5f6` |
| Context | `ctx_` | `ctx_a1b2c3d4e5f6` |
| Handoff | `hnd_` | `hnd_a1b2c3d4e5f6` |
| Event | `evt_` | `evt_a1b2c3d4e5f6` |

---

## Domain Service

### TaskValidationService

```swift
protocol TaskValidationServiceProtocol {
    func validateStatusTransition(
        from: TaskStatus,
        to: TaskStatus
    ) -> Result<Void, TaskValidationError>

    func validateAssignment(
        task: Task,
        agent: Agent
    ) -> Result<Void, TaskValidationError>
}

enum TaskValidationError: Error {
    case invalidStatusTransition(from: TaskStatus, to: TaskStatus)
    case agentNotAuthorized
    case dependenciesNotCompleted
    case blockedByOtherTask
}
```

### HandoffService

```swift
protocol HandoffServiceProtocol {
    func createHandoff(
        task: Task,
        from: Agent,
        to: Agent?,
        summary: String,
        nextSteps: [String],
        warnings: [String]
    ) -> Handoff

    func acknowledgeHandoff(
        handoff: Handoff,
        by: Agent
    ) -> Result<Handoff, HandoffError>
}

enum HandoffError: Error {
    case notTargetAgent
    case alreadyAcknowledged
    case handoffNotFound
}
```

### EventRecordingService

```swift
protocol EventRecordingServiceProtocol {
    func recordEvent<T: Encodable>(
        projectId: ProjectID,
        entityType: EntityType,
        entityId: String,
        eventType: EventType,
        previousState: T?,
        newState: T?,
        agentId: AgentID?,
        sessionId: SessionID?,
        reason: String?
    ) -> StateChangeEvent
}
```

---

## 集約（Aggregate）

### TaskAggregate

Taskを中心とした集約。Subtask、Context、Handoffを含む。

```swift
struct TaskAggregate {
    let task: Task
    let subtasks: [Subtask]
    let contexts: [Context]
    let handoffs: [Handoff]
    let assignee: Agent?

    var completionPercentage: Double {
        guard !subtasks.isEmpty else { return task.status == .done ? 100 : 0 }
        let completed = subtasks.filter { $0.isCompleted }.count
        return Double(completed) / Double(subtasks.count) * 100
    }

    var latestHandoff: Handoff? {
        handoffs.max(by: { $0.createdAt < $1.createdAt })
    }
}
```

### AgentAggregate

Agentを中心とした集約。Session履歴を含む。

```swift
struct AgentAggregate {
    let agent: Agent
    let sessions: [Session]
    let currentSession: Session?
    let assignedTasks: [Task]
    let pendingHandoffs: [Handoff]

    var isOnline: Bool {
        currentSession != nil
    }

    var totalWorkMinutes: Int {
        sessions.compactMap { session in
            guard let ended = session.endedAt else { return nil }
            return Calendar.current.dateComponents(
                [.minute],
                from: session.startedAt,
                to: ended
            ).minute
        }.reduce(0, +)
    }
}
```

---

## 変更履歴

| 日付 | バージョン | 変更内容 |
|------|-----------|----------|
| 2024-12-30 | 1.0.0 | 初版作成 |
