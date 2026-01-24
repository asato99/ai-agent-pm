# 実装計画: タスク依頼・承認機能

## 概要

本ドキュメントは `TASK_REQUEST_APPROVAL.md` の設計に基づき、ユニットテストファーストで実装を進めるための詳細計画である。

### 原則

- **RED → GREEN → REFACTOR**: テストを先に書き、失敗を確認してから実装
- **小さなステップ**: 1つのテストケースに対して1つの実装変更
- **継続的な検証**: 各ステップ完了時に全テストがパスすることを確認

---

## Phase 1: ドメイン層

### 1.1 エージェント階層判定ロジック

**目的**: `isAncestorOf(ancestor, descendant)` 関数の実装

#### テストケース

```swift
// Tests/DomainTests/AgentHierarchyTests.swift

class AgentHierarchyTests: XCTestCase {

    // MARK: - 直接の親子関係

    func test_isAncestorOf_directParent_returnsTrue() {
        // Given
        let parent = Agent(id: "human-a", parentAgentId: nil)
        let child = Agent(id: "worker-a1", parentAgentId: "human-a")

        // When
        let result = AgentHierarchy.isAncestorOf(ancestor: parent, descendant: child)

        // Then
        XCTAssertTrue(result)
    }

    func test_isAncestorOf_directChild_returnsFalse() {
        // Given
        let parent = Agent(id: "human-a", parentAgentId: nil)
        let child = Agent(id: "worker-a1", parentAgentId: "human-a")

        // When
        let result = AgentHierarchy.isAncestorOf(ancestor: child, descendant: parent)

        // Then
        XCTAssertFalse(result)
    }

    // MARK: - 祖父母関係

    func test_isAncestorOf_grandparent_returnsTrue() {
        // Given: grandparent → parent → child
        let grandparent = Agent(id: "owner", parentAgentId: nil)
        let parent = Agent(id: "human-a", parentAgentId: "owner")
        let child = Agent(id: "worker-a1", parentAgentId: "human-a")

        // When
        let result = AgentHierarchy.isAncestorOf(ancestor: grandparent, descendant: child)

        // Then
        XCTAssertTrue(result)
    }

    // MARK: - 兄弟・他人関係

    func test_isAncestorOf_siblings_returnsFalse() {
        // Given
        let sibling1 = Agent(id: "worker-a1", parentAgentId: "human-a")
        let sibling2 = Agent(id: "worker-a2", parentAgentId: "human-a")

        // When
        let result = AgentHierarchy.isAncestorOf(ancestor: sibling1, descendant: sibling2)

        // Then
        XCTAssertFalse(result)
    }

    func test_isAncestorOf_unrelatedAgents_returnsFalse() {
        // Given
        let agentA = Agent(id: "worker-a1", parentAgentId: "human-a")
        let agentB = Agent(id: "worker-b1", parentAgentId: "human-b")

        // When
        let result = AgentHierarchy.isAncestorOf(ancestor: agentA, descendant: agentB)

        // Then
        XCTAssertFalse(result)
    }

    // MARK: - 自分自身

    func test_isAncestorOf_self_returnsFalse() {
        // Given
        let agent = Agent(id: "worker-a1", parentAgentId: "human-a")

        // When
        let result = AgentHierarchy.isAncestorOf(ancestor: agent, descendant: agent)

        // Then
        XCTAssertFalse(result)
    }
}
```

#### 実装ステップ

1. ❏ テストファイル作成、全テスト RED 確認
2. ❏ `AgentHierarchy.isAncestorOf` スタブ実装（常に false）
3. ❏ 直接の親子関係の実装 → 該当テスト GREEN
4. ❏ 祖父母関係の再帰実装 → 該当テスト GREEN
5. ❏ リファクタリング

---

### 1.2 Task エンティティ拡張

**目的**: Task に承認関連フィールドを追加

#### テストケース

```swift
// Tests/DomainTests/TaskApprovalTests.swift

class TaskApprovalTests: XCTestCase {

    // MARK: - ApprovalStatus

    func test_approvalStatus_defaultIsApproved() {
        // Given/When
        let task = Task(id: "task-1", title: "Test", projectId: "proj-1")

        // Then
        XCTAssertEqual(task.approvalStatus, .approved)
    }

    func test_approvalStatus_canBePendingApproval() {
        // Given
        var task = Task(id: "task-1", title: "Test", projectId: "proj-1")

        // When
        task.approvalStatus = .pendingApproval

        // Then
        XCTAssertEqual(task.approvalStatus, .pendingApproval)
    }

    // MARK: - Requester

    func test_requesterId_isNilForDirectCreation() {
        // Given/When
        let task = Task(id: "task-1", title: "Test", projectId: "proj-1")

        // Then
        XCTAssertNil(task.requesterId)
    }

    func test_requesterId_canBeSet() {
        // Given
        var task = Task(id: "task-1", title: "Test", projectId: "proj-1")

        // When
        task.requesterId = AgentID(value: "human-b")

        // Then
        XCTAssertEqual(task.requesterId?.value, "human-b")
    }

    // MARK: - Approval/Rejection

    func test_approve_setsApprovedByAndApprovedAt() {
        // Given
        var task = Task(id: "task-1", title: "Test", projectId: "proj-1")
        task.approvalStatus = .pendingApproval
        let approver = AgentID(value: "human-a")
        let approvedAt = Date()

        // When
        task.approve(by: approver, at: approvedAt)

        // Then
        XCTAssertEqual(task.approvalStatus, .approved)
        XCTAssertEqual(task.approvedBy, approver)
        XCTAssertEqual(task.approvedAt, approvedAt)
        XCTAssertEqual(task.status, .backlog)
    }

    func test_reject_setsStatusAndReason() {
        // Given
        var task = Task(id: "task-1", title: "Test", projectId: "proj-1")
        task.approvalStatus = .pendingApproval
        let reason = "優先度が低いため"

        // When
        task.reject(reason: reason)

        // Then
        XCTAssertEqual(task.approvalStatus, .rejected)
        XCTAssertEqual(task.rejectedReason, reason)
    }
}
```

#### 実装ステップ

1. ❏ テストファイル作成、全テスト RED 確認
2. ❏ `ApprovalStatus` enum 追加
3. ❏ Task に `approvalStatus` プロパティ追加 → 該当テスト GREEN
4. ❏ Task に `requesterId` プロパティ追加 → 該当テスト GREEN
5. ❏ Task に `approve(by:at:)` メソッド追加 → 該当テスト GREEN
6. ❏ Task に `reject(reason:)` メソッド追加 → 該当テスト GREEN

---

## Phase 2: インフラ層

### 2.1 DBスキーマ拡張

**目的**: tasks テーブルに承認関連カラムを追加

#### テストケース

```swift
// Tests/InfrastructureTests/TaskRepositoryApprovalTests.swift

class TaskRepositoryApprovalTests: XCTestCase {

    var repository: TaskRepository!
    var db: Database!

    override func setUp() {
        db = Database.inMemory()
        repository = TaskRepository(database: db)
    }

    // MARK: - 保存・取得

    func test_save_taskWithPendingApproval_persistsApprovalStatus() {
        // Given
        let task = Task(
            id: "task-1",
            title: "Test",
            projectId: "proj-1",
            approvalStatus: .pendingApproval,
            requesterId: AgentID(value: "human-b")
        )

        // When
        try! repository.save(task)
        let retrieved = try! repository.findById(TaskID(value: "task-1"))

        // Then
        XCTAssertEqual(retrieved?.approvalStatus, .pendingApproval)
        XCTAssertEqual(retrieved?.requesterId?.value, "human-b")
    }

    func test_save_approvedTask_persistsApprovalDetails() {
        // Given
        var task = Task(
            id: "task-1",
            title: "Test",
            projectId: "proj-1",
            approvalStatus: .pendingApproval
        )
        task.approve(by: AgentID(value: "human-a"), at: Date())

        // When
        try! repository.save(task)
        let retrieved = try! repository.findById(TaskID(value: "task-1"))

        // Then
        XCTAssertEqual(retrieved?.approvalStatus, .approved)
        XCTAssertEqual(retrieved?.approvedBy?.value, "human-a")
        XCTAssertNotNil(retrieved?.approvedAt)
    }

    func test_save_rejectedTask_persistsRejectionReason() {
        // Given
        var task = Task(
            id: "task-1",
            title: "Test",
            projectId: "proj-1",
            approvalStatus: .pendingApproval
        )
        task.reject(reason: "却下理由")

        // When
        try! repository.save(task)
        let retrieved = try! repository.findById(TaskID(value: "task-1"))

        // Then
        XCTAssertEqual(retrieved?.approvalStatus, .rejected)
        XCTAssertEqual(retrieved?.rejectedReason, "却下理由")
    }

    // MARK: - クエリ

    func test_findPendingApprovalTasks_returnsOnlyPendingTasks() {
        // Given
        let pending1 = Task(id: "task-1", title: "Pending 1", projectId: "proj-1", approvalStatus: .pendingApproval)
        let pending2 = Task(id: "task-2", title: "Pending 2", projectId: "proj-1", approvalStatus: .pendingApproval)
        let approved = Task(id: "task-3", title: "Approved", projectId: "proj-1", approvalStatus: .approved)

        try! repository.save(pending1)
        try! repository.save(pending2)
        try! repository.save(approved)

        // When
        let results = try! repository.findPendingApprovalTasks(projectId: "proj-1")

        // Then
        XCTAssertEqual(results.count, 2)
        XCTAssertTrue(results.allSatisfy { $0.approvalStatus == .pendingApproval })
    }

    func test_findPendingApprovalTasksForApprover_returnsTasksWhereApproverIsAncestor() {
        // Given: human-a is parent of worker-a1
        let task1 = Task(
            id: "task-1",
            title: "For A1",
            projectId: "proj-1",
            assigneeId: AgentID(value: "worker-a1"),
            approvalStatus: .pendingApproval
        )
        let task2 = Task(
            id: "task-2",
            title: "For B1",
            projectId: "proj-1",
            assigneeId: AgentID(value: "worker-b1"),
            approvalStatus: .pendingApproval
        )

        try! repository.save(task1)
        try! repository.save(task2)

        // When
        let results = try! repository.findPendingApprovalTasksForApprover(
            approverId: AgentID(value: "human-a"),
            projectId: "proj-1"
        )

        // Then
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.id.value, "task-1")
    }
}
```

#### 実装ステップ

1. ❏ テストファイル作成、全テスト RED 確認
2. ❏ マイグレーション: tasks テーブルにカラム追加
3. ❏ TaskRepository の save/find を拡張 → 保存・取得テスト GREEN
4. ❏ `findPendingApprovalTasks` 実装 → 該当テスト GREEN
5. ❏ `findPendingApprovalTasksForApprover` 実装 → 該当テスト GREEN

---

## Phase 3: アプリケーション層 (MCP)

### 3.1 request_task ツール

**目的**: タスク依頼を作成し、権限に応じて自動承認または承認待ちにする

#### テストケース

```swift
// Tests/MCPServerTests/RequestTaskToolTests.swift

class RequestTaskToolTests: XCTestCase {

    var mcpServer: MCPServer!
    var taskRepository: MockTaskRepository!
    var agentRepository: MockAgentRepository!
    var chatRepository: MockChatRepository!

    override func setUp() {
        taskRepository = MockTaskRepository()
        agentRepository = MockAgentRepository()
        chatRepository = MockChatRepository()
        mcpServer = MCPServer(
            taskRepository: taskRepository,
            agentRepository: agentRepository,
            chatRepository: chatRepository
        )

        // Setup hierarchy: human-a → worker-a1, human-b → worker-b1
        agentRepository.agents = [
            Agent(id: "human-a", parentAgentId: nil, type: .human),
            Agent(id: "worker-a1", parentAgentId: "human-a", type: .ai),
            Agent(id: "human-b", parentAgentId: nil, type: .human),
            Agent(id: "worker-b1", parentAgentId: "human-b", type: .ai),
        ]
    }

    // MARK: - 自動承認

    func test_requestTask_fromAncestor_autoApproves() throws {
        // Given
        let session = AgentSession(agentId: AgentID(value: "human-a"), projectId: "proj-1")

        // When
        let result = try mcpServer.requestTask(
            session: session,
            title: "Test Task",
            assigneeId: "worker-a1"
        )

        // Then
        XCTAssertEqual(result.approvalStatus, "approved")

        let savedTask = taskRepository.savedTasks.first
        XCTAssertEqual(savedTask?.approvalStatus, .approved)
        XCTAssertEqual(savedTask?.status, .backlog)
    }

    // MARK: - 承認待ち

    func test_requestTask_fromNonAncestor_createsPendingApproval() throws {
        // Given
        let session = AgentSession(agentId: AgentID(value: "human-b"), projectId: "proj-1")

        // When
        let result = try mcpServer.requestTask(
            session: session,
            title: "Test Task",
            assigneeId: "worker-a1"  // human-b is not ancestor of worker-a1
        )

        // Then
        XCTAssertEqual(result.approvalStatus, "pending_approval")
        XCTAssertEqual(result.approvers, ["human-a"])

        let savedTask = taskRepository.savedTasks.first
        XCTAssertEqual(savedTask?.approvalStatus, .pendingApproval)
        XCTAssertEqual(savedTask?.requesterId?.value, "human-b")
    }

    // MARK: - 通知

    func test_requestTask_pendingApproval_sendsSystemChatToApprovers() throws {
        // Given
        let session = AgentSession(agentId: AgentID(value: "human-b"), projectId: "proj-1")

        // When
        _ = try mcpServer.requestTask(
            session: session,
            title: "Test Task",
            assigneeId: "worker-a1"
        )

        // Then
        let notification = chatRepository.savedMessages.first
        XCTAssertEqual(notification?.receiverId.value, "human-a")
        XCTAssertEqual(notification?.type, .system)
        XCTAssertTrue(notification?.content.contains("タスク依頼") ?? false)
    }

    // MARK: - バリデーション

    func test_requestTask_withEmptyTitle_throwsError() {
        // Given
        let session = AgentSession(agentId: AgentID(value: "human-a"), projectId: "proj-1")

        // When/Then
        XCTAssertThrowsError(try mcpServer.requestTask(
            session: session,
            title: "",
            assigneeId: "worker-a1"
        )) { error in
            XCTAssertEqual(error as? MCPError, .invalidArgument("title"))
        }
    }

    func test_requestTask_withInvalidAssignee_throwsError() {
        // Given
        let session = AgentSession(agentId: AgentID(value: "human-a"), projectId: "proj-1")

        // When/Then
        XCTAssertThrowsError(try mcpServer.requestTask(
            session: session,
            title: "Test",
            assigneeId: "non-existent"
        )) { error in
            XCTAssertEqual(error as? MCPError, .agentNotFound("non-existent"))
        }
    }
}
```

#### 実装ステップ

1. ❏ テストファイル作成、全テスト RED 確認
2. ❏ `request_task` ツール定義追加
3. ❏ 自動承認ロジック実装 → 該当テスト GREEN
4. ❏ 承認待ち作成ロジック実装 → 該当テスト GREEN
5. ❏ システムチャット通知実装 → 該当テスト GREEN
6. ❏ バリデーション実装 → 該当テスト GREEN

---

### 3.2 approve_task_request ツール

#### テストケース

```swift
// Tests/MCPServerTests/ApproveTaskRequestToolTests.swift

class ApproveTaskRequestToolTests: XCTestCase {

    // MARK: - 正常系

    func test_approveTaskRequest_byAncestor_approvesTask() throws {
        // Given
        let pendingTask = Task(
            id: "task-1",
            title: "Test",
            projectId: "proj-1",
            assigneeId: AgentID(value: "worker-a1"),
            approvalStatus: .pendingApproval,
            requesterId: AgentID(value: "human-b")
        )
        taskRepository.tasks = [pendingTask]

        let session = AgentSession(agentId: AgentID(value: "human-a"), projectId: "proj-1")

        // When
        let result = try mcpServer.approveTaskRequest(session: session, taskId: "task-1")

        // Then
        XCTAssertEqual(result.status, "backlog")

        let updatedTask = taskRepository.savedTasks.first
        XCTAssertEqual(updatedTask?.approvalStatus, .approved)
        XCTAssertEqual(updatedTask?.approvedBy?.value, "human-a")
    }

    func test_approveTaskRequest_notifiesRequester() throws {
        // Given
        let pendingTask = Task(
            id: "task-1",
            title: "Test Task",
            projectId: "proj-1",
            assigneeId: AgentID(value: "worker-a1"),
            approvalStatus: .pendingApproval,
            requesterId: AgentID(value: "human-b")
        )
        taskRepository.tasks = [pendingTask]

        let session = AgentSession(agentId: AgentID(value: "human-a"), projectId: "proj-1")

        // When
        _ = try mcpServer.approveTaskRequest(session: session, taskId: "task-1")

        // Then
        let notification = chatRepository.savedMessages.first
        XCTAssertEqual(notification?.receiverId.value, "human-b")
        XCTAssertTrue(notification?.content.contains("承認されました") ?? false)
    }

    // MARK: - 権限エラー

    func test_approveTaskRequest_byNonAncestor_throwsPermissionError() {
        // Given
        let pendingTask = Task(
            id: "task-1",
            title: "Test",
            projectId: "proj-1",
            assigneeId: AgentID(value: "worker-a1"),
            approvalStatus: .pendingApproval
        )
        taskRepository.tasks = [pendingTask]

        let session = AgentSession(agentId: AgentID(value: "human-b"), projectId: "proj-1")

        // When/Then
        XCTAssertThrowsError(try mcpServer.approveTaskRequest(
            session: session,
            taskId: "task-1"
        )) { error in
            XCTAssertEqual(error as? MCPError, .permissionDenied)
        }
    }

    // MARK: - 状態エラー

    func test_approveTaskRequest_alreadyApproved_throwsError() {
        // Given
        let approvedTask = Task(
            id: "task-1",
            title: "Test",
            projectId: "proj-1",
            approvalStatus: .approved
        )
        taskRepository.tasks = [approvedTask]

        let session = AgentSession(agentId: AgentID(value: "human-a"), projectId: "proj-1")

        // When/Then
        XCTAssertThrowsError(try mcpServer.approveTaskRequest(
            session: session,
            taskId: "task-1"
        )) { error in
            XCTAssertEqual(error as? MCPError, .taskAlreadyProcessed)
        }
    }
}
```

#### 実装ステップ

1. ❏ テストファイル作成、全テスト RED 確認
2. ❏ `approve_task_request` ツール定義追加
3. ❏ 権限チェックロジック実装 → 該当テスト GREEN
4. ❏ 承認処理実装 → 該当テスト GREEN
5. ❏ 依頼者への通知実装 → 該当テスト GREEN
6. ❏ 状態チェック実装 → 該当テスト GREEN

---

### 3.3 reject_task_request ツール

#### テストケース

```swift
// Tests/MCPServerTests/RejectTaskRequestToolTests.swift

class RejectTaskRequestToolTests: XCTestCase {

    // MARK: - 正常系

    func test_rejectTaskRequest_byAncestor_rejectsTask() throws {
        // Given
        let pendingTask = Task(
            id: "task-1",
            title: "Test",
            projectId: "proj-1",
            assigneeId: AgentID(value: "worker-a1"),
            approvalStatus: .pendingApproval
        )
        taskRepository.tasks = [pendingTask]

        let session = AgentSession(agentId: AgentID(value: "human-a"), projectId: "proj-1")

        // When
        let result = try mcpServer.rejectTaskRequest(
            session: session,
            taskId: "task-1",
            reason: "優先度が低いため"
        )

        // Then
        XCTAssertEqual(result.status, "rejected")

        let updatedTask = taskRepository.savedTasks.first
        XCTAssertEqual(updatedTask?.approvalStatus, .rejected)
        XCTAssertEqual(updatedTask?.rejectedReason, "優先度が低いため")
    }

    func test_rejectTaskRequest_notifiesRequester() throws {
        // Given
        let pendingTask = Task(
            id: "task-1",
            title: "Test Task",
            projectId: "proj-1",
            assigneeId: AgentID(value: "worker-a1"),
            approvalStatus: .pendingApproval,
            requesterId: AgentID(value: "human-b")
        )
        taskRepository.tasks = [pendingTask]

        let session = AgentSession(agentId: AgentID(value: "human-a"), projectId: "proj-1")

        // When
        _ = try mcpServer.rejectTaskRequest(
            session: session,
            taskId: "task-1",
            reason: "対応不可"
        )

        // Then
        let notification = chatRepository.savedMessages.first
        XCTAssertEqual(notification?.receiverId.value, "human-b")
        XCTAssertTrue(notification?.content.contains("却下") ?? false)
        XCTAssertTrue(notification?.content.contains("対応不可") ?? false)
    }

    // MARK: - 権限エラー

    func test_rejectTaskRequest_byNonAncestor_throwsPermissionError() {
        // Given
        let pendingTask = Task(
            id: "task-1",
            title: "Test",
            projectId: "proj-1",
            assigneeId: AgentID(value: "worker-a1"),
            approvalStatus: .pendingApproval
        )
        taskRepository.tasks = [pendingTask]

        let session = AgentSession(agentId: AgentID(value: "human-b"), projectId: "proj-1")

        // When/Then
        XCTAssertThrowsError(try mcpServer.rejectTaskRequest(
            session: session,
            taskId: "task-1",
            reason: "test"
        )) { error in
            XCTAssertEqual(error as? MCPError, .permissionDenied)
        }
    }
}
```

#### 実装ステップ

1. ❏ テストファイル作成、全テスト RED 確認
2. ❏ `reject_task_request` ツール定義追加
3. ❏ 却下処理実装 → 該当テスト GREEN
4. ❏ 依頼者への通知実装 → 該当テスト GREEN
5. ❏ 権限チェック実装 → 該当テスト GREEN

---

## Phase 4: REST API

### 4.1 エンドポイント実装

#### テストケース

```swift
// Tests/RESTServerTests/TaskRequestEndpointTests.swift

class TaskRequestEndpointTests: XCTestCase {

    var app: Application!

    // MARK: - POST /api/tasks/request

    func test_postTaskRequest_autoApproved_returns200WithApproved() async throws {
        // Given
        let body = TaskRequestBody(
            title: "Test Task",
            assigneeId: "worker-a1"
        )

        // When (human-a is ancestor of worker-a1)
        let response = try await app.test(.POST, "/api/tasks/request", body: body, auth: "human-a")

        // Then
        XCTAssertEqual(response.status, .ok)
        let result = try response.decode(TaskRequestResponse.self)
        XCTAssertEqual(result.approvalStatus, "approved")
    }

    func test_postTaskRequest_pendingApproval_returns201WithPending() async throws {
        // Given
        let body = TaskRequestBody(
            title: "Test Task",
            assigneeId: "worker-a1"
        )

        // When (human-b is NOT ancestor of worker-a1)
        let response = try await app.test(.POST, "/api/tasks/request", body: body, auth: "human-b")

        // Then
        XCTAssertEqual(response.status, .created)
        let result = try response.decode(TaskRequestResponse.self)
        XCTAssertEqual(result.approvalStatus, "pending_approval")
    }

    // MARK: - POST /api/tasks/{id}/approve

    func test_postApprove_byAncestor_returns200() async throws {
        // Given: pending task for worker-a1
        let taskId = "task-pending-1"

        // When
        let response = try await app.test(.POST, "/api/tasks/\(taskId)/approve", auth: "human-a")

        // Then
        XCTAssertEqual(response.status, .ok)
        let result = try response.decode(TaskApprovalResponse.self)
        XCTAssertEqual(result.approvalStatus, "approved")
    }

    func test_postApprove_byNonAncestor_returns403() async throws {
        // Given: pending task for worker-a1
        let taskId = "task-pending-1"

        // When (human-b cannot approve tasks for worker-a1)
        let response = try await app.test(.POST, "/api/tasks/\(taskId)/approve", auth: "human-b")

        // Then
        XCTAssertEqual(response.status, .forbidden)
    }

    // MARK: - POST /api/tasks/{id}/reject

    func test_postReject_byAncestor_returns200() async throws {
        // Given
        let taskId = "task-pending-1"
        let body = RejectBody(reason: "対応不可")

        // When
        let response = try await app.test(.POST, "/api/tasks/\(taskId)/reject", body: body, auth: "human-a")

        // Then
        XCTAssertEqual(response.status, .ok)
        let result = try response.decode(TaskApprovalResponse.self)
        XCTAssertEqual(result.approvalStatus, "rejected")
    }

    // MARK: - GET /api/tasks/pending

    func test_getPendingTasks_returnsOnlyApprovableTasks() async throws {
        // When
        let response = try await app.test(.GET, "/api/tasks/pending", auth: "human-a")

        // Then
        XCTAssertEqual(response.status, .ok)
        let tasks = try response.decode([TaskResponse].self)
        XCTAssertTrue(tasks.allSatisfy { $0.approvalStatus == "pending_approval" })
    }
}
```

#### 実装ステップ

1. ❏ テストファイル作成、全テスト RED 確認
2. ❏ `POST /api/tasks/request` 実装 → 該当テスト GREEN
3. ❏ `POST /api/tasks/{id}/approve` 実装 → 該当テスト GREEN
4. ❏ `POST /api/tasks/{id}/reject` 実装 → 該当テスト GREEN
5. ❏ `GET /api/tasks/pending` 実装 → 該当テスト GREEN

---

## Phase 5: Web UI

### 5.1 タスクボード表示

#### テストケース (Playwright)

```typescript
// e2e/task-approval.spec.ts

test.describe('Task Approval on Board', () => {

  test('pending approval task shows approval badge', async ({ page }) => {
    // Given: A pending approval task exists
    await seedPendingTask({ assignee: 'worker-a1', requester: 'human-b' })

    // When
    await page.goto('/projects/proj-1')

    // Then
    const taskCard = page.locator('[data-testid="task-pending-1"]')
    await expect(taskCard).toBeVisible()
    await expect(taskCard.locator('.approval-badge')).toHaveText('承認待ち')
    await expect(taskCard).toHaveClass(/pending-approval/)
  })

  test('rejected task shows rejected state', async ({ page }) => {
    // Given
    await seedRejectedTask({ reason: '対応不可' })

    // When
    await page.goto('/projects/proj-1')

    // Then
    const taskCard = page.locator('[data-testid="task-rejected-1"]')
    await expect(taskCard.locator('.rejection-badge')).toHaveText('却下')
    await expect(taskCard).toHaveClass(/rejected/)
  })

  test('approver can see approve/reject buttons', async ({ page }) => {
    // Given
    await seedPendingTask({ assignee: 'worker-a1' })
    await loginAs('human-a')  // ancestor of worker-a1

    // When
    await page.goto('/projects/proj-1')
    const taskCard = page.locator('[data-testid="task-pending-1"]')

    // Then
    await expect(taskCard.locator('button:has-text("承認")')).toBeVisible()
    await expect(taskCard.locator('button:has-text("却下")')).toBeVisible()
  })

  test('non-approver cannot see approve/reject buttons', async ({ page }) => {
    // Given
    await seedPendingTask({ assignee: 'worker-a1' })
    await loginAs('human-b')  // NOT ancestor of worker-a1

    // When
    await page.goto('/projects/proj-1')
    const taskCard = page.locator('[data-testid="task-pending-1"]')

    // Then
    await expect(taskCard.locator('button:has-text("承認")')).not.toBeVisible()
    await expect(taskCard.locator('button:has-text("却下")')).not.toBeVisible()
  })
})
```

### 5.2 タスク作成フロー

```typescript
// e2e/task-creation-approval.spec.ts

test.describe('Task Creation with Approval', () => {

  test('creating task for subordinate creates directly', async ({ page }) => {
    // Given
    await loginAs('human-a')
    await page.goto('/projects/proj-1')

    // When
    await page.click('[data-testid="create-task-button"]')
    await page.fill('[name="title"]', 'New Task')
    await page.selectOption('[name="assignee"]', 'worker-a1')
    await page.click('button:has-text("作成")')

    // Then
    await expect(page.locator('.toast-success')).toHaveText(/タスクを作成しました/)
    const taskCard = page.locator('[data-testid="task-card"]:has-text("New Task")')
    await expect(taskCard).not.toHaveClass(/pending-approval/)
  })

  test('creating task for non-subordinate creates request', async ({ page }) => {
    // Given
    await loginAs('human-b')
    await page.goto('/projects/proj-1')

    // When
    await page.click('[data-testid="create-task-button"]')
    await page.fill('[name="title"]', 'Requested Task')
    await page.selectOption('[name="assignee"]', 'worker-a1')  // not human-b's subordinate
    await page.click('button:has-text("作成")')

    // Then
    await expect(page.locator('.toast-info')).toHaveText(/タスク依頼を送信しました/)
  })
})
```

#### 実装ステップ

1. ❏ E2Eテストファイル作成、全テスト RED 確認
2. ❏ TaskCard に approval_status 表示追加 → 該当テスト GREEN
3. ❏ 承認/却下ボタン実装 → 該当テスト GREEN
4. ❏ タスク作成時の自動振り分けロジック実装 → 該当テスト GREEN

---

## 実装チェックリスト

### Phase 1: ドメイン層
- [ ] 1.1 AgentHierarchyTests 作成・RED確認
- [ ] 1.1 isAncestorOf 実装・GREEN確認
- [ ] 1.2 TaskApprovalTests 作成・RED確認
- [ ] 1.2 Task エンティティ拡張・GREEN確認

### Phase 2: インフラ層
- [ ] 2.1 TaskRepositoryApprovalTests 作成・RED確認
- [ ] 2.1 DBマイグレーション実行
- [ ] 2.1 TaskRepository 拡張・GREEN確認

### Phase 3: アプリケーション層
- [ ] 3.1 RequestTaskToolTests 作成・RED確認
- [ ] 3.1 request_task 実装・GREEN確認
- [ ] 3.2 ApproveTaskRequestToolTests 作成・RED確認
- [ ] 3.2 approve_task_request 実装・GREEN確認
- [ ] 3.3 RejectTaskRequestToolTests 作成・RED確認
- [ ] 3.3 reject_task_request 実装・GREEN確認

### Phase 4: REST API
- [ ] 4.1 TaskRequestEndpointTests 作成・RED確認
- [ ] 4.1 各エンドポイント実装・GREEN確認

### Phase 5: Web UI
- [ ] 5.1 E2Eテスト作成・RED確認
- [ ] 5.1 タスクボード表示実装・GREEN確認
- [ ] 5.2 タスク作成フロー実装・GREEN確認

---

## 完了条件

1. 全ユニットテストがパス
2. 全E2Eテストがパス
3. 既存テストに影響なし（リグレッションなし）
4. 設計ドキュメントと実装が一致
