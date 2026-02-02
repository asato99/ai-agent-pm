# Phase 3: プル型アーキテクチャ実装計画

タスク実行をプル型アーキテクチャに移行するためのTDD実装計画。

---

## 概要

### 変更の背景

アプリがCLIを直接実行する設計から、外部Runnerがポーリングしてタスクを実行するプル型設計へ移行する。

```
旧: アプリ → CLI実行（プッシュ型）
新: Runner → MCP → タスク取得 → CLI実行（プル型）
```

### 成功基準

```
1. Runner が authenticate でセッションを取得できる
2. Runner が get_pending_tasks で自分のタスクを取得できる
3. Runner が report_execution_start/complete で実行ログを報告できる
4. アプリでエージェントのPasskeyを管理できる
5. アプリで実行ログを閲覧できる
```

---

## 実装フェーズ

```
┌─────────────────────────────────────────────────────────────────────────┐
│  Phase 3-1       Phase 3-2       Phase 3-3       Phase 3-4              │
│  認証基盤        タスク取得       実行ログ         UI統合                │
│  ━━━━━━━━        ━━━━━━━━        ━━━━━━━━        ━━━━━━                  │
│                                                                          │
│  • Domain        • MCP Tool      • Domain        • Agent設定画面         │
│    - Session     • UseCase       • Repository    • 実行ログ画面          │
│    - Credential  • Repository    • MCP Tool      • Passkey管理           │
│  • Repository                                                            │
│  • MCP Tools                                                             │
│                                                                          │
│  Week 1          Week 2          Week 3          Week 4                  │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## Phase 3-1: 認証基盤（Week 1）

### 3-1-1: Domain層 - AgentCredential

**Red: 失敗するテストを書く**

```swift
// Tests/DomainTests/AgentCredentialTests.swift

final class AgentCredentialTests: XCTestCase {

    // MARK: - Passkey Hash

    func test_createCredential_hashesPasskey() {
        // Given
        let agentId = AgentID(value: "agt_test")
        let rawPasskey = "secret123"

        // When
        let credential = AgentCredential(
            agentId: agentId,
            rawPasskey: rawPasskey
        )

        // Then
        XCTAssertNotEqual(credential.passkeyHash, rawPasskey)
        XCTAssertTrue(credential.passkeyHash.starts(with: "$2"))  // bcrypt
    }

    func test_verifyPasskey_withCorrectPasskey_returnsTrue() {
        // Given
        let credential = AgentCredential(
            agentId: AgentID(value: "agt_test"),
            rawPasskey: "secret123"
        )

        // When
        let result = credential.verify(passkey: "secret123")

        // Then
        XCTAssertTrue(result)
    }

    func test_verifyPasskey_withWrongPasskey_returnsFalse() {
        // Given
        let credential = AgentCredential(
            agentId: AgentID(value: "agt_test"),
            rawPasskey: "secret123"
        )

        // When
        let result = credential.verify(passkey: "wrongpassword")

        // Then
        XCTAssertFalse(result)
    }
}
```

**Green: テストを通す最小限の実装**

```swift
// Sources/Domain/Entities/AgentCredential.swift

import Foundation
import CryptoKit

public struct AgentCredential: Identifiable, Sendable {
    public let id: AgentCredentialID
    public let agentId: AgentID
    public let passkeyHash: String
    public let createdAt: Date
    public var lastUsedAt: Date?

    public init(
        id: AgentCredentialID = AgentCredentialID(),
        agentId: AgentID,
        rawPasskey: String,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.agentId = agentId
        self.passkeyHash = Self.hashPasskey(rawPasskey)
        self.createdAt = createdAt
    }

    public func verify(passkey: String) -> Bool {
        // bcrypt verification
        return BCrypt.verify(passkey, against: passkeyHash)
    }

    private static func hashPasskey(_ passkey: String) -> String {
        return BCrypt.hash(passkey)
    }
}
```

### 3-1-2: Domain層 - AgentSession

**Red: テスト**

```swift
// Tests/DomainTests/AgentSessionTests.swift

final class AgentSessionTests: XCTestCase {

    func test_createSession_generatesUniqueToken() {
        // Given/When
        let session1 = AgentSession(agentId: AgentID(value: "agt_1"))
        let session2 = AgentSession(agentId: AgentID(value: "agt_1"))

        // Then
        XCTAssertNotEqual(session1.token, session2.token)
    }

    func test_createSession_expiresInOneHour() {
        // Given
        let now = Date()

        // When
        let session = AgentSession(agentId: AgentID(value: "agt_1"))

        // Then
        let expectedExpiry = now.addingTimeInterval(3600)
        XCTAssertEqual(
            session.expiresAt.timeIntervalSince1970,
            expectedExpiry.timeIntervalSince1970,
            accuracy: 1.0
        )
    }

    func test_isExpired_beforeExpiry_returnsFalse() {
        // Given
        let session = AgentSession(agentId: AgentID(value: "agt_1"))

        // When/Then
        XCTAssertFalse(session.isExpired)
    }

    func test_isExpired_afterExpiry_returnsTrue() {
        // Given
        let session = AgentSession(
            agentId: AgentID(value: "agt_1"),
            expiresAt: Date().addingTimeInterval(-1)  // 1秒前に期限切れ
        )

        // When/Then
        XCTAssertTrue(session.isExpired)
    }
}
```

**Green: 実装**

```swift
// Sources/Domain/Entities/AgentSession.swift

import Foundation

public struct AgentSession: Identifiable, Sendable {
    public let id: AgentSessionID
    public let token: String
    public let agentId: AgentID
    public let expiresAt: Date
    public let createdAt: Date

    public var isExpired: Bool {
        Date() > expiresAt
    }

    public init(
        id: AgentSessionID = AgentSessionID(),
        agentId: AgentID,
        expiresAt: Date? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.token = "sess_\(UUID().uuidString)"
        self.agentId = agentId
        self.expiresAt = expiresAt ?? createdAt.addingTimeInterval(3600)
        self.createdAt = createdAt
    }
}
```

### 3-1-3: Repository層

**Red: テスト**

```swift
// Tests/InfrastructureTests/AgentCredentialRepositoryTests.swift

final class AgentCredentialRepositoryTests: XCTestCase {
    var db: DatabaseQueue!
    var repository: AgentCredentialRepository!

    override func setUp() async throws {
        db = try DatabaseQueue()
        try DatabaseSetup.migrate(db)
        repository = AgentCredentialRepository(db: db)
    }

    func test_save_persistsCredential() throws {
        // Given
        let credential = AgentCredential(
            agentId: AgentID(value: "agt_test"),
            rawPasskey: "secret123"
        )

        // When
        try repository.save(credential)

        // Then
        let found = try repository.findByAgentId(credential.agentId)
        XCTAssertNotNil(found)
        XCTAssertEqual(found?.agentId, credential.agentId)
    }

    func test_findByAgentId_whenNotExists_returnsNil() throws {
        // Given/When
        let found = try repository.findByAgentId(AgentID(value: "nonexistent"))

        // Then
        XCTAssertNil(found)
    }

    func test_delete_removesCredential() throws {
        // Given
        let credential = AgentCredential(
            agentId: AgentID(value: "agt_test"),
            rawPasskey: "secret123"
        )
        try repository.save(credential)

        // When
        try repository.delete(credential.id)

        // Then
        let found = try repository.findByAgentId(credential.agentId)
        XCTAssertNil(found)
    }
}
```

```swift
// Tests/InfrastructureTests/AgentSessionRepositoryTests.swift

final class AgentSessionRepositoryTests: XCTestCase {
    var db: DatabaseQueue!
    var repository: AgentSessionRepository!

    override func setUp() async throws {
        db = try DatabaseQueue()
        try DatabaseSetup.migrate(db)
        repository = AgentSessionRepository(db: db)
    }

    func test_save_persistsSession() throws {
        // Given
        let session = AgentSession(agentId: AgentID(value: "agt_test"))

        // When
        try repository.save(session)

        // Then
        let found = try repository.findByToken(session.token)
        XCTAssertNotNil(found)
        XCTAssertEqual(found?.agentId, session.agentId)
    }

    func test_findByToken_withExpiredSession_returnsNil() throws {
        // Given
        let session = AgentSession(
            agentId: AgentID(value: "agt_test"),
            expiresAt: Date().addingTimeInterval(-1)
        )
        try repository.save(session)

        // When
        let found = try repository.findByToken(session.token)

        // Then
        XCTAssertNil(found)  // 期限切れセッションは返さない
    }

    func test_deleteExpired_removesOldSessions() throws {
        // Given
        let expiredSession = AgentSession(
            agentId: AgentID(value: "agt_1"),
            expiresAt: Date().addingTimeInterval(-100)
        )
        let validSession = AgentSession(agentId: AgentID(value: "agt_2"))
        try repository.save(expiredSession)
        try repository.save(validSession)

        // When
        try repository.deleteExpired()

        // Then
        XCTAssertNil(try repository.findByToken(expiredSession.token))
        XCTAssertNotNil(try repository.findByToken(validSession.token))
    }
}
```

### 3-1-4: UseCase層 - 認証

**Red: テスト**

```swift
// Tests/UseCaseTests/AuthenticateUseCaseTests.swift

final class AuthenticateUseCaseTests: XCTestCase {
    var mockCredentialRepository: MockAgentCredentialRepository!
    var mockSessionRepository: MockAgentSessionRepository!
    var useCase: AuthenticateUseCase!

    override func setUp() {
        mockCredentialRepository = MockAgentCredentialRepository()
        mockSessionRepository = MockAgentSessionRepository()
        useCase = AuthenticateUseCase(
            credentialRepository: mockCredentialRepository,
            sessionRepository: mockSessionRepository
        )
    }

    func test_execute_withValidCredentials_returnsSession() throws {
        // Given
        let credential = AgentCredential(
            agentId: AgentID(value: "agt_test"),
            rawPasskey: "secret123"
        )
        mockCredentialRepository.credentials[credential.agentId] = credential

        // When
        let result = try useCase.execute(
            agentId: "agt_test",
            passkey: "secret123"
        )

        // Then
        XCTAssertTrue(result.success)
        XCTAssertNotNil(result.sessionToken)
        XCTAssertEqual(result.expiresIn, 3600)
    }

    func test_execute_withInvalidPasskey_returnsError() throws {
        // Given
        let credential = AgentCredential(
            agentId: AgentID(value: "agt_test"),
            rawPasskey: "secret123"
        )
        mockCredentialRepository.credentials[credential.agentId] = credential

        // When
        let result = try useCase.execute(
            agentId: "agt_test",
            passkey: "wrongpassword"
        )

        // Then
        XCTAssertFalse(result.success)
        XCTAssertNil(result.sessionToken)
        XCTAssertEqual(result.error, "Invalid agent_id or passkey")
    }

    func test_execute_withUnknownAgentId_returnsError() throws {
        // Given/When
        let result = try useCase.execute(
            agentId: "unknown_agent",
            passkey: "anypasskey"
        )

        // Then
        XCTAssertFalse(result.success)
        XCTAssertEqual(result.error, "Invalid agent_id or passkey")
    }

    func test_execute_savesSessionToRepository() throws {
        // Given
        let credential = AgentCredential(
            agentId: AgentID(value: "agt_test"),
            rawPasskey: "secret123"
        )
        mockCredentialRepository.credentials[credential.agentId] = credential

        // When
        _ = try useCase.execute(
            agentId: "agt_test",
            passkey: "secret123"
        )

        // Then
        XCTAssertEqual(mockSessionRepository.saveCallCount, 1)
    }
}
```

### 3-1-5: MCP Tool - authenticate

**Red: テスト**

```swift
// Tests/MCPServerTests/AuthenticateToolTests.swift

final class AuthenticateToolTests: XCTestCase {
    var mockUseCase: MockAuthenticateUseCase!
    var tool: AuthenticateTool!

    override func setUp() {
        mockUseCase = MockAuthenticateUseCase()
        tool = AuthenticateTool(authenticateUseCase: mockUseCase)
    }

    func test_execute_withValidInput_returnsSuccessResponse() async throws {
        // Given
        mockUseCase.resultToReturn = AuthenticateResult(
            success: true,
            sessionToken: "sess_xxx",
            expiresIn: 3600,
            agentName: "test-agent"
        )
        let input: [String: Any] = [
            "agent_id": "agt_test",
            "passkey": "secret123"
        ]

        // When
        let response = try await tool.execute(input: input)

        // Then
        XCTAssertEqual(response["success"] as? Bool, true)
        XCTAssertEqual(response["session_token"] as? String, "sess_xxx")
        XCTAssertEqual(response["expires_in"] as? Int, 3600)
    }

    func test_execute_withMissingAgentId_returnsError() async throws {
        // Given
        let input: [String: Any] = ["passkey": "secret123"]

        // When
        let response = try await tool.execute(input: input)

        // Then
        XCTAssertEqual(response["success"] as? Bool, false)
        XCTAssertNotNil(response["error"])
    }
}
```

---

## Phase 3-2: タスク取得（Week 2）

### 3-2-1: UseCase - GetPendingTasks

**Red: テスト**

```swift
// Tests/UseCaseTests/GetPendingTasksUseCaseTests.swift

final class GetPendingTasksUseCaseTests: XCTestCase {
    var mockSessionRepository: MockAgentSessionRepository!
    var mockTaskRepository: MockTaskRepository!
    var useCase: GetPendingTasksUseCase!

    override func setUp() {
        mockSessionRepository = MockAgentSessionRepository()
        mockTaskRepository = MockTaskRepository()
        useCase = GetPendingTasksUseCase(
            sessionRepository: mockSessionRepository,
            taskRepository: mockTaskRepository
        )
    }

    func test_execute_withValidSession_returnsAssignedTasks() throws {
        // Given
        let session = AgentSession(agentId: AgentID(value: "agt_test"))
        mockSessionRepository.sessions[session.token] = session

        let task = Task(
            id: TaskID(value: "tsk_1"),
            projectId: ProjectID(value: "prj_1"),
            title: "Test Task",
            status: .inProgress,
            assigneeId: AgentID(value: "agt_test")
        )
        mockTaskRepository.tasks = [task]

        // When
        let result = try useCase.execute(sessionToken: session.token)

        // Then
        XCTAssertTrue(result.success)
        XCTAssertEqual(result.tasks.count, 1)
        XCTAssertEqual(result.tasks.first?.taskId, "tsk_1")
    }

    func test_execute_withExpiredSession_returnsError() throws {
        // Given
        let expiredSession = AgentSession(
            agentId: AgentID(value: "agt_test"),
            expiresAt: Date().addingTimeInterval(-1)
        )
        // Note: findByToken should return nil for expired sessions

        // When
        let result = try useCase.execute(sessionToken: expiredSession.token)

        // Then
        XCTAssertFalse(result.success)
        XCTAssertEqual(result.error, "Invalid or expired session_token")
    }

    func test_execute_returnsOnlyInProgressTasks() throws {
        // Given
        let session = AgentSession(agentId: AgentID(value: "agt_test"))
        mockSessionRepository.sessions[session.token] = session

        let inProgressTask = Task(
            id: TaskID(value: "tsk_1"),
            projectId: ProjectID(value: "prj_1"),
            title: "In Progress",
            status: .inProgress,
            assigneeId: AgentID(value: "agt_test")
        )
        let doneTask = Task(
            id: TaskID(value: "tsk_2"),
            projectId: ProjectID(value: "prj_1"),
            title: "Done",
            status: .done,
            assigneeId: AgentID(value: "agt_test")
        )
        mockTaskRepository.tasks = [inProgressTask, doneTask]

        // When
        let result = try useCase.execute(sessionToken: session.token)

        // Then
        XCTAssertEqual(result.tasks.count, 1)
        XCTAssertEqual(result.tasks.first?.taskId, "tsk_1")
    }
}
```

### 3-2-2: Repository - Task拡張

**Red: テスト**

```swift
// Tests/InfrastructureTests/TaskRepositoryPendingTests.swift

final class TaskRepositoryPendingTests: XCTestCase {
    var db: DatabaseQueue!
    var repository: TaskRepository!

    func test_findPendingByAssignee_returnsOnlyInProgressTasks() throws {
        // Given
        let agentId = AgentID(value: "agt_test")
        let projectId = ProjectID(value: "prj_1")

        try repository.save(Task(
            id: TaskID(value: "tsk_1"),
            projectId: projectId,
            title: "In Progress Task",
            status: .inProgress,
            assigneeId: agentId
        ))
        try repository.save(Task(
            id: TaskID(value: "tsk_2"),
            projectId: projectId,
            title: "Done Task",
            status: .done,
            assigneeId: agentId
        ))
        try repository.save(Task(
            id: TaskID(value: "tsk_3"),
            projectId: projectId,
            title: "Other Agent Task",
            status: .inProgress,
            assigneeId: AgentID(value: "agt_other")
        ))

        // When
        let result = try repository.findPendingByAssignee(agentId)

        // Then
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.id.value, "tsk_1")
    }
}
```

---

## Phase 3-3: 実行ログ（Week 3）

### 3-3-1: Domain - ExecutionLog

**Red: テスト**

```swift
// Tests/DomainTests/ExecutionLogTests.swift

final class ExecutionLogTests: XCTestCase {

    func test_createExecutionLog_setsStatusToRunning() {
        // Given/When
        let log = ExecutionLog(
            taskId: TaskID(value: "tsk_1"),
            agentId: AgentID(value: "agt_1")
        )

        // Then
        XCTAssertEqual(log.status, .running)
        XCTAssertNil(log.completedAt)
        XCTAssertNil(log.exitCode)
    }

    func test_complete_updatesStatusAndFields() {
        // Given
        var log = ExecutionLog(
            taskId: TaskID(value: "tsk_1"),
            agentId: AgentID(value: "agt_1")
        )

        // When
        log.complete(
            exitCode: 0,
            durationSeconds: 120.5,
            logFilePath: "/path/to/log"
        )

        // Then
        XCTAssertEqual(log.status, .completed)
        XCTAssertNotNil(log.completedAt)
        XCTAssertEqual(log.exitCode, 0)
        XCTAssertEqual(log.durationSeconds, 120.5)
        XCTAssertEqual(log.logFilePath, "/path/to/log")
    }

    func test_complete_withNonZeroExitCode_setsStatusToFailed() {
        // Given
        var log = ExecutionLog(
            taskId: TaskID(value: "tsk_1"),
            agentId: AgentID(value: "agt_1")
        )

        // When
        log.complete(
            exitCode: 1,
            durationSeconds: 60,
            logFilePath: "/path/to/log"
        )

        // Then
        XCTAssertEqual(log.status, .failed)
    }
}
```

### 3-3-2: Repository - ExecutionLog

**Red: テスト**

```swift
// Tests/InfrastructureTests/ExecutionLogRepositoryTests.swift

final class ExecutionLogRepositoryTests: XCTestCase {
    var db: DatabaseQueue!
    var repository: ExecutionLogRepository!

    func test_save_persistsExecutionLog() throws {
        // Given
        let log = ExecutionLog(
            taskId: TaskID(value: "tsk_1"),
            agentId: AgentID(value: "agt_1")
        )

        // When
        try repository.save(log)

        // Then
        let found = try repository.findById(log.id)
        XCTAssertNotNil(found)
        XCTAssertEqual(found?.taskId, log.taskId)
    }

    func test_findByTaskId_returnsLogsOrderedByDate() throws {
        // Given
        let taskId = TaskID(value: "tsk_1")
        let log1 = ExecutionLog(
            taskId: taskId,
            agentId: AgentID(value: "agt_1"),
            startedAt: Date().addingTimeInterval(-200)
        )
        let log2 = ExecutionLog(
            taskId: taskId,
            agentId: AgentID(value: "agt_1"),
            startedAt: Date().addingTimeInterval(-100)
        )
        try repository.save(log1)
        try repository.save(log2)

        // When
        let logs = try repository.findByTaskId(taskId)

        // Then
        XCTAssertEqual(logs.count, 2)
        XCTAssertEqual(logs.first?.id, log2.id)  // 新しい順
    }

    func test_findByAgentId_withLimit_respectsLimit() throws {
        // Given
        let agentId = AgentID(value: "agt_1")
        for i in 0..<5 {
            try repository.save(ExecutionLog(
                taskId: TaskID(value: "tsk_\(i)"),
                agentId: agentId
            ))
        }

        // When
        let logs = try repository.findByAgentId(agentId, limit: 3)

        // Then
        XCTAssertEqual(logs.count, 3)
    }
}
```

### 3-3-3: MCP Tool - report_execution_start/complete

**Red: テスト**

```swift
// Tests/MCPServerTests/ReportExecutionStartToolTests.swift

final class ReportExecutionStartToolTests: XCTestCase {

    func test_execute_createsExecutionLogAndReturnsId() async throws {
        // Given
        let mockUseCase = MockReportExecutionStartUseCase()
        mockUseCase.resultToReturn = ReportExecutionStartResult(
            success: true,
            executionId: "exec_abc123",
            startedAt: Date()
        )
        let tool = ReportExecutionStartTool(useCase: mockUseCase)

        // When
        let response = try await tool.execute(input: [
            "session_token": "sess_xxx",
            "task_id": "tsk_1"
        ])

        // Then
        XCTAssertEqual(response["success"] as? Bool, true)
        XCTAssertEqual(response["execution_id"] as? String, "exec_abc123")
    }
}
```

---

## Phase 3-4: UI統合（Week 4）

### 3-4-1: エージェント設定画面 - Passkey管理

**Red: UIテスト**

```swift
// UITests/PRD/PRD03_AgentManagementTests.swift

func test_agentDetail_showsPasskeySection() throws {
    // Given
    app.launch()
    navigateToAgentManagement()

    // When
    app.staticTexts["uitest_agent"].tap()

    // Then
    XCTAssertTrue(app.staticTexts["Passkey"].exists)
    XCTAssertTrue(app.buttons["ShowPasskeyButton"].exists)
    XCTAssertTrue(app.buttons["RegeneratePasskeyButton"].exists)
}

func test_regeneratePasskey_showsConfirmationAndUpdates() throws {
    // Given
    app.launch()
    navigateToAgentManagement()
    app.staticTexts["uitest_agent"].tap()

    // When
    app.buttons["RegeneratePasskeyButton"].tap()
    app.buttons["ConfirmButton"].tap()

    // Then
    // パスキーが更新されたことを確認（実際の値は非表示）
    XCTAssertTrue(app.staticTexts["Passkey updated"].waitForExistence(timeout: 2))
}
```

### 3-4-2: 実行ログ画面

**Red: UIテスト**

```swift
// UITests/PRD/PRD04_TaskDetailTests.swift

func test_taskDetail_showsExecutionHistory() throws {
    // Given
    app.launch()
    navigateToTask(id: "uitest_task")

    // When
    // (自動表示)

    // Then
    XCTAssertTrue(app.staticTexts["Execution History"].exists)
}

func test_executionLog_clickShowsLogContent() throws {
    // Given
    app.launch()
    navigateToTask(id: "uitest_task")

    // When
    app.buttons["ShowLogButton_exec_1"].tap()

    // Then
    XCTAssertTrue(app.textViews["LogContentView"].exists)
}
```

---

## Phase 3-5: Runner実装（Week 5-6）

### 概要

RunnerはMCP経由でタスクをポーリングし、CLI（Claude/Gemini）を実行する外部プログラム。
アプリにバンドルされるサンプル実装と、ユーザーがカスタマイズ可能な構造を提供する。

```
┌─────────────────────────────────────────────────────────────────┐
│  Runner アーキテクチャ                                           │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  ┌──────────────┐    ┌──────────────┐    ┌──────────────┐       │
│  │ RunnerConfig │───▶│ RunnerCore   │───▶│ CLIExecutor  │       │
│  │              │    │              │    │              │       │
│  │ • agent_id   │    │ • 認証       │    │ • claude     │       │
│  │ • passkey    │    │ • ポーリング │    │ • gemini     │       │
│  │ • interval   │    │ • ログ報告   │    │ • custom     │       │
│  └──────────────┘    └──────────────┘    └──────────────┘       │
│                              │                                   │
│                              ▼                                   │
│                      ┌──────────────┐                           │
│                      │ MCPClient    │                           │
│                      │              │                           │
│                      │ • authenticate│                          │
│                      │ • get_tasks  │                           │
│                      │ • report_*   │                           │
│                      └──────────────┘                           │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### 3-5-1: Runner Core（Python）

**ディレクトリ構成**

```
runner/
├── pyproject.toml
├── src/
│   └── aiagent_runner/
│       ├── __init__.py
│       ├── config.py
│       ├── mcp_client.py
│       ├── runner.py
│       ├── executor.py
│       └── prompt_builder.py
└── tests/
    ├── conftest.py
    ├── test_config.py
    ├── test_mcp_client.py
    ├── test_runner.py
    ├── test_executor.py
    └── test_prompt_builder.py
```

**Red: テスト - Config**

```python
# tests/test_config.py

import pytest
from aiagent_runner.config import RunnerConfig

class TestRunnerConfig:

    def test_from_env_loads_required_fields(self, monkeypatch):
        """環境変数から設定を読み込む"""
        # Given
        monkeypatch.setenv("AGENT_ID", "agt_test")
        monkeypatch.setenv("AGENT_PASSKEY", "secret123")

        # When
        config = RunnerConfig.from_env()

        # Then
        assert config.agent_id == "agt_test"
        assert config.passkey == "secret123"
        assert config.polling_interval == 5  # デフォルト値

    def test_from_env_missing_agent_id_raises_error(self, monkeypatch):
        """AGENT_IDが未設定の場合エラー"""
        # Given
        monkeypatch.delenv("AGENT_ID", raising=False)
        monkeypatch.setenv("AGENT_PASSKEY", "secret123")

        # When/Then
        with pytest.raises(ValueError, match="AGENT_ID"):
            RunnerConfig.from_env()

    def test_from_yaml_loads_config_file(self, tmp_path):
        """YAMLファイルから設定を読み込む"""
        # Given
        config_file = tmp_path / "config.yaml"
        config_file.write_text("""
agent_id: agt_yaml_test
passkey: yaml_secret
polling_interval: 10
cli_command: gemini
working_directory: /path/to/project
""")

        # When
        config = RunnerConfig.from_yaml(config_file)

        # Then
        assert config.agent_id == "agt_yaml_test"
        assert config.passkey == "yaml_secret"
        assert config.polling_interval == 10
        assert config.cli_command == "gemini"

    def test_validate_rejects_invalid_interval(self):
        """polling_intervalが0以下の場合エラー"""
        # Given/When/Then
        with pytest.raises(ValueError, match="polling_interval"):
            RunnerConfig(
                agent_id="agt_test",
                passkey="secret",
                polling_interval=0
            )
```

**Green: 実装 - Config**

```python
# src/aiagent_runner/config.py

import os
from dataclasses import dataclass, field
from pathlib import Path
from typing import Optional
import yaml

@dataclass
class RunnerConfig:
    agent_id: str
    passkey: str
    polling_interval: int = 5
    cli_command: str = "claude"
    cli_args: list[str] = field(default_factory=lambda: ["--dangerously-skip-permissions"])
    working_directory: Optional[str] = None
    log_directory: Optional[str] = None
    mcp_socket_path: Optional[str] = None

    def __post_init__(self):
        if self.polling_interval <= 0:
            raise ValueError("polling_interval must be positive")
        if not self.agent_id:
            raise ValueError("agent_id is required")
        if not self.passkey:
            raise ValueError("passkey is required")

    @classmethod
    def from_env(cls) -> "RunnerConfig":
        """環境変数から設定を読み込む"""
        agent_id = os.environ.get("AGENT_ID")
        passkey = os.environ.get("AGENT_PASSKEY")

        if not agent_id:
            raise ValueError("AGENT_ID environment variable is required")
        if not passkey:
            raise ValueError("AGENT_PASSKEY environment variable is required")

        return cls(
            agent_id=agent_id,
            passkey=passkey,
            polling_interval=int(os.environ.get("POLLING_INTERVAL", "5")),
            cli_command=os.environ.get("CLI_COMMAND", "claude"),
            working_directory=os.environ.get("WORKING_DIRECTORY"),
            log_directory=os.environ.get("LOG_DIRECTORY"),
        )

    @classmethod
    def from_yaml(cls, path: Path) -> "RunnerConfig":
        """YAMLファイルから設定を読み込む"""
        with open(path) as f:
            data = yaml.safe_load(f)
        return cls(**data)
```

### 3-5-2: MCP Client

**Red: テスト**

```python
# tests/test_mcp_client.py

import pytest
from unittest.mock import AsyncMock, patch
from aiagent_runner.mcp_client import MCPClient, AuthenticationError, SessionExpiredError

class TestMCPClient:

    @pytest.fixture
    def client(self):
        return MCPClient(socket_path="/tmp/mcp.sock")

    @pytest.mark.asyncio
    async def test_authenticate_success(self, client):
        """認証成功時にセッショントークンを返す"""
        # Given
        with patch.object(client, '_call_tool', new_callable=AsyncMock) as mock:
            mock.return_value = {
                "success": True,
                "session_token": "sess_abc123",
                "expires_in": 3600
            }

            # When
            result = await client.authenticate("agt_test", "secret123")

            # Then
            assert result.session_token == "sess_abc123"
            assert result.expires_in == 3600
            mock.assert_called_once_with("authenticate", {
                "agent_id": "agt_test",
                "passkey": "secret123"
            })

    @pytest.mark.asyncio
    async def test_authenticate_failure_raises_error(self, client):
        """認証失敗時にAuthenticationErrorを発生"""
        # Given
        with patch.object(client, '_call_tool', new_callable=AsyncMock) as mock:
            mock.return_value = {
                "success": False,
                "error": "Invalid agent_id or passkey"
            }

            # When/Then
            with pytest.raises(AuthenticationError, match="Invalid"):
                await client.authenticate("agt_test", "wrong_password")

    @pytest.mark.asyncio
    async def test_get_pending_tasks_returns_task_list(self, client):
        """実行待ちタスクのリストを返す"""
        # Given
        with patch.object(client, '_call_tool', new_callable=AsyncMock) as mock:
            mock.return_value = {
                "success": True,
                "tasks": [
                    {
                        "taskId": "tsk_1",
                        "projectId": "prj_1",
                        "title": "Test Task",
                        "description": "Do something",
                        "priority": "high",
                        "workingDirectory": "/path/to/project"
                    }
                ]
            }

            # When
            tasks = await client.get_pending_tasks("sess_abc123")

            # Then
            assert len(tasks) == 1
            assert tasks[0].task_id == "tsk_1"
            assert tasks[0].title == "Test Task"

    @pytest.mark.asyncio
    async def test_get_pending_tasks_expired_session_raises_error(self, client):
        """セッション期限切れ時にSessionExpiredErrorを発生"""
        # Given
        with patch.object(client, '_call_tool', new_callable=AsyncMock) as mock:
            mock.return_value = {
                "success": False,
                "error": "Invalid or expired session_token"
            }

            # When/Then
            with pytest.raises(SessionExpiredError):
                await client.get_pending_tasks("expired_token")

    @pytest.mark.asyncio
    async def test_report_execution_start_returns_execution_id(self, client):
        """実行開始報告でexecution_idを返す"""
        # Given
        with patch.object(client, '_call_tool', new_callable=AsyncMock) as mock:
            mock.return_value = {
                "success": True,
                "execution_id": "exec_xyz789",
                "started_at": "2026-01-06T10:00:00Z"
            }

            # When
            result = await client.report_execution_start("sess_abc", "tsk_1")

            # Then
            assert result.execution_id == "exec_xyz789"

    @pytest.mark.asyncio
    async def test_report_execution_complete_success(self, client):
        """実行完了報告"""
        # Given
        with patch.object(client, '_call_tool', new_callable=AsyncMock) as mock:
            mock.return_value = {"success": True}

            # When
            await client.report_execution_complete(
                session_token="sess_abc",
                execution_id="exec_xyz",
                exit_code=0,
                duration_seconds=120.5,
                log_file_path="/path/to/log"
            )

            # Then
            mock.assert_called_once()
```

**Green: 実装**

```python
# src/aiagent_runner/mcp_client.py

import asyncio
import json
from dataclasses import dataclass
from typing import Optional
from datetime import datetime

class AuthenticationError(Exception):
    pass

class SessionExpiredError(Exception):
    pass

class MCPError(Exception):
    pass

@dataclass
class AuthResult:
    session_token: str
    expires_in: int
    agent_name: Optional[str] = None

@dataclass
class TaskInfo:
    task_id: str
    project_id: str
    title: str
    description: str
    priority: str
    working_directory: str

@dataclass
class ExecutionStartResult:
    execution_id: str
    started_at: datetime

class MCPClient:
    def __init__(self, socket_path: Optional[str] = None):
        self.socket_path = socket_path or self._default_socket_path()
        self._session_token: Optional[str] = None

    def _default_socket_path(self) -> str:
        import os
        return os.path.expanduser(
            "~/Library/Application Support/AIAgentPM/mcp.sock"
        )

    async def _call_tool(self, tool_name: str, args: dict) -> dict:
        """MCPサーバーのツールを呼び出す"""
        # 実際の実装ではUnixソケット/stdio通信
        reader, writer = await asyncio.open_unix_connection(self.socket_path)

        request = json.dumps({
            "jsonrpc": "2.0",
            "method": "tools/call",
            "params": {"name": tool_name, "arguments": args},
            "id": 1
        })
        writer.write(request.encode() + b"\n")
        await writer.drain()

        response = await reader.readline()
        writer.close()
        await writer.wait_closed()

        data = json.loads(response)
        if "error" in data:
            raise MCPError(data["error"]["message"])
        return data["result"]

    async def authenticate(self, agent_id: str, passkey: str) -> AuthResult:
        """認証してセッショントークンを取得"""
        result = await self._call_tool("authenticate", {
            "agent_id": agent_id,
            "passkey": passkey
        })

        if not result.get("success"):
            raise AuthenticationError(result.get("error", "Authentication failed"))

        self._session_token = result["session_token"]
        return AuthResult(
            session_token=result["session_token"],
            expires_in=result["expires_in"],
            agent_name=result.get("agent_name")
        )

    async def get_pending_tasks(self, session_token: str) -> list[TaskInfo]:
        """実行待ちタスクを取得"""
        result = await self._call_tool("get_pending_tasks", {
            "session_token": session_token
        })

        if not result.get("success"):
            error = result.get("error", "")
            if "expired" in error.lower():
                raise SessionExpiredError(error)
            raise MCPError(error)

        return [
            TaskInfo(
                task_id=t["taskId"],
                project_id=t["projectId"],
                title=t["title"],
                description=t["description"],
                priority=t["priority"],
                working_directory=t["workingDirectory"]
            )
            for t in result.get("tasks", [])
        ]

    async def report_execution_start(
        self, session_token: str, task_id: str
    ) -> ExecutionStartResult:
        """実行開始を報告"""
        result = await self._call_tool("report_execution_start", {
            "session_token": session_token,
            "task_id": task_id
        })

        if not result.get("success"):
            raise MCPError(result.get("error", "Failed to report execution start"))

        return ExecutionStartResult(
            execution_id=result["execution_id"],
            started_at=datetime.fromisoformat(result["started_at"].replace("Z", "+00:00"))
        )

    async def report_execution_complete(
        self,
        session_token: str,
        execution_id: str,
        exit_code: int,
        duration_seconds: float,
        log_file_path: str
    ) -> None:
        """実行完了を報告"""
        result = await self._call_tool("report_execution_complete", {
            "session_token": session_token,
            "execution_id": execution_id,
            "exit_code": exit_code,
            "duration_seconds": duration_seconds,
            "log_file_path": log_file_path
        })

        if not result.get("success"):
            raise MCPError(result.get("error", "Failed to report execution complete"))

    async def update_task_status(
        self, task_id: str, status: str
    ) -> None:
        """タスクステータスを更新"""
        result = await self._call_tool("update_task_status", {
            "task_id": task_id,
            "status": status
        })

        if not result.get("success"):
            raise MCPError(result.get("error", "Failed to update task status"))
```

### 3-5-3: Prompt Builder

**Red: テスト**

```python
# tests/test_prompt_builder.py

import pytest
from aiagent_runner.prompt_builder import PromptBuilder
from aiagent_runner.mcp_client import TaskInfo

class TestPromptBuilder:

    @pytest.fixture
    def task(self):
        return TaskInfo(
            task_id="tsk_abc123",
            project_id="prj_xyz789",
            title="Implement login feature",
            description="Create a login form with email and password fields",
            priority="high",
            working_directory="/Users/dev/myproject"
        )

    def test_build_includes_task_identification(self, task):
        """プロンプトにタスク識別情報が含まれる"""
        # Given
        builder = PromptBuilder(agent_id="agt_dev001", agent_name="frontend-dev")

        # When
        prompt = builder.build(task)

        # Then
        assert "tsk_abc123" in prompt
        assert "prj_xyz789" in prompt
        assert "agt_dev001" in prompt

    def test_build_includes_task_details(self, task):
        """プロンプトにタスク詳細が含まれる"""
        # Given
        builder = PromptBuilder(agent_id="agt_dev001")

        # When
        prompt = builder.build(task)

        # Then
        assert "Implement login feature" in prompt
        assert "Create a login form" in prompt
        assert "high" in prompt

    def test_build_includes_working_directory(self, task):
        """プロンプトに作業ディレクトリが含まれる"""
        # Given
        builder = PromptBuilder(agent_id="agt_dev001")

        # When
        prompt = builder.build(task)

        # Then
        assert "/Users/dev/myproject" in prompt

    def test_build_includes_completion_instructions(self, task):
        """プロンプトに完了時の指示が含まれる"""
        # Given
        builder = PromptBuilder(agent_id="agt_dev001")

        # When
        prompt = builder.build(task)

        # Then
        assert "update_task_status" in prompt
        assert '"done"' in prompt or "'done'" in prompt

    def test_build_with_context_includes_context(self, task):
        """コンテキスト情報がある場合はプロンプトに含まれる"""
        # Given
        builder = PromptBuilder(agent_id="agt_dev001")
        context = {
            "progress": "50% complete",
            "blockers": "Need API endpoint clarification"
        }

        # When
        prompt = builder.build(task, context=context)

        # Then
        assert "50% complete" in prompt
        assert "API endpoint clarification" in prompt

    def test_build_with_handoff_includes_handoff_info(self, task):
        """ハンドオフ情報がある場合はプロンプトに含まれる"""
        # Given
        builder = PromptBuilder(agent_id="agt_dev001")
        handoff = {
            "from_agent": "agt_backend",
            "summary": "Backend API is ready",
            "recommendations": "Use /api/v2/auth endpoint"
        }

        # When
        prompt = builder.build(task, handoff=handoff)

        # Then
        assert "Backend API is ready" in prompt
        assert "/api/v2/auth" in prompt
```

**Green: 実装**

```python
# src/aiagent_runner/prompt_builder.py

from typing import Optional
from aiagent_runner.mcp_client import TaskInfo

class PromptBuilder:
    def __init__(self, agent_id: str, agent_name: Optional[str] = None):
        self.agent_id = agent_id
        self.agent_name = agent_name or agent_id

    def build(
        self,
        task: TaskInfo,
        context: Optional[dict] = None,
        handoff: Optional[dict] = None
    ) -> str:
        """タスク情報からプロンプトを構築"""
        sections = [
            self._build_header(task),
            self._build_identification(task),
            self._build_description(task),
            self._build_working_directory(task),
        ]

        if context:
            sections.append(self._build_context(context))

        if handoff:
            sections.append(self._build_handoff(handoff))

        sections.append(self._build_instructions(task))

        return "\n\n".join(sections)

    def _build_header(self, task: TaskInfo) -> str:
        return f"# Task: {task.title}"

    def _build_identification(self, task: TaskInfo) -> str:
        return f"""## Identification
- Task ID: {task.task_id}
- Project ID: {task.project_id}
- Agent ID: {self.agent_id}
- Agent Name: {self.agent_name}
- Priority: {task.priority}"""

    def _build_description(self, task: TaskInfo) -> str:
        return f"""## Description
{task.description}"""

    def _build_working_directory(self, task: TaskInfo) -> str:
        return f"""## Working Directory
Path: {task.working_directory}"""

    def _build_context(self, context: dict) -> str:
        lines = ["## Previous Context"]
        if context.get("progress"):
            lines.append(f"**Progress**: {context['progress']}")
        if context.get("findings"):
            lines.append(f"**Findings**: {context['findings']}")
        if context.get("blockers"):
            lines.append(f"**Blockers**: {context['blockers']}")
        if context.get("next_steps"):
            lines.append(f"**Next Steps**: {context['next_steps']}")
        return "\n".join(lines)

    def _build_handoff(self, handoff: dict) -> str:
        lines = ["## Handoff Information"]
        if handoff.get("from_agent"):
            lines.append(f"**From Agent**: {handoff['from_agent']}")
        if handoff.get("summary"):
            lines.append(f"**Summary**: {handoff['summary']}")
        if handoff.get("recommendations"):
            lines.append(f"**Recommendations**: {handoff['recommendations']}")
        return "\n".join(lines)

    def _build_instructions(self, task: TaskInfo) -> str:
        return f"""## Instructions
1. Complete the task as described above
2. Save your progress regularly using:
   save_context(task_id="{task.task_id}", progress="...", findings="...", next_steps="...")
3. When done, update the task status using:
   update_task_status(task_id="{task.task_id}", status="done")
4. If you need to hand off to another agent, use:
   create_handoff(task_id="{task.task_id}", from_agent_id="{self.agent_id}", summary="...", recommendations="...")"""
```

### 3-5-4: CLI Executor

**Red: テスト**

```python
# tests/test_executor.py

import pytest
from unittest.mock import patch, MagicMock, AsyncMock
from pathlib import Path
from aiagent_runner.executor import CLIExecutor, ExecutionResult

class TestCLIExecutor:

    @pytest.fixture
    def executor(self):
        return CLIExecutor(
            cli_command="claude",
            cli_args=["--dangerously-skip-permissions"]
        )

    def test_execute_runs_cli_with_prompt(self, executor, tmp_path):
        """CLIをプロンプト付きで実行"""
        # Given
        log_file = tmp_path / "test.log"
        prompt = "# Test Task\nDo something"

        with patch("subprocess.run") as mock_run:
            mock_run.return_value = MagicMock(returncode=0)

            # When
            result = executor.execute(
                prompt=prompt,
                working_directory=str(tmp_path),
                log_file=str(log_file)
            )

            # Then
            assert result.exit_code == 0
            mock_run.assert_called_once()
            call_args = mock_run.call_args
            assert "claude" in call_args[0][0]
            assert "--dangerously-skip-permissions" in call_args[0][0]

    def test_execute_captures_output_to_log_file(self, executor, tmp_path):
        """出力をログファイルにキャプチャ"""
        # Given
        log_file = tmp_path / "test.log"

        with patch("subprocess.run") as mock_run:
            mock_run.return_value = MagicMock(returncode=0)

            # When
            executor.execute(
                prompt="test",
                working_directory=str(tmp_path),
                log_file=str(log_file)
            )

            # Then
            call_kwargs = mock_run.call_args[1]
            assert call_kwargs["cwd"] == str(tmp_path)
            # stdout がファイルにリダイレクトされていることを確認

    def test_execute_returns_duration(self, executor, tmp_path):
        """実行時間を返す"""
        # Given
        log_file = tmp_path / "test.log"

        with patch("subprocess.run") as mock_run:
            mock_run.return_value = MagicMock(returncode=0)

            # When
            result = executor.execute(
                prompt="test",
                working_directory=str(tmp_path),
                log_file=str(log_file)
            )

            # Then
            assert result.duration_seconds >= 0

    def test_execute_non_zero_exit_code(self, executor, tmp_path):
        """非ゼロ終了コードを返す"""
        # Given
        log_file = tmp_path / "test.log"

        with patch("subprocess.run") as mock_run:
            mock_run.return_value = MagicMock(returncode=1)

            # When
            result = executor.execute(
                prompt="test",
                working_directory=str(tmp_path),
                log_file=str(log_file)
            )

            # Then
            assert result.exit_code == 1

    def test_execute_with_custom_cli(self, tmp_path):
        """カスタムCLIコマンドを使用"""
        # Given
        executor = CLIExecutor(cli_command="gemini", cli_args=["--no-confirm"])
        log_file = tmp_path / "test.log"

        with patch("subprocess.run") as mock_run:
            mock_run.return_value = MagicMock(returncode=0)

            # When
            executor.execute(
                prompt="test",
                working_directory=str(tmp_path),
                log_file=str(log_file)
            )

            # Then
            call_args = mock_run.call_args[0][0]
            assert "gemini" in call_args
            assert "--no-confirm" in call_args
```

**Green: 実装**

```python
# src/aiagent_runner/executor.py

import subprocess
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Optional

@dataclass
class ExecutionResult:
    exit_code: int
    duration_seconds: float
    log_file: str

class CLIExecutor:
    def __init__(
        self,
        cli_command: str = "claude",
        cli_args: Optional[list[str]] = None
    ):
        self.cli_command = cli_command
        self.cli_args = cli_args or ["--dangerously-skip-permissions"]

    def execute(
        self,
        prompt: str,
        working_directory: str,
        log_file: str
    ) -> ExecutionResult:
        """CLIを実行してプロンプトを処理"""
        Path(log_file).parent.mkdir(parents=True, exist_ok=True)

        cmd = [self.cli_command] + self.cli_args + ["-p", prompt]

        start_time = time.time()

        with open(log_file, "w") as log:
            result = subprocess.run(
                cmd,
                cwd=working_directory,
                stdout=log,
                stderr=subprocess.STDOUT,
                text=True
            )

        end_time = time.time()

        return ExecutionResult(
            exit_code=result.returncode,
            duration_seconds=end_time - start_time,
            log_file=log_file
        )
```

### 3-5-5: Runner Main Loop

**Red: テスト**

```python
# tests/test_runner.py

import pytest
from unittest.mock import AsyncMock, MagicMock, patch
from aiagent_runner.runner import Runner
from aiagent_runner.config import RunnerConfig
from aiagent_runner.mcp_client import TaskInfo, SessionExpiredError

class TestRunner:

    @pytest.fixture
    def config(self):
        return RunnerConfig(
            agent_id="agt_test",
            passkey="secret123",
            polling_interval=1
        )

    @pytest.fixture
    def runner(self, config):
        return Runner(config)

    @pytest.mark.asyncio
    async def test_start_authenticates_on_startup(self, runner):
        """起動時に認証を実行"""
        # Given
        runner.mcp_client.authenticate = AsyncMock(return_value=MagicMock(
            session_token="sess_xxx",
            expires_in=3600
        ))
        runner.mcp_client.get_pending_tasks = AsyncMock(return_value=[])

        # When
        await runner._run_once()

        # Then
        runner.mcp_client.authenticate.assert_called_once_with(
            "agt_test", "secret123"
        )

    @pytest.mark.asyncio
    async def test_run_once_processes_pending_tasks(self, runner):
        """ポーリングでタスクを処理"""
        # Given
        task = TaskInfo(
            task_id="tsk_1",
            project_id="prj_1",
            title="Test",
            description="Do test",
            priority="high",
            working_directory="/tmp"
        )
        runner.mcp_client.authenticate = AsyncMock(return_value=MagicMock(
            session_token="sess_xxx"
        ))
        runner.mcp_client.get_pending_tasks = AsyncMock(return_value=[task])
        runner.mcp_client.report_execution_start = AsyncMock(return_value=MagicMock(
            execution_id="exec_1"
        ))
        runner.mcp_client.report_execution_complete = AsyncMock()
        runner.executor.execute = MagicMock(return_value=MagicMock(
            exit_code=0,
            duration_seconds=10.0,
            log_file="/tmp/log"
        ))

        # When
        await runner._run_once()

        # Then
        runner.executor.execute.assert_called_once()

    @pytest.mark.asyncio
    async def test_run_once_reports_execution_complete(self, runner):
        """タスク実行後に完了報告"""
        # Given
        task = TaskInfo(
            task_id="tsk_1", project_id="prj_1", title="Test",
            description="Do test", priority="high", working_directory="/tmp"
        )
        runner._session_token = "sess_xxx"
        runner.mcp_client.get_pending_tasks = AsyncMock(return_value=[task])
        runner.mcp_client.report_execution_start = AsyncMock(return_value=MagicMock(
            execution_id="exec_1"
        ))
        runner.mcp_client.report_execution_complete = AsyncMock()
        runner.executor.execute = MagicMock(return_value=MagicMock(
            exit_code=0, duration_seconds=10.0, log_file="/tmp/log"
        ))

        # When
        await runner._process_task(task)

        # Then
        runner.mcp_client.report_execution_complete.assert_called_once()

    @pytest.mark.asyncio
    async def test_run_once_reauthenticates_on_session_expired(self, runner):
        """セッション期限切れ時に再認証"""
        # Given
        runner._session_token = "expired_token"
        runner.mcp_client.get_pending_tasks = AsyncMock(
            side_effect=[SessionExpiredError(), []]
        )
        runner.mcp_client.authenticate = AsyncMock(return_value=MagicMock(
            session_token="new_token"
        ))

        # When
        await runner._run_once()

        # Then
        assert runner._session_token == "new_token"
        assert runner.mcp_client.authenticate.call_count == 1
```

**Green: 実装**

```python
# src/aiagent_runner/runner.py

import asyncio
import logging
from datetime import datetime
from pathlib import Path
from typing import Optional

from aiagent_runner.config import RunnerConfig
from aiagent_runner.mcp_client import MCPClient, TaskInfo, SessionExpiredError
from aiagent_runner.executor import CLIExecutor
from aiagent_runner.prompt_builder import PromptBuilder

logger = logging.getLogger(__name__)

class Runner:
    def __init__(self, config: RunnerConfig):
        self.config = config
        self.mcp_client = MCPClient(socket_path=config.mcp_socket_path)
        self.executor = CLIExecutor(
            cli_command=config.cli_command,
            cli_args=config.cli_args
        )
        self.prompt_builder = PromptBuilder(agent_id=config.agent_id)
        self._session_token: Optional[str] = None
        self._running = False

    async def start(self):
        """Runnerを開始"""
        logger.info(f"Starting runner for agent {self.config.agent_id}")
        self._running = True

        while self._running:
            try:
                await self._run_once()
            except Exception as e:
                logger.error(f"Error in run loop: {e}")

            await asyncio.sleep(self.config.polling_interval)

    async def stop(self):
        """Runnerを停止"""
        self._running = False
        logger.info("Runner stopped")

    async def _run_once(self):
        """1回のポーリングサイクル"""
        await self._ensure_authenticated()

        try:
            tasks = await self.mcp_client.get_pending_tasks(self._session_token)
        except SessionExpiredError:
            logger.info("Session expired, re-authenticating")
            self._session_token = None
            await self._ensure_authenticated()
            tasks = await self.mcp_client.get_pending_tasks(self._session_token)

        for task in tasks:
            await self._process_task(task)

    async def _ensure_authenticated(self):
        """認証済みであることを保証"""
        if self._session_token is None:
            result = await self.mcp_client.authenticate(
                self.config.agent_id,
                self.config.passkey
            )
            self._session_token = result.session_token
            self.prompt_builder = PromptBuilder(
                agent_id=self.config.agent_id,
                agent_name=result.agent_name
            )
            logger.info(f"Authenticated as {result.agent_name}")

    async def _process_task(self, task: TaskInfo):
        """タスクを処理"""
        logger.info(f"Processing task: {task.task_id} - {task.title}")

        # 実行開始を報告
        start_result = await self.mcp_client.report_execution_start(
            self._session_token, task.task_id
        )

        # プロンプトを構築
        prompt = self.prompt_builder.build(task)

        # ログファイルパスを決定
        log_dir = self._get_log_directory(task.task_id)
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        log_file = log_dir / f"exec_{timestamp}.log"

        # CLI実行
        working_dir = task.working_directory or self.config.working_directory or "."
        result = self.executor.execute(
            prompt=prompt,
            working_directory=working_dir,
            log_file=str(log_file)
        )

        # 実行完了を報告
        await self.mcp_client.report_execution_complete(
            session_token=self._session_token,
            execution_id=start_result.execution_id,
            exit_code=result.exit_code,
            duration_seconds=result.duration_seconds,
            log_file_path=str(log_file)
        )

        logger.info(
            f"Task {task.task_id} completed with exit code {result.exit_code}"
        )

    def _get_log_directory(self, task_id: str) -> Path:
        """ログディレクトリを取得"""
        if self.config.log_directory:
            base = Path(self.config.log_directory)
        else:
            base = Path.home() / "Library/Application Support/AIAgentPM/logs"
        return base / task_id
```

### 3-5-6: Runner Entry Point

**実装**

```python
# src/aiagent_runner/__main__.py

import asyncio
import argparse
import logging
import signal
from pathlib import Path

from aiagent_runner.config import RunnerConfig
from aiagent_runner.runner import Runner

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s"
)
logger = logging.getLogger(__name__)

def main():
    parser = argparse.ArgumentParser(description="AI Agent PM Runner")
    parser.add_argument(
        "-c", "--config",
        type=Path,
        help="Path to config YAML file"
    )
    parser.add_argument(
        "--agent-id",
        help="Agent ID (overrides config/env)"
    )
    parser.add_argument(
        "--passkey",
        help="Agent passkey (overrides config/env)"
    )
    parser.add_argument(
        "--interval",
        type=int,
        default=5,
        help="Polling interval in seconds"
    )
    args = parser.parse_args()

    # 設定読み込み
    if args.config and args.config.exists():
        config = RunnerConfig.from_yaml(args.config)
    else:
        config = RunnerConfig.from_env()

    # コマンドライン引数で上書き
    if args.agent_id:
        config.agent_id = args.agent_id
    if args.passkey:
        config.passkey = args.passkey
    if args.interval:
        config.polling_interval = args.interval

    # Runner起動
    runner = Runner(config)

    # シグナルハンドラ
    def signal_handler(sig, frame):
        logger.info("Received shutdown signal")
        asyncio.get_event_loop().create_task(runner.stop())

    signal.signal(signal.SIGINT, signal_handler)
    signal.signal(signal.SIGTERM, signal_handler)

    # 実行
    asyncio.run(runner.start())

if __name__ == "__main__":
    main()
```

---

## Phase 3-6: Runner統合テスト + ドキュメント（Week 6）

### 3-6-1: E2Eテスト

**テスト**

```python
# tests/e2e/test_runner_e2e.py

import pytest
import asyncio
from pathlib import Path

class TestRunnerE2E:
    """Runner E2Eテスト（実際のMCPサーバーと通信）"""

    @pytest.fixture
    async def setup_test_data(self, mcp_server):
        """テストデータをセットアップ"""
        # エージェント作成
        await mcp_server.create_agent(
            agent_id="agt_e2e_test",
            name="E2E Test Agent",
            passkey="e2e_secret"
        )
        # プロジェクト・タスク作成
        await mcp_server.create_project(project_id="prj_e2e")
        await mcp_server.create_task(
            task_id="tsk_e2e",
            project_id="prj_e2e",
            title="E2E Test Task",
            assignee_id="agt_e2e_test",
            status="in_progress"
        )
        yield
        # クリーンアップ
        await mcp_server.cleanup()

    @pytest.mark.e2e
    async def test_runner_full_cycle(self, setup_test_data, runner_config):
        """Runner完全サイクルテスト"""
        # Given
        config = RunnerConfig(
            agent_id="agt_e2e_test",
            passkey="e2e_secret",
            polling_interval=1,
            cli_command="echo",  # テスト用にechoを使用
            cli_args=[]
        )
        runner = Runner(config)

        # When
        # 1回のサイクルを実行
        await runner._run_once()

        # Then
        # タスクが処理され、実行ログが作成されたことを確認
        logs = await runner.mcp_client._call_tool("list_execution_logs", {
            "task_id": "tsk_e2e"
        })
        assert len(logs["logs"]) >= 1

    @pytest.mark.e2e
    async def test_runner_session_renewal(self, setup_test_data):
        """セッション更新テスト"""
        # Given
        config = RunnerConfig(
            agent_id="agt_e2e_test",
            passkey="e2e_secret",
            polling_interval=1
        )
        runner = Runner(config)

        # When
        await runner._ensure_authenticated()
        first_token = runner._session_token

        # セッションを無効化（テスト用）
        runner._session_token = "invalid_token"

        # 再度認証が必要な操作を実行
        await runner._run_once()

        # Then
        assert runner._session_token != "invalid_token"
        assert runner._session_token is not None
```

### 3-6-2: ドキュメント

**docs/guide/RUNNER.md**

```markdown
# Runner セットアップガイド

## 概要

Runnerは外部プログラムとしてタスクを実行します。
アプリにバンドルされたサンプル実装を使用するか、独自に実装できます。

## クイックスタート

### 1. 環境変数を設定

```bash
export AGENT_ID="agt_xxx"        # アプリで確認
export AGENT_PASSKEY="secret"    # アプリで発行
```

### 2. Runnerを起動

```bash
# Pythonバージョン
python -m aiagent_runner

# または設定ファイルを使用
python -m aiagent_runner -c runner_config.yaml
```

### 3. アプリでタスクをin_progressに

アプリでタスクのステータスを「in_progress」に変更すると、
Runnerが自動的に検知して実行します。

## 設定ファイル

```yaml
# runner_config.yaml
agent_id: agt_xxx
passkey: your_passkey
polling_interval: 5        # ポーリング間隔（秒）
cli_command: claude        # 使用するCLI
cli_args:
  - "--dangerously-skip-permissions"
working_directory: /path/to/project
log_directory: ~/logs
```

## カスタマイズ

### 別のLLMを使用

```yaml
cli_command: gemini
cli_args:
  - "--project"
  - "my-project"
```

### 独自のRunnerを実装

MCPクライアントライブラリを使用して独自のRunnerを実装できます：

```python
from aiagent_runner.mcp_client import MCPClient

async def my_runner():
    client = MCPClient()
    result = await client.authenticate("my_agent", "my_passkey")
    tasks = await client.get_pending_tasks(result.session_token)
    # 独自の処理...
```

## トラブルシューティング

### 認証エラー

- `AGENT_ID`と`AGENT_PASSKEY`が正しいか確認
- アプリでPasskeyを再生成してみる

### タスクが検出されない

- タスクのステータスが`in_progress`か確認
- タスクの担当者が正しいエージェントか確認
- ポーリング間隔を短くしてみる

### 実行ログが見つからない

- `log_directory`の権限を確認
- ディスク容量を確認
```

---

## テストカバレッジ目標

| レイヤー | カバレッジ目標 | 優先テスト |
|---------|---------------|-----------|
| Domain | 90%+ | エンティティのビジネスロジック |
| UseCase | 85%+ | 正常系 + 主要エラー系 |
| Repository | 80%+ | CRUD + クエリ |
| MCP Tool | 75%+ | 入出力変換 + エラーハンドリング |
| UI | 70%+ | 主要フロー + 状態表示 |
| **Runner** | 80%+ | 認証、タスク処理、エラーハンドリング |

---

## 実装順序（TDD Red-Green-Refactor）

### Week 1: 認証基盤

```
Day 1-2: Domain層
├── [Red]  AgentCredentialTests
├── [Green] AgentCredential実装
├── [Red]  AgentSessionTests
├── [Green] AgentSession実装
└── [Refactor] 共通化

Day 3-4: Repository層
├── [Red]  AgentCredentialRepositoryTests
├── [Green] AgentCredentialRepository実装
├── [Red]  AgentSessionRepositoryTests
├── [Green] AgentSessionRepository実装
├── [Migration] DBスキーマ追加
└── [Refactor] クエリ最適化

Day 5: UseCase + MCP
├── [Red]  AuthenticateUseCaseTests
├── [Green] AuthenticateUseCase実装
├── [Red]  AuthenticateToolTests
├── [Green] AuthenticateTool実装
└── [Integration] 結合テスト
```

### Week 2: タスク取得

```
Day 1-2: Repository拡張
├── [Red]  TaskRepository.findPendingByAssignee Tests
├── [Green] 実装
└── [Refactor] インデックス追加

Day 3-4: UseCase + MCP
├── [Red]  GetPendingTasksUseCaseTests
├── [Green] GetPendingTasksUseCase実装
├── [Red]  GetPendingTasksToolTests
├── [Green] GetPendingTasksTool実装
└── [Integration] 結合テスト

Day 5: ログアウト
├── [Red]  LogoutUseCaseTests
├── [Green] LogoutUseCase実装
├── [Red]  LogoutToolTests
├── [Green] LogoutTool実装
└── [Integration] 結合テスト
```

### Week 3: 実行ログ

```
Day 1-2: Domain + Repository
├── [Red]  ExecutionLogTests
├── [Green] ExecutionLog実装
├── [Red]  ExecutionLogRepositoryTests
├── [Green] ExecutionLogRepository実装
└── [Migration] DBスキーマ追加

Day 3-4: UseCase
├── [Red]  ReportExecutionStartUseCaseTests
├── [Green] 実装
├── [Red]  ReportExecutionCompleteUseCaseTests
├── [Green] 実装
└── [Refactor] 共通化

Day 5: MCP Tools
├── [Red]  ReportExecutionStartToolTests
├── [Green] 実装
├── [Red]  ReportExecutionCompleteToolTests
├── [Green] 実装
└── [Integration] 結合テスト
```

### Week 4: UI統合

```
Day 1-2: エージェント設定
├── [Red]  UITest - Passkey表示
├── [Green] AgentDetailView拡張
├── [Red]  UITest - Passkey再生成
├── [Green] 再生成機能実装
└── [Refactor] UX改善

Day 3-4: 実行ログ画面
├── [Red]  UITest - 実行履歴表示
├── [Green] TaskDetailView拡張
├── [Red]  UITest - ログ内容表示
├── [Green] ログビューア実装
└── [Refactor] パフォーマンス

Day 5: 統合 + ドキュメント
├── E2Eテスト
├── サンプルRunner動作確認
└── ドキュメント更新
```

### Week 5: Runner Core

```
Day 1-2: Config + MCPClient
├── [Red]  RunnerConfigTests
├── [Green] RunnerConfig実装
├── [Red]  MCPClientTests
├── [Green] MCPClient実装
└── [Refactor] エラーハンドリング

Day 3-4: PromptBuilder + CLIExecutor
├── [Red]  PromptBuilderTests
├── [Green] PromptBuilder実装
├── [Red]  CLIExecutorTests
├── [Green] CLIExecutor実装
└── [Refactor] 設定の柔軟性

Day 5: Runner Main Loop
├── [Red]  RunnerTests
├── [Green] Runner実装
├── [Integration] コンポーネント結合
└── [Refactor] ロギング改善
```

### Week 6: Runner統合 + ドキュメント

```
Day 1-2: E2Eテスト
├── [Setup] テスト用MCPサーバー
├── [Red]  E2E認証テスト
├── [Red]  E2Eタスク実行テスト
├── [Green] 問題修正
└── [Refactor] テスト安定化

Day 3-4: パッケージング
├── pyproject.toml設定
├── pip install対応
├── ビルドスクリプト
└── アプリバンドル統合

Day 5: ドキュメント + リリース準備
├── RUNNER.mdガイド作成
├── サンプル設定ファイル
├── トラブルシューティング
└── READMEアップデート
```

---

## 依存関係

```
┌─────────────────────────────────────────────────────────────────────────┐
│  Swift（アプリ + MCPサーバー）                                           │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  AgentCredential ─────────┐                                              │
│                           │                                              │
│  AgentSession ────────────┼──→ AuthenticateUseCase ──→ authenticate Tool │
│                           │                                              │
│  AgentCredentialRepository┘                                              │
│  AgentSessionRepository ──┘                                              │
│                                                                          │
│                                GetPendingTasksUseCase ──→ get_pending_tasks│
│  TaskRepository.findPending ─┘                                           │
│                                                                          │
│  ExecutionLog ─────────────┐                                             │
│                            ├──→ ReportExecutionStartUseCase ──→ Tool     │
│  ExecutionLogRepository ──┘                                              │
│                            └──→ ReportExecutionCompleteUseCase ──→ Tool  │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
                                      │
                                      │ MCP Protocol (JSON-RPC)
                                      │
                                      ▼
┌─────────────────────────────────────────────────────────────────────────┐
│  Python（Runner）                                                        │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  RunnerConfig ──────────────────────────────────────────────┐            │
│                                                             │            │
│  MCPClient ─────────────────────────────────────────────────┼──→ Runner  │
│   ├── authenticate()                                        │            │
│   ├── get_pending_tasks()                                   │            │
│   ├── report_execution_start()                              │            │
│   └── report_execution_complete()                           │            │
│                                                             │            │
│  PromptBuilder ─────────────────────────────────────────────┤            │
│                                                             │            │
│  CLIExecutor ───────────────────────────────────────────────┘            │
│   ├── claude CLI                                                         │
│   └── gemini CLI                                                         │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## リスクと対策

| リスク | 対策 |
|--------|------|
| bcryptライブラリの選定 | Swift Crypto または外部ライブラリ調査（Day 1） |
| セッション管理の複雑さ | シンプルなトークン方式から開始、必要に応じて拡張 |
| ログファイル読み込みのセキュリティ | サンドボックス内パスのみ許可 |
| テストデータの整合性 | setUp/tearDownで確実にクリーンアップ |
| MCP通信の安定性 | 再接続ロジック、タイムアウト処理を実装 |
| Python環境の依存性 | pyproject.tomlで依存関係を固定、venv推奨 |
| CLI実行のタイムアウト | 設定可能なタイムアウト、graceful shutdown対応 |
| 複数Runner同時実行 | 1 Runner = 1 Agent設計、タスクロック機構 |

---

## pyproject.toml

```toml
[project]
name = "aiagent-runner"
version = "0.1.0"
description = "AI Agent PM Runner - Task executor for AI agents"
requires-python = ">=3.11"
dependencies = [
    "pyyaml>=6.0",
    "asyncio>=3.4",
]

[project.optional-dependencies]
dev = [
    "pytest>=7.0",
    "pytest-asyncio>=0.21",
    "pytest-mock>=3.0",
]

[project.scripts]
aiagent-runner = "aiagent_runner.__main__:main"

[build-system]
requires = ["hatchling"]
build-backend = "hatchling.build"
```

---

## 実装進捗

### Phase 3-1: 認証基盤（2026-01-06更新）

| タスク | ステータス | 備考 |
|--------|----------|------|
| 3-1-1: Domain - AgentCredential | ✅ 完了 | SHA256 + salt方式（bcryptではなく） |
| 3-1-2: Domain - AgentSession | ✅ 完了 | 1時間有効期限、sess_プレフィックス |
| 3-1-3: Repository - AgentCredentialRepository | ✅ 完了 | GRDBベース |
| 3-1-3: Repository - AgentSessionRepository | ✅ 完了 | 期限切れ自動フィルタリング |
| 3-1-4: UseCase - 認証 | ✅ 完了 | AuthenticateUseCase等6つ実装 |
| 3-1-5: MCP Tool - authenticate | ✅ 完了 | ToolDefinitions, MCPServer実装 |

**実装済みファイル:**

```
Sources/Domain/ValueObjects/IDs.swift              # AgentCredentialID, AgentSessionID追加
Sources/Domain/Entities/AgentCredential.swift      # 新規作成
Sources/Domain/Entities/AgentSession.swift         # 新規作成
Sources/Domain/Repositories/RepositoryProtocols.swift  # プロトコル追加
Sources/Infrastructure/Database/DatabaseSetup.swift    # v15_authentication追加
Sources/Infrastructure/Repositories/AgentCredentialRepository.swift  # 新規作成
Sources/Infrastructure/Repositories/AgentSessionRepository.swift     # 新規作成
Sources/UseCase/UseCases.swift                     # エラー型追加
Sources/UseCase/AuthenticationUseCases.swift       # 新規作成
Sources/MCPServer/Tools/ToolDefinitions.swift      # authenticate追加
Sources/MCPServer/MCPServer.swift                  # authenticateハンドラ追加
```

**テスト:**
- DomainTests: AgentCredential, AgentSessionテスト ✅
- InfrastructureTests: AgentCredentialRepository, AgentSessionRepositoryテスト ✅
- UseCaseTests: 認証関連UseCase全テスト ✅
- MCPServerTests: AuthenticateToolTests（4テスト）✅

**テスト結果サマリー:**
- 全295テスト実行
- 2件のViewInspector関連失敗（認証実装とは無関係）
- 認証関連テストは全て合格

**変更点:**
- bcryptの代わりにSHA256 + salt方式を採用（Swift標準CryptoKit使用）
- ステートレス設計に対応するためMCPServerTestsを更新
- ツール数: 15 → 16（authenticate追加）

---

## Phase 3-2 実装完了ノート

**実装日:** 2026-01-06
**ステータス:** ✅ 完了

### 実装した機能

1. **TaskRepositoryProtocol拡張**
   - `findPendingByAssignee(_ agentId: AgentID) throws -> [Task]` を追加
   - in_progressステータスかつ指定エージェントにアサインされたタスクを取得

2. **TaskRepository実装**
   - GRDBを使用したfindPendingByAssignee実装
   - 3件のテスト追加・パス

3. **GetPendingTasksUseCase**
   - 外部Runnerが作業継続のため現在進行中のタスクを取得するUseCase
   - 2件のテスト追加・パス

4. **get_pending_tasks MCP Tool**
   - ToolDefinitions: ツール定義追加
   - MCPServer: ハンドラー実装
   - 2件のテスト追加・パス

### テスト結果

```
302 tests, 2 failures (ViewInspector関連、Phase 3-2とは無関係)
- testGetPendingTasksToolDefinition: ✅
- testGetPendingTasksToolInAllTools: ✅
- testGetPendingTasksUseCase: ✅
- testGetPendingTasksUseCaseExcludesOtherAgents: ✅
- testTaskRepositoryFindPendingByAssignee: ✅
- testTaskRepositoryFindPendingByAssigneeExcludesOtherAgents: ✅
- testTaskRepositoryFindPendingByAssigneeExcludesUnassigned: ✅
```

**変更点:**
- ツール数: 16 → 17（get_pending_tasks追加）

---

## 変更履歴

| 日付 | バージョン | 変更内容 |
|------|-----------|----------|
| 2026-01-06 | 1.0.0 | 初版作成 |
| 2026-01-06 | 1.1.0 | Phase 3-5, 3-6 Runner実装を追加 |
| 2026-01-06 | 1.2.0 | Phase 3-1 認証基盤実装完了（MCP Tool除く） |
| 2026-01-06 | 1.3.0 | Phase 3-1 完了: authenticate MCP Tool実装 |
| 2026-01-06 | 1.4.0 | Phase 3-2 完了: get_pending_tasks MCP Tool実装 |
| 2026-01-06 | 1.5.0 | Phase 3-3 完了: 実行ログ（ExecutionLog）実装 |

---

## Phase 3-3 実装完了ノート

**実装日:** 2026-01-06
**ステータス:** ✅ 完了

### 実装した機能

1. **Domain層 - ExecutionLog エンティティ**
   - ExecutionLogID: 実行ログの識別子
   - ExecutionStatus: running, completed, failed
   - ExecutionLog: タスク実行のログを記録するエンティティ
   - 6件のテスト追加・パス

2. **Domain層 - ExecutionLogRepositoryProtocol**
   - findById, findByTaskId, findByAgentId, findRunning, save, delete メソッド

3. **Infrastructure層 - ExecutionLogRepository**
   - GRDBを使用した実装
   - v16マイグレーション: execution_logsテーブル追加
   - インデックス: task_id, agent_id, status
   - 8件のテスト追加・パス

4. **UseCase層 - ExecutionLog UseCases**
   - RecordExecutionStartUseCase: 実行開始を記録
   - RecordExecutionCompleteUseCase: 実行完了を記録
   - GetExecutionLogsUseCase: 実行ログを取得
   - UseCaseError拡張: executionLogNotFound, invalidStateTransition
   - 10件のテスト追加・パス

5. **MCP層 - 実行ログツール**
   - report_execution_start: タスク実行開始を報告
   - report_execution_complete: タスク実行完了を報告
   - ToolDefinitions: 2つのツール定義追加
   - MCPServer: ハンドラー実装
   - 5件のテスト追加・パス

### テスト結果

```
329 tests, 2 failures (ViewInspector関連、Phase 3-3とは無関係)

Domain (87 tests):
- testExecutionLogInitialization: ✅
- testExecutionLogStartsWithRunningStatus: ✅
- testExecutionLogCompleteWithSuccessStatus: ✅
- testExecutionLogCompleteWithFailedStatus: ✅
- testExecutionLogStatusRawValues: ✅
- testExecutionLogStatusCaseIterable: ✅

Infrastructure (79 tests):
- testExecutionLogRepositorySave: ✅
- testExecutionLogRepositoryFindById: ✅
- testExecutionLogRepositoryFindByTaskId: ✅
- testExecutionLogRepositoryFindByAgentId: ✅
- testExecutionLogRepositoryFindRunning: ✅
- testExecutionLogRepositoryUpdate: ✅
- testExecutionLogRepositoryDelete: ✅
- testExecutionLogRepositoryNotFound: ✅

UseCase (90 tests):
- testRecordExecutionStartUseCaseSuccess: ✅
- testRecordExecutionStartUseCaseTaskNotFound: ✅
- testRecordExecutionStartUseCaseAgentNotFound: ✅
- testRecordExecutionCompleteUseCaseSuccess: ✅
- testRecordExecutionCompleteUseCaseFailedStatus: ✅
- testRecordExecutionCompleteUseCaseNotFound: ✅
- testRecordExecutionCompleteUseCaseAlreadyCompleted: ✅
- testGetExecutionLogsByTaskId: ✅
- testGetExecutionLogsByAgentId: ✅
- testGetRunningExecutionLogs: ✅

MCPServer (42 tests):
- testReportExecutionStartToolDefinition: ✅
- testReportExecutionCompleteToolDefinition: ✅
- testExecutionLogToolsInAllTools: ✅
- testToolCount: ✅ (19 tools)
- testPRDComplianceSummary: ✅ (19 tools)
```

### 変更点

- ツール数: 17 → 19（report_execution_start, report_execution_complete追加）

### 実装済みファイル

```
Sources/Domain/ValueObjects/IDs.swift              # ExecutionLogID追加
Sources/Domain/Entities/ExecutionLog.swift         # 新規作成
Sources/Domain/Repositories/RepositoryProtocols.swift  # ExecutionLogRepositoryProtocol追加
Sources/Infrastructure/Database/DatabaseSetup.swift    # v16_execution_logs追加
Sources/Infrastructure/Repositories/ExecutionLogRepository.swift  # 新規作成
Sources/UseCase/UseCases.swift                     # エラー型追加
Sources/UseCase/ExecutionLogUseCases.swift         # 新規作成
Sources/MCPServer/Tools/ToolDefinitions.swift      # report_execution_start/complete追加
Sources/MCPServer/MCPServer.swift                  # ハンドラー追加
```

### Phase 3-3 進捗サマリー

| タスク | ステータス | 備考 |
|--------|----------|------|
| 3-3-1: Domain - ExecutionLog | ✅ 完了 | ExecutionStatus enum付き |
| 3-3-2: Repository - ExecutionLogRepository | ✅ 完了 | GRDB実装、マイグレーション追加 |
| 3-3-3: UseCase - ExecutionLog UseCases | ✅ 完了 | Start/Complete/Get の3 UseCase |
| 3-3-4: MCP Tool - report_execution_start/complete | ✅ 完了 | ToolDefinitions, MCPServer実装 |
