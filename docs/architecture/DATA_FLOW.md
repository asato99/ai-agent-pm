# データフロー設計

システム全体のデータの流れと状態管理の設計。

---

## 全体データフロー

```
┌─────────────────────────────────────────────────────────────────────────┐
│                           Data Flow Overview                             │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  ┌────────────────────────┐    ┌────────────────────────┐              │
│  │     Mac App (GUI)      │    │   Claude Code (MCP)    │              │
│  │                        │    │                        │              │
│  │  User Action           │    │  AI Tool Call          │              │
│  │       │                │    │       │                │              │
│  │       ▼                │    │       ▼                │              │
│  │  ViewModel             │    │  ToolsHandler          │              │
│  │       │                │    │       │                │              │
│  └───────┼────────────────┘    └───────┼────────────────┘              │
│          │                              │                               │
│          ▼                              ▼                               │
│  ┌──────────────────────────────────────────────────────────────────┐  │
│  │                         UseCase Layer                             │  │
│  │  ┌─────────────────────────────────────────────────────────────┐ │  │
│  │  │  1. ビジネスロジック実行                                     │ │  │
│  │  │  2. StateChangeEvent生成                                    │ │  │
│  │  │  3. Repository経由でDB更新                                   │ │  │
│  │  └─────────────────────────────────────────────────────────────┘ │  │
│  └──────────────────────────────────────────────────────────────────┘  │
│                              │                                          │
│                              ▼                                          │
│  ┌──────────────────────────────────────────────────────────────────┐  │
│  │                      SQLite Database                              │  │
│  │  ┌──────────────┐  ┌──────────────┐  ┌──────────────────────┐   │  │
│  │  │   Entities   │  │    Events    │  │     Relationships    │   │  │
│  │  │  (現在状態)  │  │  (変更履歴)  │  │      (関連付け)      │   │  │
│  │  └──────────────┘  └──────────────┘  └──────────────────────┘   │  │
│  └──────────────────────────────────────────────────────────────────┘  │
│                              │                                          │
│          ┌───────────────────┴───────────────────┐                     │
│          ▼                                        ▼                     │
│  ┌────────────────────────┐    ┌────────────────────────┐              │
│  │   Mac App (観察)       │    │   MCP Server (読取)    │              │
│  │                        │    │                        │              │
│  │  ValueObservation      │    │  Query Result          │              │
│  │       │                │    │       │                │              │
│  │       ▼                │    │       ▼                │              │
│  │  UI自動更新            │    │  JSON Response         │              │
│  └────────────────────────┘    └────────────────────────┘              │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## シナリオ別データフロー

### 1. タスクステータス変更（Macアプリ）

```
┌─────────────────────────────────────────────────────────────────────────┐
│  User: タスクをドラッグ&ドロップで「レビュー」に移動                      │
└─────────────────────────────────────────────────────────────────────────┘
        │
        ▼
┌─────────────────────────────────────────────────────────────────────────┐
│  TaskBoardView                                                           │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │  .onDrop { task, targetStatus in                                │   │
│  │      await viewModel.moveTask(task, to: targetStatus)           │   │
│  │  }                                                               │   │
│  └─────────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────┘
        │
        ▼
┌─────────────────────────────────────────────────────────────────────────┐
│  TaskBoardViewModel                                                      │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │  func moveTask(_ task: Task, to status: TaskStatus) async {     │   │
│  │      try await updateTaskStatusUseCase.execute(                 │   │
│  │          taskId: task.id,                                       │   │
│  │          newStatus: status,                                     │   │
│  │          reason: "ドラッグ&ドロップで移動"                       │   │
│  │      )                                                          │   │
│  │  }                                                               │   │
│  └─────────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────┘
        │
        ▼
┌─────────────────────────────────────────────────────────────────────────┐
│  UpdateTaskStatusUseCase                                                 │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │  func execute(taskId:, newStatus:, reason:) async throws {      │   │
│  │      // 1. 現在のタスク取得                                      │   │
│  │      let task = try await taskRepository.findById(taskId)       │   │
│  │      let oldStatus = task.status                                │   │
│  │                                                                  │   │
│  │      // 2. バリデーション                                        │   │
│  │      try validationService.validateStatusTransition(             │   │
│  │          from: oldStatus, to: newStatus                         │   │
│  │      )                                                          │   │
│  │                                                                  │   │
│  │      // 3. タスク更新                                            │   │
│  │      var updatedTask = task                                     │   │
│  │      updatedTask.status = newStatus                             │   │
│  │      updatedTask.updatedAt = Date()                             │   │
│  │      try await taskRepository.save(updatedTask)                 │   │
│  │                                                                  │   │
│  │      // 4. イベント記録                                          │   │
│  │      let event = eventRecordingService.recordEvent(             │   │
│  │          entityType: .task,                                     │   │
│  │          entityId: taskId.value,                                │   │
│  │          eventType: .statusChanged,                             │   │
│  │          previousState: oldStatus,                              │   │
│  │          newState: newStatus,                                   │   │
│  │          reason: reason                                         │   │
│  │      )                                                          │   │
│  │      try await eventRepository.save(event)                      │   │
│  │  }                                                               │   │
│  └─────────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────┘
        │
        ▼
┌─────────────────────────────────────────────────────────────────────────┐
│  SQLite (トランザクション内で実行)                                       │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │  UPDATE tasks SET status = 'review', updated_at = '...'         │   │
│  │  WHERE id = 'tsk_xxx';                                          │   │
│  │                                                                  │   │
│  │  INSERT INTO state_change_events (id, entity_type, ...)         │   │
│  │  VALUES ('evt_xxx', 'task', ...);                               │   │
│  └─────────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────┘
        │
        ▼
┌─────────────────────────────────────────────────────────────────────────┐
│  TaskBoardViewModel (ValueObservation)                                   │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │  // DB変更を検知して自動更新                                     │   │
│  │  tasksByStatus = updatedTasks.grouped(by: \.status)             │   │
│  └─────────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────┘
        │
        ▼
┌─────────────────────────────────────────────────────────────────────────┐
│  TaskBoardView (SwiftUI)                                                 │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │  // @Observable により自動再描画                                 │   │
│  │  ForEach(viewModel.tasksByStatus[.review] ?? []) { task in      │   │
│  │      TaskCardView(task: task)                                   │   │
│  │  }                                                               │   │
│  └─────────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────┘
```

---

### 2. タスクステータス変更（MCP経由）

```
┌─────────────────────────────────────────────────────────────────────────┐
│  Claude Code: update_task_status を呼び出し                              │
└─────────────────────────────────────────────────────────────────────────┘
        │
        ▼
┌─────────────────────────────────────────────────────────────────────────┐
│  JSON-RPC Request (stdin)                                                │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │  {                                                               │   │
│  │    "jsonrpc": "2.0",                                            │   │
│  │    "id": 1,                                                     │   │
│  │    "method": "tools/call",                                      │   │
│  │    "params": {                                                  │   │
│  │      "name": "update_task_status",                              │   │
│  │      "arguments": {                                             │   │
│  │        "task_id": "tsk_abc123",                                 │   │
│  │        "status": "in_progress",                                 │   │
│  │        "reason": "実装を開始します"                              │   │
│  │      }                                                          │   │
│  │    }                                                            │   │
│  │  }                                                               │   │
│  └─────────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────┘
        │
        ▼
┌─────────────────────────────────────────────────────────────────────────┐
│  ToolsHandler                                                            │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │  // Tools/call を処理                                            │   │
│  │  try await taskTools.updateTaskStatus(                          │   │
│  │      taskId: "tsk_abc123",                                      │   │
│  │      status: "in_progress",                                     │   │
│  │      reason: "実装を開始します"                                  │   │
│  │  )                                                               │   │
│  └─────────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────┘
        │
        ▼
┌─────────────────────────────────────────────────────────────────────────┐
│  UpdateTaskStatusUseCase (アプリと同じロジック)                          │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │  // 追加: MCP経由の場合はagentIdとsessionIdを記録               │   │
│  │  let event = eventRecordingService.recordEvent(                 │   │
│  │      ...                                                        │   │
│  │      agentId: currentAgent.id,     // ← MCPサーバーが保持       │   │
│  │      sessionId: currentSession.id  // ← MCPサーバーが保持       │   │
│  │  )                                                               │   │
│  └─────────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────┘
        │
        ▼
┌─────────────────────────────────────────────────────────────────────────┐
│  JSON-RPC Response (stdout)                                              │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │  {                                                               │   │
│  │    "jsonrpc": "2.0",                                            │   │
│  │    "id": 1,                                                     │   │
│  │    "result": {                                                  │   │
│  │      "success": true,                                           │   │
│  │      "task": {                                                  │   │
│  │        "id": "tsk_abc123",                                      │   │
│  │        "status": "in_progress",                                 │   │
│  │        ...                                                      │   │
│  │      }                                                          │   │
│  │    }                                                            │   │
│  │  }                                                               │   │
│  └─────────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────┘
        │
        ▼
┌─────────────────────────────────────────────────────────────────────────┐
│  Mac App (同時に変更を検知)                                              │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │  // ValueObservation がDB変更を検知                              │   │
│  │  // UI が自動的に更新される                                      │   │
│  │  // 人間ユーザーはリアルタイムでAIの作業を確認可能               │   │
│  └─────────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────┘
```

---

### 3. ハンドオフフロー

```
┌─────────────────────────────────────────────────────────────────────────┐
│  1. Frontend-dev がハンドオフを作成                                       │
└─────────────────────────────────────────────────────────────────────────┘
        │
        ▼
┌─────────────────────────────────────────────────────────────────────────┐
│  create_handoff Tool                                                     │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │  {                                                               │   │
│  │    "task_id": "tsk_abc123",                                     │   │
│  │    "to_agent_id": "agt_backend",                                │   │
│  │    "summary": "UI実装完了。API連携が必要",                       │   │
│  │    "next_steps": [                                              │   │
│  │      "POST /api/users エンドポイント作成",                       │   │
│  │      "認証ミドルウェア追加"                                      │   │
│  │    ],                                                           │   │
│  │    "warnings": [                                                │   │
│  │      "入力バリデーションはフロントで実装済み"                    │   │
│  │    ]                                                            │   │
│  │  }                                                               │   │
│  └─────────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────┘
        │
        ▼
┌─────────────────────────────────────────────────────────────────────────┐
│  CreateHandoffUseCase                                                    │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │  // 1. Handoff エンティティ作成                                  │   │
│  │  let handoff = Handoff(                                         │   │
│  │      id: HandoffID.generate(),                                  │   │
│  │      taskId: taskId,                                            │   │
│  │      fromAgentId: currentAgent.id,                              │   │
│  │      toAgentId: toAgentId,                                      │   │
│  │      summary: summary,                                          │   │
│  │      status: .pending,                                          │   │
│  │      ...                                                        │   │
│  │  )                                                               │   │
│  │                                                                  │   │
│  │  // 2. DB保存                                                    │   │
│  │  try await handoffRepository.save(handoff)                      │   │
│  │                                                                  │   │
│  │  // 3. イベント記録                                              │   │
│  │  recordEvent(eventType: .handoffCreated, ...)                   │   │
│  └─────────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────┘
        │
        ▼
┌─────────────────────────────────────────────────────────────────────────┐
│  2. Backend-dev がセッション開始                                          │
└─────────────────────────────────────────────────────────────────────────┘
        │
        ▼
┌─────────────────────────────────────────────────────────────────────────┐
│  session_start Prompt                                                    │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │  # セッション開始                                                │   │
│  │                                                                  │   │
│  │  ## あなたの情報                                                 │   │
│  │  - 名前: backend-dev                                            │   │
│  │  - 役割: バックエンド開発担当                                    │   │
│  │                                                                  │   │
│  │  ## 未確認のハンドオフ (1件)                                     │   │
│  │  - frontend-dev からの引き継ぎ:                                  │   │
│  │    「UI実装完了。API連携が必要」                                 │   │
│  │    次のステップ:                                                 │   │
│  │    - POST /api/users エンドポイント作成                          │   │
│  │    - 認証ミドルウェア追加                                        │   │
│  └─────────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────┘
        │
        ▼
┌─────────────────────────────────────────────────────────────────────────┐
│  3. Backend-dev がハンドオフを確認                                        │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │  acknowledge_handoff Tool                                        │   │
│  │  → Handoff.status = .acknowledged                               │   │
│  │  → StateChangeEvent(eventType: .handoffAcknowledged)            │   │
│  └─────────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## 状態同期パターン

### GRDB ValueObservation

```swift
// Repository層でObservationを提供
protocol TaskRepositoryProtocol {
    func observeTasks(projectId: ProjectID) -> AsyncStream<[Task]>
}

// 実装
final class TaskRepository: TaskRepositoryProtocol {
    private let database: DatabaseQueue

    func observeTasks(projectId: ProjectID) -> AsyncStream<[Task]> {
        let observation = ValueObservation.tracking { db in
            try TaskRecord
                .filter(Column("project_id") == projectId.value)
                .fetchAll(db)
                .map { $0.toDomain() }
        }

        return AsyncStream { continuation in
            let cancellable = observation.start(
                in: database,
                scheduling: .immediate
            ) { error in
                continuation.finish()
            } onChange: { tasks in
                continuation.yield(tasks)
            }

            continuation.onTermination = { _ in
                cancellable.cancel()
            }
        }
    }
}

// ViewModel での使用
@Observable
final class TaskBoardViewModel {
    private var observationTask: Task<Void, Never>?

    func startObserving() {
        observationTask = Task {
            for await tasks in taskRepository.observeTasks(projectId: project.id) {
                self.tasksByStatus = Dictionary(grouping: tasks, by: \.status)
            }
        }
    }

    func stopObserving() {
        observationTask?.cancel()
    }
}
```

---

## イベントソーシング詳細

### イベント生成フロー

```
┌─────────────────────────────────────────────────────────────────────────┐
│                        Event Recording Flow                              │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  UseCase 実行                                                            │
│       │                                                                  │
│       ├── 1. 現在状態を取得 (previousState)                              │
│       │                                                                  │
│       ├── 2. ビジネスロジック実行                                        │
│       │                                                                  │
│       ├── 3. 新状態を保存 (newState)                                     │
│       │                                                                  │
│       └── 4. StateChangeEvent を生成・保存                               │
│                                                                          │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │  StateChangeEvent                                                │   │
│  │  ┌─────────────────────────────────────────────────────────┐    │   │
│  │  │  id: "evt_xxx"                                           │    │   │
│  │  │  projectId: "prj_xxx"                                    │    │   │
│  │  │  entityType: "task"                                      │    │   │
│  │  │  entityId: "tsk_xxx"                                     │    │   │
│  │  │  eventType: "status_changed"                             │    │   │
│  │  │  agentId: "agt_xxx" (nullable)                           │    │   │
│  │  │  sessionId: "ses_xxx" (nullable)                         │    │   │
│  │  │  previousState: {"status": "todo"}                       │    │   │
│  │  │  newState: {"status": "in_progress"}                     │    │   │
│  │  │  reason: "作業開始"                                       │    │   │
│  │  │  timestamp: "2024-12-30T10:30:00Z"                       │    │   │
│  │  └─────────────────────────────────────────────────────────┘    │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

### 履歴再構築

```swift
// 特定時点の状態を再構築
func reconstructState(entityId: String, at timestamp: Date) async throws -> Task? {
    // 1. 作成イベントを取得
    guard let createdEvent = try await eventRepository.findCreatedEvent(
        entityId: entityId
    ) else {
        return nil
    }

    // 2. 指定時点までのイベントを取得
    let events = try await eventRepository.findEvents(
        entityId: entityId,
        until: timestamp
    )

    // 3. イベントを順に適用して状態を再構築
    var state = try JSONDecoder().decode(Task.self, from: createdEvent.newState!)

    for event in events {
        state = applyEvent(event, to: state)
    }

    return state
}
```

---

## 同時実行制御

### 楽観的ロック

```swift
struct Task {
    let id: TaskID
    var version: Int  // 楽観的ロック用バージョン
    // ...
}

final class TaskRepository {
    func save(_ task: Task) async throws {
        try await database.write { db in
            // バージョンチェック
            let current = try TaskRecord
                .filter(Column("id") == task.id.value)
                .fetchOne(db)

            if let current = current, current.version != task.version {
                throw ConcurrencyError.versionMismatch
            }

            // バージョンをインクリメントして保存
            var record = TaskRecord.fromDomain(task)
            record.version += 1
            try record.save(db)
        }
    }
}
```

### トランザクション

```swift
// 複数操作のアトミック実行
func updateTaskWithEvent(
    task: Task,
    event: StateChangeEvent
) async throws {
    try await database.write { db in
        // トランザクション内で両方実行
        try TaskRecord.fromDomain(task).save(db)
        try EventRecord.fromDomain(event).insert(db)
    }
    // 失敗時は両方ロールバック
}
```

---

## 変更履歴

| 日付 | バージョン | 変更内容 |
|------|-----------|----------|
| 2024-12-30 | 1.0.0 | 初版作成 |
