// Sources/App/Core/DependencyContainer/DependencyContainer.swift
// DIコンテナ - アプリケーション全体の依存関係を管理
// 要件: サブタスク概念は削除（タスク間の関係は依存関係のみで表現）

import SwiftUI
import Domain
import UseCase
import Infrastructure

/// アプリケーション全体の依存関係を管理するコンテナ
@MainActor
public final class DependencyContainer: ObservableObject {

    // MARK: - Repositories

    public let projectRepository: ProjectRepository
    public let agentRepository: AgentRepository
    public let taskRepository: TaskRepository
    public let sessionRepository: SessionRepository
    public let contextRepository: ContextRepository
    public let handoffRepository: HandoffRepository
    public let eventRepository: EventRepository

    // MARK: - Event Recorder

    public let eventRecorder: EventRecorder

    // MARK: - Services

    public let kickService: ClaudeCodeKickService

    // MARK: - Use Cases (Project)

    public lazy var getProjectsUseCase: GetProjectsUseCase = {
        GetProjectsUseCase(projectRepository: projectRepository)
    }()

    public lazy var createProjectUseCase: CreateProjectUseCase = {
        CreateProjectUseCase(projectRepository: projectRepository)
    }()

    // MARK: - Use Cases (Agent)

    public lazy var getAgentsUseCase: GetAgentsUseCase = {
        GetAgentsUseCase(agentRepository: agentRepository)
    }()

    public lazy var createAgentUseCase: CreateAgentUseCase = {
        CreateAgentUseCase(agentRepository: agentRepository)
    }()

    public lazy var getAgentProfileUseCase: GetAgentProfileUseCase = {
        GetAgentProfileUseCase(agentRepository: agentRepository)
    }()

    // MARK: - Use Cases (Task)

    public lazy var getTasksUseCase: GetTasksUseCase = {
        GetTasksUseCase(taskRepository: taskRepository)
    }()

    public lazy var getTasksByAssigneeUseCase: GetTasksByAssigneeUseCase = {
        GetTasksByAssigneeUseCase(taskRepository: taskRepository)
    }()

    public lazy var getTaskDetailUseCase: GetTaskDetailUseCase = {
        GetTaskDetailUseCase(
            taskRepository: taskRepository,
            contextRepository: contextRepository
        )
    }()

    public lazy var createTaskUseCase: CreateTaskUseCase = {
        CreateTaskUseCase(
            taskRepository: taskRepository,
            projectRepository: projectRepository,
            eventRepository: eventRepository
        )
    }()

    public lazy var updateTaskUseCase: UpdateTaskUseCase = {
        UpdateTaskUseCase(taskRepository: taskRepository)
    }()

    public lazy var updateTaskStatusUseCase: UpdateTaskStatusUseCase = {
        UpdateTaskStatusUseCase(
            taskRepository: taskRepository,
            agentRepository: agentRepository,
            eventRepository: eventRepository
        )
    }()

    public lazy var assignTaskUseCase: AssignTaskUseCase = {
        AssignTaskUseCase(
            taskRepository: taskRepository,
            agentRepository: agentRepository,
            eventRepository: eventRepository
        )
    }()

    public lazy var kickAgentUseCase: KickAgentUseCase = {
        KickAgentUseCase(
            taskRepository: taskRepository,
            agentRepository: agentRepository,
            projectRepository: projectRepository,
            eventRepository: eventRepository,
            kickService: kickService
        )
    }()

    // MARK: - Use Cases (Session)

    public lazy var startSessionUseCase: StartSessionUseCase = {
        StartSessionUseCase(
            sessionRepository: sessionRepository,
            agentRepository: agentRepository,
            eventRepository: eventRepository
        )
    }()

    public lazy var endSessionUseCase: EndSessionUseCase = {
        EndSessionUseCase(
            sessionRepository: sessionRepository,
            eventRepository: eventRepository
        )
    }()

    public lazy var getActiveSessionUseCase: GetActiveSessionUseCase = {
        GetActiveSessionUseCase(sessionRepository: sessionRepository)
    }()

    public lazy var getAgentSessionsUseCase: GetAgentSessionsUseCase = {
        GetAgentSessionsUseCase(sessionRepository: sessionRepository)
    }()

    // MARK: - Use Cases (Context)

    public lazy var saveContextUseCase: SaveContextUseCase = {
        SaveContextUseCase(
            contextRepository: contextRepository,
            taskRepository: taskRepository,
            sessionRepository: sessionRepository,
            eventRepository: eventRepository
        )
    }()

    public lazy var getTaskContextUseCase: GetTaskContextUseCase = {
        GetTaskContextUseCase(contextRepository: contextRepository)
    }()

    // MARK: - Use Cases (Handoff)

    public lazy var createHandoffUseCase: CreateHandoffUseCase = {
        CreateHandoffUseCase(
            handoffRepository: handoffRepository,
            taskRepository: taskRepository,
            agentRepository: agentRepository,
            eventRepository: eventRepository
        )
    }()

    public lazy var acceptHandoffUseCase: AcceptHandoffUseCase = {
        AcceptHandoffUseCase(
            handoffRepository: handoffRepository,
            taskRepository: taskRepository,
            eventRepository: eventRepository
        )
    }()

    public lazy var getPendingHandoffsUseCase: GetPendingHandoffsUseCase = {
        GetPendingHandoffsUseCase(handoffRepository: handoffRepository)
    }()

    // MARK: - Initialization

    public init(databasePath: String) throws {
        let database = try DatabaseSetup.createDatabase(at: databasePath)

        self.projectRepository = ProjectRepository(database: database)
        self.agentRepository = AgentRepository(database: database)
        self.taskRepository = TaskRepository(database: database)
        self.sessionRepository = SessionRepository(database: database)
        self.contextRepository = ContextRepository(database: database)
        self.handoffRepository = HandoffRepository(database: database)
        self.eventRepository = EventRepository(database: database)
        self.eventRecorder = EventRecorder(database: database)
        self.kickService = ClaudeCodeKickService()
    }

    /// デフォルトのデータベースパスを使用して初期化
    public convenience init() throws {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        let appDirectory = appSupport.appendingPathComponent("AIAgentPM")
        let dbPath = appDirectory.appendingPathComponent("pm.db").path
        try self.init(databasePath: dbPath)
    }
}
