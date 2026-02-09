// Tests/UseCaseTests/ExecutionLogUseCaseTests.swift
// Execution log, credential, session validation, and task completion UseCase tests
// extracted from UseCaseTests.swift
// 参照: Phase 3-1 (Authentication), Phase 3-3 (Execution Logs)

import XCTest
@testable import UseCase
@testable import Domain

// MARK: - Execution Log & Auth Session UseCase Tests

final class ExecutionLogUseCaseTests: XCTestCase {

    var projectRepo: MockProjectRepository!
    var agentRepo: MockAgentRepository!
    var taskRepo: MockTaskRepository!
    var sessionRepo: MockSessionRepository!
    var eventRepo: MockEventRepository!
    var agentCredentialRepo: MockAgentCredentialRepository!
    var agentSessionRepo: MockAgentSessionRepository!
    var executionLogRepo: MockExecutionLogRepository!

    override func setUp() {
        projectRepo = MockProjectRepository()
        agentRepo = MockAgentRepository()
        taskRepo = MockTaskRepository()
        sessionRepo = MockSessionRepository()
        eventRepo = MockEventRepository()
        agentCredentialRepo = MockAgentCredentialRepository()
        agentSessionRepo = MockAgentSessionRepository()
        executionLogRepo = MockExecutionLogRepository()
    }

    // MARK: - ValidateSessionUseCase Tests

    func testValidateSessionUseCaseValid() throws {
        // 有効なセッションでエージェントIDを返す
        let project = Project(id: ProjectID.generate(), name: "TestProject")
        projectRepo.projects[project.id] = project
        let agent = Agent(id: AgentID.generate(), name: "TestAgent", role: "Developer")
        agentRepo.agents[agent.id] = agent

        let session = AgentSession(agentId: agent.id, projectId: project.id)
        agentSessionRepo.sessions[session.id] = session

        let useCase = ValidateSessionUseCase(
            sessionRepository: agentSessionRepo,
            agentRepository: agentRepo
        )

        let result = try useCase.execute(sessionToken: session.token)

        XCTAssertEqual(result, agent.id)
    }

    func testValidateSessionUseCaseExpired() throws {
        // 期限切れセッションでnilを返す
        let project = Project(id: ProjectID.generate(), name: "TestProject")
        projectRepo.projects[project.id] = project
        let agent = Agent(id: AgentID.generate(), name: "TestAgent", role: "Developer")
        agentRepo.agents[agent.id] = agent

        let expiredSession = AgentSession(
            agentId: agent.id,
            projectId: project.id,
            expiresAt: Date().addingTimeInterval(-100)
        )
        agentSessionRepo.sessions[expiredSession.id] = expiredSession

        let useCase = ValidateSessionUseCase(
            sessionRepository: agentSessionRepo,
            agentRepository: agentRepo
        )

        let result = try useCase.execute(sessionToken: expiredSession.token)

        XCTAssertNil(result)
    }

    func testValidateSessionUseCaseInvalidToken() throws {
        // 無効なトークンでnilを返す
        let useCase = ValidateSessionUseCase(
            sessionRepository: agentSessionRepo,
            agentRepository: agentRepo
        )

        let result = try useCase.execute(sessionToken: "invalid_token")

        XCTAssertNil(result)
    }

    // MARK: - LogoutUseCase Tests

    func testLogoutUseCaseSuccess() throws {
        // セッションを削除してログアウト
        let project = Project(id: ProjectID.generate(), name: "TestProject")
        projectRepo.projects[project.id] = project
        let agent = Agent(id: AgentID.generate(), name: "TestAgent", role: "Developer")
        agentRepo.agents[agent.id] = agent

        let session = AgentSession(agentId: agent.id, projectId: project.id)
        agentSessionRepo.sessions[session.id] = session

        let useCase = LogoutUseCase(sessionRepository: agentSessionRepo)

        let result = try useCase.execute(sessionToken: session.token)

        XCTAssertTrue(result)
        XCTAssertTrue(agentSessionRepo.sessions.isEmpty)
    }

    func testLogoutUseCaseInvalidToken() throws {
        // 無効なトークンでfalseを返す
        let useCase = LogoutUseCase(sessionRepository: agentSessionRepo)

        let result = try useCase.execute(sessionToken: "invalid_token")

        XCTAssertFalse(result)
    }

    // MARK: - CreateCredentialUseCase Tests

    func testCreateCredentialUseCaseSuccess() throws {
        // 認証情報を作成
        let agent = Agent(id: AgentID.generate(), name: "TestAgent", role: "Developer")
        agentRepo.agents[agent.id] = agent

        let useCase = CreateCredentialUseCase(
            credentialRepository: agentCredentialRepo,
            agentRepository: agentRepo
        )

        let credential = try useCase.execute(agentId: agent.id, passkey: "newsecret123")

        XCTAssertEqual(credential.agentId, agent.id)
        XCTAssertEqual(agentCredentialRepo.credentials.count, 1)
    }

    func testCreateCredentialUseCaseShortPasskey() throws {
        // 短すぎるパスキーでエラー
        let agent = Agent(id: AgentID.generate(), name: "TestAgent", role: "Developer")
        agentRepo.agents[agent.id] = agent

        let useCase = CreateCredentialUseCase(
            credentialRepository: agentCredentialRepo,
            agentRepository: agentRepo
        )

        XCTAssertThrowsError(try useCase.execute(agentId: agent.id, passkey: "short")) { error in
            if case UseCaseError.validationFailed = error {
                // Expected
            } else {
                XCTFail("Expected validationFailed error")
            }
        }
    }

    func testCreateCredentialUseCaseReplacesExisting() throws {
        // 既存の認証情報を置き換え
        let agent = Agent(id: AgentID.generate(), name: "TestAgent", role: "Developer")
        agentRepo.agents[agent.id] = agent

        let oldCredential = AgentCredential(agentId: agent.id, rawPasskey: "oldsecret123")
        agentCredentialRepo.credentials[oldCredential.id] = oldCredential

        let useCase = CreateCredentialUseCase(
            credentialRepository: agentCredentialRepo,
            agentRepository: agentRepo
        )

        let newCredential = try useCase.execute(agentId: agent.id, passkey: "newsecret123")

        XCTAssertEqual(agentCredentialRepo.credentials.count, 1)
        XCTAssertNotEqual(newCredential.id, oldCredential.id)
    }

    // MARK: - CleanupExpiredSessionsUseCase Tests

    func testCleanupExpiredSessionsUseCase() throws {
        // 期限切れセッションをクリーンアップ
        let project = Project(id: ProjectID.generate(), name: "TestProject")
        projectRepo.projects[project.id] = project
        let agent = Agent(id: AgentID.generate(), name: "TestAgent", role: "Developer")
        agentRepo.agents[agent.id] = agent

        let expiredSession = AgentSession(
            agentId: agent.id,
            projectId: project.id,
            expiresAt: Date().addingTimeInterval(-100)
        )
        let validSession = AgentSession(agentId: agent.id, projectId: project.id)
        agentSessionRepo.sessions[expiredSession.id] = expiredSession
        agentSessionRepo.sessions[validSession.id] = validSession

        let useCase = CleanupExpiredSessionsUseCase(sessionRepository: agentSessionRepo)

        try useCase.execute()

        XCTAssertEqual(agentSessionRepo.sessions.count, 1)
        XCTAssertNotNil(agentSessionRepo.sessions[validSession.id])
    }

    // MARK: - RecordExecutionStartUseCase Tests (Phase 3-3)

    func testRecordExecutionStartUseCaseSuccess() throws {
        // 正常系：実行開始を記録
        let project = Project(id: ProjectID.generate(), name: "TestProject")
        projectRepo.projects[project.id] = project

        let agent = Agent(id: AgentID.generate(), name: "TestAgent", role: "Developer")
        agentRepo.agents[agent.id] = agent

        let task = Task(id: TaskID.generate(), projectId: project.id, title: "Test Task", status: .inProgress)
        taskRepo.tasks[task.id] = task

        let useCase = RecordExecutionStartUseCase(
            executionLogRepository: executionLogRepo,
            taskRepository: taskRepo,
            agentRepository: agentRepo
        )

        let log = try useCase.execute(taskId: task.id, agentId: agent.id)

        XCTAssertEqual(log.taskId, task.id)
        XCTAssertEqual(log.agentId, agent.id)
        XCTAssertEqual(log.status, .running)
        XCTAssertNil(log.completedAt)
        XCTAssertNotNil(executionLogRepo.logs[log.id])
    }

    func testRecordExecutionStartUseCaseTaskNotFound() throws {
        // タスクが見つからない場合
        let agent = Agent(id: AgentID.generate(), name: "TestAgent", role: "Developer")
        agentRepo.agents[agent.id] = agent

        let useCase = RecordExecutionStartUseCase(
            executionLogRepository: executionLogRepo,
            taskRepository: taskRepo,
            agentRepository: agentRepo
        )

        let nonExistentTaskId = TaskID.generate()

        XCTAssertThrowsError(try useCase.execute(taskId: nonExistentTaskId, agentId: agent.id)) { error in
            if case UseCaseError.taskNotFound = error {
                // Expected
            } else {
                XCTFail("Expected taskNotFound error")
            }
        }
    }

    func testRecordExecutionStartUseCaseAgentNotFound() throws {
        // エージェントが見つからない場合
        let project = Project(id: ProjectID.generate(), name: "TestProject")
        projectRepo.projects[project.id] = project

        let task = Task(id: TaskID.generate(), projectId: project.id, title: "Test Task", status: .inProgress)
        taskRepo.tasks[task.id] = task

        let useCase = RecordExecutionStartUseCase(
            executionLogRepository: executionLogRepo,
            taskRepository: taskRepo,
            agentRepository: agentRepo
        )

        let nonExistentAgentId = AgentID.generate()

        XCTAssertThrowsError(try useCase.execute(taskId: task.id, agentId: nonExistentAgentId)) { error in
            if case UseCaseError.agentNotFound = error {
                // Expected
            } else {
                XCTFail("Expected agentNotFound error")
            }
        }
    }

    // MARK: - RecordExecutionCompleteUseCase Tests (Phase 3-3)

    func testRecordExecutionCompleteUseCaseSuccess() throws {
        // 正常系：実行完了を記録（exitCode=0で完了）
        let project = Project(id: ProjectID.generate(), name: "TestProject")
        projectRepo.projects[project.id] = project

        let agent = Agent(id: AgentID.generate(), name: "TestAgent", role: "Developer")
        agentRepo.agents[agent.id] = agent

        let task = Task(id: TaskID.generate(), projectId: project.id, title: "Test Task", status: .inProgress)
        taskRepo.tasks[task.id] = task

        let log = ExecutionLog(taskId: task.id, agentId: agent.id)
        executionLogRepo.logs[log.id] = log

        let useCase = RecordExecutionCompleteUseCase(executionLogRepository: executionLogRepo)

        let updatedLog = try useCase.execute(
            executionLogId: log.id,
            exitCode: 0,
            durationSeconds: 120.5,
            logFilePath: "/tmp/log.txt"
        )

        XCTAssertEqual(updatedLog.status, .completed)
        XCTAssertEqual(updatedLog.exitCode, 0)
        XCTAssertEqual(updatedLog.durationSeconds, 120.5)
        XCTAssertEqual(updatedLog.logFilePath, "/tmp/log.txt")
        XCTAssertNotNil(updatedLog.completedAt)
    }

    func testRecordExecutionCompleteUseCaseFailedStatus() throws {
        // 正常系：実行失敗を記録（exitCode≠0で失敗）
        let project = Project(id: ProjectID.generate(), name: "TestProject")
        projectRepo.projects[project.id] = project

        let agent = Agent(id: AgentID.generate(), name: "TestAgent", role: "Developer")
        agentRepo.agents[agent.id] = agent

        let task = Task(id: TaskID.generate(), projectId: project.id, title: "Test Task", status: .inProgress)
        taskRepo.tasks[task.id] = task

        let log = ExecutionLog(taskId: task.id, agentId: agent.id)
        executionLogRepo.logs[log.id] = log

        let useCase = RecordExecutionCompleteUseCase(executionLogRepository: executionLogRepo)

        let updatedLog = try useCase.execute(
            executionLogId: log.id,
            exitCode: 1,
            durationSeconds: 45.0,
            logFilePath: "/tmp/error.log",
            errorMessage: "Command failed"
        )

        XCTAssertEqual(updatedLog.status, .failed)
        XCTAssertEqual(updatedLog.exitCode, 1)
        XCTAssertEqual(updatedLog.errorMessage, "Command failed")
    }

    func testRecordExecutionCompleteUseCaseNotFound() throws {
        // 実行ログが見つからない場合
        let useCase = RecordExecutionCompleteUseCase(executionLogRepository: executionLogRepo)

        let nonExistentId = ExecutionLogID.generate()

        XCTAssertThrowsError(try useCase.execute(
            executionLogId: nonExistentId,
            exitCode: 0,
            durationSeconds: 10.0
        )) { error in
            if case UseCaseError.executionLogNotFound = error {
                // Expected
            } else {
                XCTFail("Expected executionLogNotFound error")
            }
        }
    }

    func testRecordExecutionCompleteUseCaseAlreadyCompleted() throws {
        // 既に完了している実行ログに対するエラー
        let project = Project(id: ProjectID.generate(), name: "TestProject")
        projectRepo.projects[project.id] = project

        let agent = Agent(id: AgentID.generate(), name: "TestAgent", role: "Developer")
        agentRepo.agents[agent.id] = agent

        let task = Task(id: TaskID.generate(), projectId: project.id, title: "Test Task", status: .inProgress)
        taskRepo.tasks[task.id] = task

        var log = ExecutionLog(taskId: task.id, agentId: agent.id)
        log.complete(exitCode: 0, durationSeconds: 60.0)  // 既に完了
        executionLogRepo.logs[log.id] = log

        let useCase = RecordExecutionCompleteUseCase(executionLogRepository: executionLogRepo)

        XCTAssertThrowsError(try useCase.execute(
            executionLogId: log.id,
            exitCode: 0,
            durationSeconds: 10.0
        )) { error in
            if case UseCaseError.invalidStateTransition = error {
                // Expected
            } else {
                XCTFail("Expected invalidStateTransition error")
            }
        }
    }

    // MARK: - GetExecutionLogsUseCase Tests (Phase 3-3)

    func testGetExecutionLogsByTaskId() throws {
        // タスクIDで実行ログを取得
        let project = Project(id: ProjectID.generate(), name: "TestProject")
        projectRepo.projects[project.id] = project

        let agent = Agent(id: AgentID.generate(), name: "TestAgent", role: "Developer")
        agentRepo.agents[agent.id] = agent

        let task = Task(id: TaskID.generate(), projectId: project.id, title: "Test Task")
        taskRepo.tasks[task.id] = task

        let log1 = ExecutionLog(taskId: task.id, agentId: agent.id)
        let log2 = ExecutionLog(taskId: task.id, agentId: agent.id)
        executionLogRepo.logs[log1.id] = log1
        executionLogRepo.logs[log2.id] = log2

        let useCase = GetExecutionLogsUseCase(executionLogRepository: executionLogRepo)

        let logs = try useCase.executeByTaskId(task.id)

        XCTAssertEqual(logs.count, 2)
    }

    func testGetExecutionLogsByAgentId() throws {
        // エージェントIDで実行ログを取得
        let project = Project(id: ProjectID.generate(), name: "TestProject")
        projectRepo.projects[project.id] = project

        let agent = Agent(id: AgentID.generate(), name: "TestAgent", role: "Developer")
        agentRepo.agents[agent.id] = agent

        let task1 = Task(id: TaskID.generate(), projectId: project.id, title: "Task 1")
        let task2 = Task(id: TaskID.generate(), projectId: project.id, title: "Task 2")
        taskRepo.tasks[task1.id] = task1
        taskRepo.tasks[task2.id] = task2

        let log1 = ExecutionLog(taskId: task1.id, agentId: agent.id)
        let log2 = ExecutionLog(taskId: task2.id, agentId: agent.id)
        executionLogRepo.logs[log1.id] = log1
        executionLogRepo.logs[log2.id] = log2

        let useCase = GetExecutionLogsUseCase(executionLogRepository: executionLogRepo)

        let logs = try useCase.executeByAgentId(agent.id)

        XCTAssertEqual(logs.count, 2)
    }

    func testGetRunningExecutionLogs() throws {
        // 実行中のログを取得
        let project = Project(id: ProjectID.generate(), name: "TestProject")
        projectRepo.projects[project.id] = project

        let agent = Agent(id: AgentID.generate(), name: "TestAgent", role: "Developer")
        agentRepo.agents[agent.id] = agent

        let task = Task(id: TaskID.generate(), projectId: project.id, title: "Test Task")
        taskRepo.tasks[task.id] = task

        let runningLog = ExecutionLog(taskId: task.id, agentId: agent.id)
        var completedLog = ExecutionLog(taskId: task.id, agentId: agent.id)
        completedLog.complete(exitCode: 0, durationSeconds: 60.0)

        executionLogRepo.logs[runningLog.id] = runningLog
        executionLogRepo.logs[completedLog.id] = completedLog

        let useCase = GetExecutionLogsUseCase(executionLogRepository: executionLogRepo)

        let logs = try useCase.executeRunning(agentId: agent.id)

        XCTAssertEqual(logs.count, 1)
        XCTAssertEqual(logs.first?.status, .running)
    }

    // MARK: - Report Completed/Blocked Tests (セッション管理)

    func testReportCompletedEndsSession() throws {
        // reportCompleted相当の処理でセッションが終了されること
        let project = Project(id: ProjectID.generate(), name: "TestProject")
        projectRepo.projects[project.id] = project

        let agent = Agent(id: AgentID.generate(), name: "TestAgent", role: "Worker")
        agentRepo.agents[agent.id] = agent

        // タスク（in_progress状態）
        var task = Task(
            id: TaskID.generate(),
            projectId: project.id,
            title: "Test Task",
            status: .inProgress
        )
        task.assigneeId = agent.id
        taskRepo.tasks[task.id] = task

        // アクティブセッション
        let session = Session(
            id: SessionID.generate(),
            projectId: project.id,
            agentId: agent.id
        )
        sessionRepo.sessions[session.id] = session

        // CompleteTaskWithSessionCleanupUseCaseでタスク完了とセッション終了を同時に行う
        let useCase = CompleteTaskWithSessionCleanupUseCase(
            taskRepository: taskRepo,
            sessionRepository: sessionRepo,
            eventRepository: eventRepo
        )

        let result = try useCase.execute(taskId: task.id, agentId: agent.id, result: .success)

        // タスクがdoneになっていること
        XCTAssertEqual(result.task.status, .done)

        // セッションが終了していること
        let remainingSession = try sessionRepo.findActive(agentId: agent.id)
        XCTAssertNil(remainingSession, "タスク完了後、アクティブセッションは残らないはず")
    }

    func testReportBlockedEndsSession() throws {
        // blocked報告でセッションが終了されること
        let project = Project(id: ProjectID.generate(), name: "TestProject")
        projectRepo.projects[project.id] = project

        let agent = Agent(id: AgentID.generate(), name: "TestAgent", role: "Worker")
        agentRepo.agents[agent.id] = agent

        var task = Task(
            id: TaskID.generate(),
            projectId: project.id,
            title: "Test Task",
            status: .inProgress
        )
        task.assigneeId = agent.id
        taskRepo.tasks[task.id] = task

        let session = Session(
            id: SessionID.generate(),
            projectId: project.id,
            agentId: agent.id
        )
        sessionRepo.sessions[session.id] = session

        let useCase = CompleteTaskWithSessionCleanupUseCase(
            taskRepository: taskRepo,
            sessionRepository: sessionRepo,
            eventRepository: eventRepo
        )

        let result = try useCase.execute(taskId: task.id, agentId: agent.id, result: .blocked)

        // タスクがblockedになっていること
        XCTAssertEqual(result.task.status, .blocked)

        // セッションが終了していること
        let remainingSession = try sessionRepo.findActive(agentId: agent.id)
        XCTAssertNil(remainingSession, "タスクblocked後、アクティブセッションは残らないはず")
    }
}
