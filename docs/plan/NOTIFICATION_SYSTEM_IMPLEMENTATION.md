# 通知システム実装計画

ユニットテストファーストで通知システムを実装するための計画書。

## 関連ドキュメント

- 設計: [NOTIFICATION_SYSTEM.md](../design/NOTIFICATION_SYSTEM.md)
- ユースケース: [UC010_TaskInterruptByStatusChange.md](../usecase/UC010_TaskInterruptByStatusChange.md)

---

## 実装概要

### ゴール

1. 全MCPツールレスポンスに `notification` フィールドを追加
2. `get_notifications` ツールを新規実装
3. UC010（blockedステータス変更による割り込み）を実現

### アーキテクチャ

```
┌─────────────────────────────────────────────────────────────────┐
│                         Domain Layer                            │
│  ┌─────────────────┐  ┌──────────────────────────────────────┐  │
│  │  Notification   │  │  NotificationRepository (Protocol)   │  │
│  │  (Entity)       │  │                                      │  │
│  └─────────────────┘  └──────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
                              │
┌─────────────────────────────────────────────────────────────────┐
│                       UseCase Layer                             │
│  ┌─────────────────────────┐  ┌──────────────────────────────┐  │
│  │ CreateNotificationUseCase│  │ GetNotificationsUseCase     │  │
│  └─────────────────────────┘  └──────────────────────────────┘  │
│  ┌─────────────────────────┐  ┌──────────────────────────────┐  │
│  │ CheckNotificationUseCase│  │ ClearNotificationsUseCase   │  │
│  └─────────────────────────┘  └──────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
                              │
┌─────────────────────────────────────────────────────────────────┐
│                    Infrastructure Layer                         │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │  SQLiteNotificationRepository                             │   │
│  └──────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
                              │
┌─────────────────────────────────────────────────────────────────┐
│                       MCPServer Layer                           │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │  handleToolsCall() ─── NotificationMiddleware             │   │
│  │                         └── getNotificationMessage()      │   │
│  └──────────────────────────────────────────────────────────┘   │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │  get_notifications ツール                                  │   │
│  └──────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
```

---

## Phase 1: Domain Layer

### 1.1 Notification エンティティ

**テストファイル**: `Tests/DomainTests/NotificationTests.swift`

```swift
// RED: 最初に書くテスト
final class NotificationTests: XCTestCase {

    /// 通知の基本生成
    func testNotificationCreation() {
        let notification = Notification(
            id: NotificationID("notif_001"),
            targetAgentId: AgentID("agent_001"),
            targetProjectId: ProjectID("proj_001"),
            type: .statusChange,
            action: "blocked",
            taskId: TaskID("task_001"),
            message: "タスクのステータスがblockedに変更されました",
            instruction: "作業を中断してください",
            createdAt: Date()
        )

        XCTAssertEqual(notification.type, .statusChange)
        XCTAssertEqual(notification.action, "blocked")
        XCTAssertFalse(notification.isRead)
    }

    /// 通知タイプの検証
    func testNotificationTypes() {
        XCTAssertEqual(NotificationType.statusChange.rawValue, "status_change")
        XCTAssertEqual(NotificationType.interrupt.rawValue, "interrupt")
        XCTAssertEqual(NotificationType.message.rawValue, "message")
    }

    /// 通知の既読マーク
    func testMarkAsRead() {
        var notification = Notification(...)
        XCTAssertFalse(notification.isRead)

        notification.markAsRead()

        XCTAssertTrue(notification.isRead)
        XCTAssertNotNil(notification.readAt)
    }
}
```

**実装ファイル**: `Sources/Domain/Entities/Notification.swift`

```swift
// GREEN: テストを通すための実装
public struct NotificationID: Hashable, Codable, Sendable {
    public let value: String
    public init(_ value: String) { self.value = value }
}

public enum NotificationType: String, Codable, Sendable {
    case statusChange = "status_change"
    case interrupt = "interrupt"
    case message = "message"
}

public struct Notification: Identifiable, Codable, Sendable {
    public let id: NotificationID
    public let targetAgentId: AgentID
    public let targetProjectId: ProjectID
    public let type: NotificationType
    public let action: String
    public let taskId: TaskID?
    public let message: String
    public let instruction: String
    public let createdAt: Date
    public private(set) var isRead: Bool
    public private(set) var readAt: Date?

    public init(...) { ... }

    public mutating func markAsRead() {
        isRead = true
        readAt = Date()
    }
}
```

### 1.2 NotificationRepository プロトコル

**テストファイル**: `Tests/DomainTests/NotificationRepositoryTests.swift`

```swift
// RED: リポジトリ契約のテスト（モック使用）
final class NotificationRepositoryContractTests: XCTestCase {

    /// 通知の保存と取得
    func testSaveAndFindById() {
        let repo = MockNotificationRepository()
        let notification = createTestNotification()

        try repo.save(notification)
        let found = try repo.findById(notification.id)

        XCTAssertEqual(found?.id, notification.id)
    }

    /// エージェント+プロジェクト単位での未読通知取得
    func testFindUnreadByAgentAndProject() {
        let repo = MockNotificationRepository()
        let agentId = AgentID("agent_001")
        let projectId = ProjectID("proj_001")

        // 未読通知を2件作成
        try repo.save(createTestNotification(agentId: agentId, projectId: projectId, isRead: false))
        try repo.save(createTestNotification(agentId: agentId, projectId: projectId, isRead: false))
        // 既読通知を1件作成
        try repo.save(createTestNotification(agentId: agentId, projectId: projectId, isRead: true))

        let unread = try repo.findUnreadByAgentAndProject(agentId: agentId, projectId: projectId)

        XCTAssertEqual(unread.count, 2)
    }

    /// 通知の存在チェック（高速）
    func testHasUnreadNotifications() {
        let repo = MockNotificationRepository()
        let agentId = AgentID("agent_001")
        let projectId = ProjectID("proj_001")

        XCTAssertFalse(try repo.hasUnreadNotifications(agentId: agentId, projectId: projectId))

        try repo.save(createTestNotification(agentId: agentId, projectId: projectId))

        XCTAssertTrue(try repo.hasUnreadNotifications(agentId: agentId, projectId: projectId))
    }

    /// 通知の既読化
    func testMarkAsRead() {
        let repo = MockNotificationRepository()
        let notification = createTestNotification()
        try repo.save(notification)

        try repo.markAsRead(notification.id)

        let found = try repo.findById(notification.id)
        XCTAssertTrue(found?.isRead ?? false)
    }

    /// 古い通知のクリーンアップ
    func testDeleteOlderThan() {
        let repo = MockNotificationRepository()
        let oldDate = Date().addingTimeInterval(-86400 * 8) // 8日前
        let recentDate = Date().addingTimeInterval(-86400 * 1) // 1日前

        try repo.save(createTestNotification(createdAt: oldDate))
        try repo.save(createTestNotification(createdAt: recentDate))

        let deleted = try repo.deleteOlderThan(days: 7)

        XCTAssertEqual(deleted, 1)
    }
}
```

**実装ファイル**: `Sources/Domain/Repositories/NotificationRepository.swift`

```swift
public protocol NotificationRepository: Sendable {
    func save(_ notification: Notification) throws
    func findById(_ id: NotificationID) throws -> Notification?
    func findUnreadByAgentAndProject(agentId: AgentID, projectId: ProjectID) throws -> [Notification]
    func hasUnreadNotifications(agentId: AgentID, projectId: ProjectID) throws -> Bool
    func markAsRead(_ id: NotificationID) throws
    func markAllAsRead(agentId: AgentID, projectId: ProjectID) throws
    func deleteOlderThan(days: Int) throws -> Int
}
```

---

## Phase 2: Infrastructure Layer

### 2.1 SQLiteNotificationRepository

**テストファイル**: `Tests/InfrastructureTests/SQLiteNotificationRepositoryTests.swift`

```swift
// RED: 実際のDB操作テスト
final class SQLiteNotificationRepositoryTests: XCTestCase {

    var database: AppDatabase!
    var repository: SQLiteNotificationRepository!

    override func setUp() {
        database = try! AppDatabase(inMemory: true)
        repository = SQLiteNotificationRepository(database: database)
    }

    /// DB保存と取得
    func testSaveAndRetrieve() throws {
        let notification = Notification(
            id: NotificationID("notif_\(UUID().uuidString)"),
            targetAgentId: AgentID("agent_001"),
            targetProjectId: ProjectID("proj_001"),
            type: .statusChange,
            action: "blocked",
            taskId: TaskID("task_001"),
            message: "テストメッセージ",
            instruction: "テスト指示",
            createdAt: Date(),
            isRead: false
        )

        try repository.save(notification)
        let found = try repository.findById(notification.id)

        XCTAssertNotNil(found)
        XCTAssertEqual(found?.type, .statusChange)
        XCTAssertEqual(found?.action, "blocked")
    }

    /// hasUnreadNotificationsの高速性テスト
    func testHasUnreadNotificationsPerformance() throws {
        let agentId = AgentID("agent_perf")
        let projectId = ProjectID("proj_perf")

        // 1000件の通知を作成
        for i in 0..<1000 {
            let notification = createTestNotification(
                id: "notif_\(i)",
                agentId: agentId,
                projectId: projectId
            )
            try repository.save(notification)
        }

        // EXISTS句を使用した高速チェック
        measure {
            _ = try? repository.hasUnreadNotifications(agentId: agentId, projectId: projectId)
        }
    }

    /// マイグレーションテスト
    func testNotificationsTableExists() throws {
        let tables = try database.pool.read { db in
            try String.fetchAll(db, sql: "SELECT name FROM sqlite_master WHERE type='table' AND name='notifications'")
        }
        XCTAssertTrue(tables.contains("notifications"))
    }
}
```

**実装ファイル**: `Sources/Infrastructure/Persistence/SQLiteNotificationRepository.swift`

**マイグレーション**: `Sources/Infrastructure/Persistence/AppDatabase.swift` に追加

```sql
-- notifications テーブル
CREATE TABLE notifications (
    id TEXT PRIMARY KEY,
    target_agent_id TEXT NOT NULL,
    target_project_id TEXT NOT NULL,
    type TEXT NOT NULL,
    action TEXT NOT NULL,
    task_id TEXT,
    message TEXT NOT NULL,
    instruction TEXT NOT NULL,
    created_at TEXT NOT NULL,
    is_read INTEGER NOT NULL DEFAULT 0,
    read_at TEXT,
    FOREIGN KEY (target_agent_id) REFERENCES agents(id),
    FOREIGN KEY (target_project_id) REFERENCES projects(id)
);

CREATE INDEX idx_notifications_unread
ON notifications(target_agent_id, target_project_id, is_read)
WHERE is_read = 0;
```

---

## Phase 3: UseCase Layer

### 3.1 CreateNotificationUseCase

**テストファイル**: `Tests/UseCaseTests/CreateNotificationUseCaseTests.swift`

```swift
// RED: 通知作成ユースケース
final class CreateNotificationUseCaseTests: XCTestCase {

    /// blockedステータス変更時の通知作成
    func testCreateNotificationForBlockedStatus() throws {
        let notificationRepo = MockNotificationRepository()
        let taskRepo = MockTaskRepository()

        // タスクをセットアップ
        let task = Task(id: TaskID("task_001"), assigneeId: AgentID("agent_001"), projectId: ProjectID("proj_001"), ...)
        taskRepo.save(task)

        let useCase = CreateNotificationUseCase(
            notificationRepository: notificationRepo,
            taskRepository: taskRepo
        )

        let notification = try useCase.execute(
            taskId: TaskID("task_001"),
            type: .statusChange,
            action: "blocked"
        )

        XCTAssertEqual(notification.targetAgentId.value, "agent_001")
        XCTAssertEqual(notification.type, .statusChange)
        XCTAssertEqual(notification.action, "blocked")
        XCTAssertTrue(notification.instruction.contains("report_completed"))
    }

    /// 担当者がいないタスクへの通知はエラー
    func testCreateNotificationFailsForUnassignedTask() throws {
        let task = Task(id: TaskID("task_002"), assigneeId: nil, ...)

        XCTAssertThrowsError(try useCase.execute(taskId: TaskID("task_002"), ...)) { error in
            XCTAssertEqual(error as? NotificationError, .noAssignee)
        }
    }
}
```

### 3.2 CheckNotificationUseCase

**テストファイル**: `Tests/UseCaseTests/CheckNotificationUseCaseTests.swift`

```swift
// RED: 通知有無チェック（ミドルウェア用）
final class CheckNotificationUseCaseTests: XCTestCase {

    /// 通知ありの場合のメッセージ
    func testReturnsNotificationMessage_WhenUnreadExists() throws {
        let repo = MockNotificationRepository()
        repo.addUnreadNotification(agentId: AgentID("agent_001"), projectId: ProjectID("proj_001"))

        let useCase = CheckNotificationUseCase(notificationRepository: repo)

        let message = try useCase.execute(agentId: AgentID("agent_001"), projectId: ProjectID("proj_001"))

        XCTAssertEqual(message, "通知があります。get_notificationsを呼び出して確認してください。")
    }

    /// 通知なしの場合のメッセージ
    func testReturnsNoNotificationMessage_WhenNoUnread() throws {
        let repo = MockNotificationRepository()

        let useCase = CheckNotificationUseCase(notificationRepository: repo)

        let message = try useCase.execute(agentId: AgentID("agent_001"), projectId: ProjectID("proj_001"))

        XCTAssertEqual(message, "通知はありません")
    }
}
```

### 3.3 GetNotificationsUseCase

**テストファイル**: `Tests/UseCaseTests/GetNotificationsUseCaseTests.swift`

```swift
// RED: 通知詳細取得
final class GetNotificationsUseCaseTests: XCTestCase {

    /// 未読通知の取得と自動既読化
    func testGetNotificationsAndMarkAsRead() throws {
        let repo = MockNotificationRepository()
        let notif1 = createTestNotification(id: "notif_001", isRead: false)
        let notif2 = createTestNotification(id: "notif_002", isRead: false)
        repo.save(notif1)
        repo.save(notif2)

        let useCase = GetNotificationsUseCase(notificationRepository: repo)

        let result = try useCase.execute(
            agentId: AgentID("agent_001"),
            projectId: ProjectID("proj_001"),
            markAsRead: true
        )

        XCTAssertEqual(result.count, 2)

        // 既読化されていることを確認
        XCTAssertFalse(try repo.hasUnreadNotifications(agentId: AgentID("agent_001"), projectId: ProjectID("proj_001")))
    }

    /// 通知の順序（作成日時降順）
    func testNotificationsOrderedByCreatedAtDesc() throws {
        // 古い通知と新しい通知を作成
        let oldNotif = createTestNotification(createdAt: Date().addingTimeInterval(-3600))
        let newNotif = createTestNotification(createdAt: Date())

        let result = try useCase.execute(...)

        XCTAssertEqual(result.first?.id, newNotif.id) // 新しい方が先
    }
}
```

---

## Phase 4: MCPServer Layer

### 4.1 NotificationMiddleware

**テストファイル**: `Tests/MCPServerTests/NotificationMiddlewareTests.swift`

```swift
// RED: 全レスポンスへの通知フィールド付加
final class NotificationMiddlewareTests: XCTestCase {

    /// 通知なしの場合のレスポンス形式
    func testResponseIncludesNoNotificationMessage() throws {
        let repo = MockNotificationRepository() // 空
        let middleware = NotificationMiddleware(
            checkNotificationUseCase: CheckNotificationUseCase(notificationRepository: repo)
        )

        let originalResult: [String: Any] = ["status": "success", "data": [...]]
        let caller = CallerInfo(agentId: AgentID("agent_001"), projectId: ProjectID("proj_001"))

        let enhanced = try middleware.enhance(result: originalResult, caller: caller)

        XCTAssertEqual(enhanced["notification"] as? String, "通知はありません")
        XCTAssertNotNil(enhanced["result"]) // 元の結果も保持
    }

    /// 通知ありの場合のレスポンス形式
    func testResponseIncludesNotificationAlert() throws {
        let repo = MockNotificationRepository()
        repo.addUnreadNotification(agentId: AgentID("agent_001"), projectId: ProjectID("proj_001"))

        let middleware = NotificationMiddleware(...)
        let enhanced = try middleware.enhance(result: [...], caller: caller)

        XCTAssertEqual(enhanced["notification"] as? String, "通知があります。get_notificationsを呼び出して確認してください。")
    }

    /// caller情報がない場合は通知チェックをスキップ
    func testSkipsNotificationCheckWhenNoCallerInfo() throws {
        let middleware = NotificationMiddleware(...)

        let enhanced = try middleware.enhance(result: [...], caller: nil)

        XCTAssertEqual(enhanced["notification"] as? String, "通知はありません")
    }
}
```

### 4.2 handleToolsCall への統合

**テストファイル**: `Tests/MCPServerTests/MCPServerNotificationTests.swift`

```swift
// RED: MCPServer統合テスト
final class MCPServerNotificationTests: XCTestCase {

    /// 全ツールレスポンスにnotificationフィールドが含まれる
    func testAllToolResponsesIncludeNotificationField() async throws {
        let server = createTestMCPServer()

        // list_tasks を呼び出し
        let response = try await server.handleToolsCall([
            "name": "list_tasks",
            "arguments": ["session_token": "valid_token"]
        ])

        let content = response["content"] as? [[String: Any]]
        let text = content?.first?["text"] as? String
        let json = try JSONSerialization.jsonObject(with: text!.data(using: .utf8)!) as? [String: Any]

        XCTAssertNotNil(json?["notification"], "All tool responses should include notification field")
    }

    /// get_my_task 呼び出し時の通知チェック
    func testGetMyTaskIncludesNotification() async throws {
        let server = createTestMCPServer()
        let notificationRepo = server.notificationRepository as! MockNotificationRepository

        // 通知を作成
        notificationRepo.addUnreadNotification(agentId: AgentID("agent_001"), projectId: ProjectID("proj_001"))

        let response = try await server.handleToolsCall([
            "name": "get_my_task",
            "arguments": ["session_token": "valid_token_for_agent_001_proj_001"]
        ])

        // レスポンスに通知アラートが含まれる
        let json = parseResponse(response)
        XCTAssertEqual(json?["notification"] as? String, "通知があります。get_notificationsを呼び出して確認してください。")
    }
}
```

### 4.3 get_notifications ツール

**テストファイル**: `Tests/MCPServerTests/GetNotificationsToolTests.swift`

```swift
// RED: get_notifications ツールテスト
final class GetNotificationsToolTests: XCTestCase {

    /// ツール定義の存在確認
    func testToolDefinitionExists() {
        let tools = ToolDefinitions.all()
        let toolNames = tools.compactMap { $0["name"] as? String }

        XCTAssertTrue(toolNames.contains("get_notifications"))
    }

    /// 通知詳細の取得
    func testGetNotificationsReturnsDetails() async throws {
        let server = createTestMCPServer()

        // 通知を作成
        let notification = Notification(
            id: NotificationID("notif_001"),
            targetAgentId: AgentID("agent_001"),
            targetProjectId: ProjectID("proj_001"),
            type: .statusChange,
            action: "blocked",
            taskId: TaskID("task_001"),
            message: "タスクのステータスがblockedに変更されました",
            instruction: "作業を中断し、report_completedをresult='blocked'で呼び出してください",
            createdAt: Date()
        )
        server.notificationRepository.save(notification)

        let response = try await server.handleToolsCall([
            "name": "get_notifications",
            "arguments": ["session_token": "valid_token"]
        ])

        let json = parseResponse(response)
        let notifications = json?["notifications"] as? [[String: Any]]

        XCTAssertEqual(notifications?.count, 1)
        XCTAssertEqual(notifications?.first?["type"] as? String, "status_change")
        XCTAssertEqual(notifications?.first?["action"] as? String, "blocked")
        XCTAssertNotNil(notifications?.first?["instruction"])
    }

    /// 取得後の自動既読化
    func testGetNotificationsMarksAsRead() async throws {
        let server = createTestMCPServer()
        server.notificationRepository.addUnreadNotification(...)

        // 1回目: 通知あり
        let response1 = try await server.handleToolsCall([
            "name": "get_notifications",
            "arguments": ["session_token": "valid_token"]
        ])
        XCTAssertEqual((parseResponse(response1)?["notifications"] as? [Any])?.count, 1)

        // 2回目: 既読化されて空
        let response2 = try await server.handleToolsCall([
            "name": "get_notifications",
            "arguments": ["session_token": "valid_token"]
        ])
        XCTAssertEqual((parseResponse(response2)?["notifications"] as? [Any])?.count, 0)
    }
}
```

---

## Phase 5: UC010 統合テスト

### 5.1 E2Eテスト

**テストファイル**: `Tests/MCPServerTests/UC010_StatusChangeInterruptTests.swift`

```swift
// RED: UC010 統合テスト
final class UC010_StatusChangeInterruptTests: XCTestCase {

    /// タスクをblockedに変更 → エージェントに通知
    func testBlockedStatusChangeCreatesNotification() async throws {
        let server = createTestMCPServer()

        // 前提: タスクがin_progressでエージェントに割り当て済み
        let task = createTestTask(status: .inProgress, assigneeId: AgentID("agent_001"))
        server.taskRepository.save(task)

        // トリガー: ステータスをblockedに変更（REST API経由を想定）
        try await server.updateTaskStatusWithNotification(
            taskId: task.id,
            status: .blocked,
            reason: "ユーザーからの要求"
        )

        // 検証: 通知が作成されている
        let hasNotification = try server.notificationRepository.hasUnreadNotifications(
            agentId: AgentID("agent_001"),
            projectId: task.projectId
        )
        XCTAssertTrue(hasNotification)
    }

    /// エージェントが任意のツール呼び出しで通知を検知
    func testAgentDetectsNotificationOnAnyToolCall() async throws {
        let server = createTestMCPServer()
        setupBlockedNotification(server, agentId: "agent_001", projectId: "proj_001")

        // エージェントが list_tasks を呼び出し
        let response = try await server.handleToolsCall([
            "name": "list_tasks",
            "arguments": ["session_token": "valid_token"]
        ])

        let json = parseResponse(response)
        XCTAssertEqual(json?["notification"] as? String, "通知があります。get_notificationsを呼び出して確認してください。")
    }

    /// エージェントが通知詳細を取得してblocked指示を受け取る
    func testAgentReceivesBlockedInstruction() async throws {
        let server = createTestMCPServer()
        setupBlockedNotification(server, agentId: "agent_001", projectId: "proj_001", taskId: "task_001")

        let response = try await server.handleToolsCall([
            "name": "get_notifications",
            "arguments": ["session_token": "valid_token"]
        ])

        let notifications = parseResponse(response)?["notifications"] as? [[String: Any]]
        let instruction = notifications?.first?["instruction"] as? String

        XCTAssertTrue(instruction?.contains("report_completed") ?? false)
        XCTAssertTrue(instruction?.contains("blocked") ?? false)
    }

    /// 完全なフロー: blocked変更 → 検知 → 詳細取得 → 報告
    func testFullBlockedInterruptFlow() async throws {
        let server = createTestMCPServer()
        let task = createTestTask(status: .inProgress, assigneeId: AgentID("agent_001"))
        server.taskRepository.save(task)

        // Step 1: ステータス変更（通知作成）
        try await server.updateTaskStatusWithNotification(taskId: task.id, status: .blocked, reason: "blockerあり")

        // Step 2: エージェントがツール呼び出し → 通知検知
        let listResponse = try await server.handleToolsCall([
            "name": "list_tasks",
            "arguments": ["session_token": "valid_token"]
        ])
        XCTAssertTrue((parseResponse(listResponse)?["notification"] as? String)?.contains("通知があります") ?? false)

        // Step 3: get_notifications呼び出し → 詳細取得
        let notifResponse = try await server.handleToolsCall([
            "name": "get_notifications",
            "arguments": ["session_token": "valid_token"]
        ])
        let notifications = parseResponse(notifResponse)?["notifications"] as? [[String: Any]]
        XCTAssertEqual(notifications?.first?["action"] as? String, "blocked")

        // Step 4: report_completed呼び出し（result=blocked）
        let reportResponse = try await server.handleToolsCall([
            "name": "report_completed",
            "arguments": [
                "session_token": "valid_token",
                "result": "blocked",
                "summary": "ユーザーからのblocked指示により中断"
            ]
        ])
        XCTAssertTrue(parseResponse(reportResponse)?["success"] as? Bool ?? false)

        // Step 5: 通知がクリアされている
        let hasNotification = try server.notificationRepository.hasUnreadNotifications(
            agentId: AgentID("agent_001"),
            projectId: task.projectId
        )
        XCTAssertFalse(hasNotification)
    }
}
```

---

## Phase 6: REST API統合

### 6.1 タスクステータス更新時の通知作成

**テストファイル**: `Tests/MCPServerTests/TaskStatusUpdateNotificationTests.swift`

```swift
// RED: REST API経由のステータス更新で通知作成
final class TaskStatusUpdateNotificationTests: XCTestCase {

    /// in_progress → blocked で通知作成
    func testInProgressToBlockedCreatesNotification() async throws {
        let server = createTestMCPServer()
        let task = createTestTask(status: .inProgress, assigneeId: AgentID("agent_001"))

        // REST APIハンドラをシミュレート
        try await server.handleTaskStatusUpdate(
            taskId: task.id,
            newStatus: .blocked,
            reason: "blockerあり"
        )

        let notifications = try server.notificationRepository.findUnreadByAgentAndProject(
            agentId: AgentID("agent_001"),
            projectId: task.projectId
        )

        XCTAssertEqual(notifications.count, 1)
        XCTAssertEqual(notifications.first?.type, .statusChange)
        XCTAssertEqual(notifications.first?.action, "blocked")
    }

    /// 担当者なしタスクは通知作成しない
    func testNoNotificationForUnassignedTask() async throws {
        let task = createTestTask(status: .inProgress, assigneeId: nil)

        try await server.handleTaskStatusUpdate(taskId: task.id, newStatus: .blocked, reason: "test")

        // 通知は作成されない（エラーにもならない）
        let count = try server.notificationRepository.countAll()
        XCTAssertEqual(count, 0)
    }

    /// backlog → todo は通知不要
    func testNoNotificationForNonInterruptingStatusChange() async throws {
        let task = createTestTask(status: .backlog, assigneeId: AgentID("agent_001"))

        try await server.handleTaskStatusUpdate(taskId: task.id, newStatus: .todo, reason: nil)

        let count = try server.notificationRepository.countAll()
        XCTAssertEqual(count, 0)
    }
}
```

---

## 実装順序

| Phase | 内容 | テストファイル | 実装ファイル |
|-------|------|---------------|-------------|
| 1.1 | Notification エンティティ | `NotificationTests.swift` | `Notification.swift` |
| 1.2 | NotificationRepository | `NotificationRepositoryTests.swift` | `NotificationRepository.swift` |
| 2.1 | SQLiteNotificationRepository | `SQLiteNotificationRepositoryTests.swift` | `SQLiteNotificationRepository.swift` + マイグレーション |
| 3.1 | CreateNotificationUseCase | `CreateNotificationUseCaseTests.swift` | `CreateNotificationUseCase.swift` |
| 3.2 | CheckNotificationUseCase | `CheckNotificationUseCaseTests.swift` | `CheckNotificationUseCase.swift` |
| 3.3 | GetNotificationsUseCase | `GetNotificationsUseCaseTests.swift` | `GetNotificationsUseCase.swift` |
| 4.1 | NotificationMiddleware | `NotificationMiddlewareTests.swift` | MCPServer内 |
| 4.2 | handleToolsCall統合 | `MCPServerNotificationTests.swift` | `MCPServer.swift` |
| 4.3 | get_notifications ツール | `GetNotificationsToolTests.swift` | `ToolDefinitions.swift` + `MCPServer.swift` |
| 5.1 | UC010 統合テスト | `UC010_StatusChangeInterruptTests.swift` | - |
| 6.1 | REST API統合 | `TaskStatusUpdateNotificationTests.swift` | REST APIハンドラ |

---

## 未確定事項への対応

| 事項 | 暫定方針 |
|------|----------|
| 通知の対象単位 | `agentId + projectId` の組み合わせ |
| 通知の有効期限 | 7日間（deleteOlderThan で定期クリーンアップ） |
| 複数通知の処理 | 全件返却、新しい順にソート |
| 通知タイプ | 初期実装は `status_change` のみ、後から拡張 |

---

## 成功基準

- [x] 全Phase のユニットテストが GREEN
- [x] UC010 統合テストが GREEN
- [x] 既存テストに影響なし（リグレッションなし）
- [x] パフォーマンス: `hasUnreadNotifications` が 10ms 以下

---

## 実装完了メモ

### 2026-01-22: UC010 完了

- **実装方式**: interrupt通知のレスポンス差替え方式を採用
- **理由**: 単にnotificationフィールドを追加するだけではエージェントが検知しない場合がある
- **統合テスト**: 60秒以内にエージェントが中断を検知することを確認
- **テスト結果**: PASSED (55.3秒)

---

## 参考

- 既存MCPServerテスト: `Tests/MCPServerTests/MCPServerTests.swift`
- 設計ドキュメント: `docs/design/NOTIFICATION_SYSTEM.md`
- UC010: `docs/usecase/UC010_TaskInterruptByStatusChange.md`
