// Tests/UseCaseTests/UseCaseTests.swift
// PRD仕様に基づくUseCase層テスト - コアエンティティ（Error, Project, Agent）
// 参照: docs/prd/TASK_MANAGEMENT.md, AGENT_CONCEPT.md, STATE_HISTORY.md
//
// NOTE: This file has been split into domain-specific test files.
// See: MockRepositories.swift, TaskUseCaseTests.swift, SessionUseCaseTests.swift,
//      WorkflowTemplateUseCaseTests.swift, AuditUseCaseTests.swift, ExecutionLogUseCaseTests.swift

import XCTest
@testable import UseCase
@testable import Domain

// MARK: - Core UseCase Tests (Error, Project, Agent)

final class UseCaseTests: XCTestCase {

    var projectRepo: MockProjectRepository!
    var agentRepo: MockAgentRepository!
    var agentSessionRepo: MockAgentSessionRepository!

    override func setUp() {
        projectRepo = MockProjectRepository()
        agentRepo = MockAgentRepository()
        agentSessionRepo = MockAgentSessionRepository()
    }

    // MARK: - Error Description Tests

    func testUseCaseErrorDescriptions() {
        let taskError = UseCaseError.taskNotFound(TaskID(value: "tsk_test"))
        XCTAssertTrue(taskError.localizedDescription.contains("tsk_test"))

        let transitionError = UseCaseError.invalidStatusTransition(from: .done, to: .inProgress)
        XCTAssertTrue(transitionError.localizedDescription.contains("done"))
    }

    // MARK: - Project UseCase Tests (PRD: 01_project_list.md)

    func testCreateProjectUseCaseSuccess() throws {
        // PRD: プロジェクトの作成
        let useCase = CreateProjectUseCase(projectRepository: projectRepo)

        let project = try useCase.execute(name: "ECサイト開発", description: "EC site development")

        XCTAssertEqual(project.name, "ECサイト開発")
        XCTAssertEqual(project.description, "EC site development")
        XCTAssertEqual(project.status, .active)
        XCTAssertNotNil(projectRepo.projects[project.id])
    }

    func testCreateProjectUseCaseEmptyNameFails() throws {
        // PRD: 名前は必須
        let useCase = CreateProjectUseCase(projectRepository: projectRepo)

        XCTAssertThrowsError(try useCase.execute(name: "")) { error in
            XCTAssertTrue(error is UseCaseError)
            if case UseCaseError.validationFailed = error {
                // Expected
            } else {
                XCTFail("Expected validationFailed error")
            }
        }
    }

    func testGetProjectsUseCase() throws {
        // PRD: プロジェクト一覧取得
        let project1 = Project(id: ProjectID.generate(), name: "Project 1")
        let project2 = Project(id: ProjectID.generate(), name: "Project 2")
        projectRepo.projects[project1.id] = project1
        projectRepo.projects[project2.id] = project2

        let useCase = GetProjectsUseCase(projectRepository: projectRepo)
        let projects = try useCase.execute()

        XCTAssertEqual(projects.count, 2)
    }

    // MARK: - Agent UseCase Tests (要件: エージェントはプロジェクト非依存)

    func testCreateAgentUseCaseSuccess() throws {
        // 要件: エージェントの作成（プロジェクト非依存）
        let useCase = CreateAgentUseCase(agentRepository: agentRepo)

        let agent = try useCase.execute(
            name: "frontend-dev",
            role: "フロントエンド開発",
            roleType: .developer,
            type: .ai
        )

        XCTAssertEqual(agent.name, "frontend-dev")
        XCTAssertEqual(agent.type, AgentType.ai)
        XCTAssertEqual(agent.roleType, AgentRoleType.developer)
        XCTAssertEqual(agent.status, AgentStatus.active)
    }

    func testCreateAgentUseCaseEmptyNameFails() throws {
        // 要件: 名前は必須
        let useCase = CreateAgentUseCase(agentRepository: agentRepo)

        XCTAssertThrowsError(try useCase.execute(
            name: "",
            role: "Role"
        )) { error in
            if case UseCaseError.validationFailed = error {
                // Expected
            } else {
                XCTFail("Expected validationFailed error")
            }
        }
    }

    func testGetAgentProfileUseCase() throws {
        // PRD: エージェントプロファイル取得（get_my_profile）
        let agent = Agent(
            id: AgentID.generate(),
            name: "test-agent",
            role: "Tester"
        )
        agentRepo.agents[agent.id] = agent

        let useCase = GetAgentProfileUseCase(agentRepository: agentRepo)
        let profile = try useCase.execute(agentId: agent.id)

        XCTAssertEqual(profile.name, "test-agent")
    }

    func testGetAgentProfileUseCaseNotFound() throws {
        // PRD: 存在しないエージェントはエラー
        let useCase = GetAgentProfileUseCase(agentRepository: agentRepo)

        XCTAssertThrowsError(try useCase.execute(agentId: AgentID.generate())) { error in
            if case UseCaseError.agentNotFound = error {
                // Expected
            } else {
                XCTFail("Expected agentNotFound error")
            }
        }
    }

    // MARK: - Feature 14: Project Pause Tests

    /// PauseProjectUseCase: プロジェクトを一時停止する
    func testPauseProjectUseCaseSuccess() throws {
        // 前提: activeなプロジェクト
        let project = Project(id: ProjectID.generate(), name: "TestProject", status: .active)
        projectRepo.projects[project.id] = project

        // アクティブセッション（有効期限を短縮される対象）
        let agentId = AgentID.generate()
        let originalExpiry = Date().addingTimeInterval(3600) // 1時間後
        let session = AgentSession(
            agentId: agentId,
            projectId: project.id,
            expiresAt: originalExpiry
        )
        agentSessionRepo.sessions[session.id] = session

        // 実行
        let useCase = PauseProjectUseCase(
            projectRepository: projectRepo,
            agentSessionRepository: agentSessionRepo
        )
        let result = try useCase.execute(projectId: project.id)

        // 検証: プロジェクトがpausedになっている
        XCTAssertEqual(result.status, .paused, "プロジェクトがpausedになるべき")

        // 検証: セッションの有効期限が短縮されている（5分以内）
        let updatedSession = try agentSessionRepo.findById(session.id)
        XCTAssertNotNil(updatedSession)
        let gracePeriod: TimeInterval = 5 * 60 // 5分
        XCTAssertLessThanOrEqual(
            updatedSession!.expiresAt.timeIntervalSinceNow,
            gracePeriod,
            "セッション有効期限が5分以内に短縮されるべき"
        )
    }

    /// PauseProjectUseCase: 既にpausedのプロジェクトは何もしない
    func testPauseProjectUseCaseAlreadyPaused() throws {
        let project = Project(id: ProjectID.generate(), name: "TestProject", status: .paused)
        projectRepo.projects[project.id] = project

        let useCase = PauseProjectUseCase(
            projectRepository: projectRepo,
            agentSessionRepository: agentSessionRepo
        )

        // 既にpausedの場合はエラーにならず、そのまま返す
        let result = try useCase.execute(projectId: project.id)
        XCTAssertEqual(result.status, .paused)
    }

    /// PauseProjectUseCase: archivedプロジェクトは一時停止できない
    func testPauseProjectUseCaseArchivedFails() throws {
        let project = Project(id: ProjectID.generate(), name: "TestProject", status: .archived)
        projectRepo.projects[project.id] = project

        let useCase = PauseProjectUseCase(
            projectRepository: projectRepo,
            agentSessionRepository: agentSessionRepo
        )

        XCTAssertThrowsError(try useCase.execute(projectId: project.id)) { error in
            guard case UseCaseError.invalidProjectStatus = error else {
                XCTFail("invalidProjectStatusエラーが期待される")
                return
            }
        }
    }

    /// ResumeProjectUseCase: 一時停止中のプロジェクトを再開する
    func testResumeProjectUseCaseSuccess() throws {
        // 前提: pausedなプロジェクト
        let project = Project(id: ProjectID.generate(), name: "TestProject", status: .paused)
        projectRepo.projects[project.id] = project

        let beforeResume = Date()

        // 実行
        let useCase = ResumeProjectUseCase(projectRepository: projectRepo)
        let result = try useCase.execute(projectId: project.id)

        // 検証: プロジェクトがactiveになっている
        XCTAssertEqual(result.status, .active, "プロジェクトがactiveになるべき")

        // 検証: resumedAtが設定されている
        XCTAssertNotNil(result.resumedAt, "resumedAtが設定されるべき")
        XCTAssertGreaterThanOrEqual(result.resumedAt!, beforeResume, "resumedAtは再開時刻以降")
    }

    /// ResumeProjectUseCase: 既にactiveのプロジェクトは何もしない
    func testResumeProjectUseCaseAlreadyActive() throws {
        let project = Project(id: ProjectID.generate(), name: "TestProject", status: .active)
        projectRepo.projects[project.id] = project

        let useCase = ResumeProjectUseCase(projectRepository: projectRepo)
        let result = try useCase.execute(projectId: project.id)

        XCTAssertEqual(result.status, .active)
        // resumedAtは更新されない（既にactiveなので）
    }

    /// ResumeProjectUseCase: archivedプロジェクトは再開できない
    func testResumeProjectUseCaseArchivedFails() throws {
        let project = Project(id: ProjectID.generate(), name: "TestProject", status: .archived)
        projectRepo.projects[project.id] = project

        let useCase = ResumeProjectUseCase(projectRepository: projectRepo)

        XCTAssertThrowsError(try useCase.execute(projectId: project.id)) { error in
            guard case UseCaseError.invalidProjectStatus = error else {
                XCTFail("invalidProjectStatusエラーが期待される")
                return
            }
        }
    }
}
