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

    // MARK: - Shared Instance

    /// グローバル共有インスタンス（アプリ起動時に設定）
    /// 注意: 通常は@EnvironmentObject経由でアクセスすべき
    public static var shared: DependencyContainer!

    // MARK: - Database Path

    /// 使用中のデータベースパス（MCPデーモン起動時に渡す）
    public let databasePath: String

    // MARK: - Repositories

    public let projectRepository: ProjectRepository
    public let agentRepository: AgentRepository
    public let taskRepository: TaskRepository
    public let sessionRepository: SessionRepository
    public let contextRepository: ContextRepository
    public let handoffRepository: HandoffRepository
    public let eventRepository: EventRepository
    public let workflowTemplateRepository: WorkflowTemplateRepository
    public let templateTaskRepository: TemplateTaskRepository
    public let internalAuditRepository: InternalAuditRepository
    public let auditRuleRepository: AuditRuleRepository
    public let executionLogRepository: ExecutionLogRepository
    public let agentCredentialRepository: AgentCredentialRepository
    public let projectAgentAssignmentRepository: ProjectAgentAssignmentRepository
    public let agentSessionRepository: AgentSessionRepository
    public let skillDefinitionRepository: SkillDefinitionRepository
    public let agentSkillAssignmentRepository: AgentSkillAssignmentRepository

    // MARK: - File Storage

    public let projectDirectoryManager: ProjectDirectoryManager
    public let chatRepository: ChatFileRepository

    // MARK: - App Settings
    /// アプリケーション設定リポジトリ（Coordinator Token等）
    public let appSettingsRepository: AppSettingsRepository

    // MARK: - Event Recorder

    public let eventRecorder: EventRecorder

    // MARK: - Services

    public let mcpDaemonManager: MCPDaemonManager
    public let webServerManager: WebServerManager
    public let skillArchiveService: SkillArchiveService

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
        CreateAgentUseCase(
            agentRepository: agentRepository,
            credentialRepository: agentCredentialRepository
        )
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
            eventRepository: eventRepository,
            internalAuditRepository: internalAuditRepository,
            auditRuleRepository: auditRuleRepository
        )
    }()

    public lazy var assignTaskUseCase: AssignTaskUseCase = {
        AssignTaskUseCase(
            taskRepository: taskRepository,
            agentRepository: agentRepository,
            eventRepository: eventRepository
        )
    }()

    public lazy var approveTaskUseCase: ApproveTaskUseCase = {
        ApproveTaskUseCase(
            taskRepository: taskRepository,
            agentRepository: agentRepository,
            eventRepository: eventRepository
        )
    }()

    public lazy var rejectTaskUseCase: RejectTaskUseCase = {
        RejectTaskUseCase(
            taskRepository: taskRepository,
            agentRepository: agentRepository,
            eventRepository: eventRepository
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

    // MARK: - Use Cases (Workflow Template)

    public lazy var listTemplatesUseCase: ListTemplatesUseCase = {
        ListTemplatesUseCase(templateRepository: workflowTemplateRepository)
    }()

    public lazy var listAllTemplatesUseCase: ListAllTemplatesUseCase = {
        ListAllTemplatesUseCase(templateRepository: workflowTemplateRepository)
    }()

    public lazy var createTemplateUseCase: CreateTemplateUseCase = {
        CreateTemplateUseCase(
            templateRepository: workflowTemplateRepository,
            templateTaskRepository: templateTaskRepository,
            projectRepository: projectRepository
        )
    }()

    public lazy var updateTemplateUseCase: UpdateTemplateUseCase = {
        UpdateTemplateUseCase(templateRepository: workflowTemplateRepository)
    }()

    public lazy var archiveTemplateUseCase: ArchiveTemplateUseCase = {
        ArchiveTemplateUseCase(templateRepository: workflowTemplateRepository)
    }()

    public lazy var getTemplateWithTasksUseCase: GetTemplateWithTasksUseCase = {
        GetTemplateWithTasksUseCase(
            templateRepository: workflowTemplateRepository,
            templateTaskRepository: templateTaskRepository
        )
    }()

    public lazy var instantiateTemplateUseCase: InstantiateTemplateUseCase = {
        InstantiateTemplateUseCase(
            templateRepository: workflowTemplateRepository,
            templateTaskRepository: templateTaskRepository,
            taskRepository: taskRepository,
            projectRepository: projectRepository,
            eventRepository: eventRepository
        )
    }()

    // MARK: - Use Cases (Internal Audit)

    public lazy var listInternalAuditsUseCase: ListInternalAuditsUseCase = {
        ListInternalAuditsUseCase(internalAuditRepository: internalAuditRepository)
    }()

    public lazy var createInternalAuditUseCase: CreateInternalAuditUseCase = {
        CreateInternalAuditUseCase(internalAuditRepository: internalAuditRepository)
    }()

    public lazy var getInternalAuditUseCase: GetInternalAuditUseCase = {
        GetInternalAuditUseCase(internalAuditRepository: internalAuditRepository)
    }()

    public lazy var updateInternalAuditUseCase: UpdateInternalAuditUseCase = {
        UpdateInternalAuditUseCase(internalAuditRepository: internalAuditRepository)
    }()

    public lazy var suspendInternalAuditUseCase: SuspendInternalAuditUseCase = {
        SuspendInternalAuditUseCase(internalAuditRepository: internalAuditRepository)
    }()

    public lazy var activateInternalAuditUseCase: ActivateInternalAuditUseCase = {
        ActivateInternalAuditUseCase(internalAuditRepository: internalAuditRepository)
    }()

    public lazy var deleteInternalAuditUseCase: DeleteInternalAuditUseCase = {
        DeleteInternalAuditUseCase(internalAuditRepository: internalAuditRepository)
    }()

    public lazy var getAuditWithRulesUseCase: GetAuditWithRulesUseCase = {
        GetAuditWithRulesUseCase(
            internalAuditRepository: internalAuditRepository,
            auditRuleRepository: auditRuleRepository
        )
    }()

    public lazy var listAuditRulesUseCase: ListAuditRulesUseCase = {
        ListAuditRulesUseCase(auditRuleRepository: auditRuleRepository)
    }()

    public lazy var createAuditRuleUseCase: CreateAuditRuleUseCase = {
        CreateAuditRuleUseCase(
            auditRuleRepository: auditRuleRepository,
            internalAuditRepository: internalAuditRepository
        )
    }()

    public lazy var updateAuditRuleUseCase: UpdateAuditRuleUseCase = {
        UpdateAuditRuleUseCase(auditRuleRepository: auditRuleRepository)
    }()

    public lazy var enableDisableAuditRuleUseCase: EnableDisableAuditRuleUseCase = {
        EnableDisableAuditRuleUseCase(auditRuleRepository: auditRuleRepository)
    }()

    public lazy var deleteAuditRuleUseCase: DeleteAuditRuleUseCase = {
        DeleteAuditRuleUseCase(auditRuleRepository: auditRuleRepository)
    }()

    // MARK: - Use Cases (Lock)

    public lazy var lockTaskUseCase: LockTaskUseCase = {
        LockTaskUseCase(
            taskRepository: taskRepository,
            internalAuditRepository: internalAuditRepository
        )
    }()

    public lazy var unlockTaskUseCase: UnlockTaskUseCase = {
        UnlockTaskUseCase(
            taskRepository: taskRepository,
            internalAuditRepository: internalAuditRepository
        )
    }()

    public lazy var lockAgentUseCase: LockAgentUseCase = {
        LockAgentUseCase(
            agentRepository: agentRepository,
            internalAuditRepository: internalAuditRepository
        )
    }()

    public lazy var unlockAgentUseCase: UnlockAgentUseCase = {
        UnlockAgentUseCase(
            agentRepository: agentRepository,
            internalAuditRepository: internalAuditRepository
        )
    }()

    public lazy var getLockedTasksUseCase: GetLockedTasksUseCase = {
        GetLockedTasksUseCase(taskRepository: taskRepository)
    }()

    public lazy var getLockedAgentsUseCase: GetLockedAgentsUseCase = {
        GetLockedAgentsUseCase(agentRepository: agentRepository)
    }()

    // MARK: - Use Cases (Execution Log)

    public lazy var getExecutionLogsUseCase: GetExecutionLogsUseCase = {
        GetExecutionLogsUseCase(executionLogRepository: executionLogRepository)
    }()

    // MARK: - Use Cases (Skills)

    public lazy var skillDefinitionUseCases: SkillDefinitionUseCases = {
        SkillDefinitionUseCases(skillRepository: skillDefinitionRepository)
    }()

    public lazy var agentSkillUseCases: AgentSkillUseCases = {
        AgentSkillUseCases(
            assignmentRepository: agentSkillAssignmentRepository,
            skillRepository: skillDefinitionRepository
        )
    }()

    // MARK: - Use Cases (Audit Triggers)

    public lazy var fireAuditRuleUseCase: FireAuditRuleUseCase = {
        FireAuditRuleUseCase(
            auditRuleRepository: auditRuleRepository,
            taskRepository: taskRepository,
            eventRepository: eventRepository
        )
    }()

    public lazy var checkAuditTriggersUseCase: CheckAuditTriggersUseCase = {
        CheckAuditTriggersUseCase(
            internalAuditRepository: internalAuditRepository,
            auditRuleRepository: auditRuleRepository,
            fireAuditRuleUseCase: fireAuditRuleUseCase
        )
    }()

    // MARK: - Initialization

    public init(databasePath: String) throws {
        let database = try DatabaseSetup.createDatabase(at: databasePath)

        self.databasePath = databasePath
        self.projectRepository = ProjectRepository(database: database)
        self.agentRepository = AgentRepository(database: database)
        self.taskRepository = TaskRepository(database: database)
        self.sessionRepository = SessionRepository(database: database)
        self.contextRepository = ContextRepository(database: database)
        self.handoffRepository = HandoffRepository(database: database)
        self.eventRepository = EventRepository(database: database)
        self.workflowTemplateRepository = WorkflowTemplateRepository(database: database)
        self.templateTaskRepository = TemplateTaskRepository(database: database)
        self.internalAuditRepository = InternalAuditRepository(database: database)
        self.auditRuleRepository = AuditRuleRepository(database: database)
        self.executionLogRepository = ExecutionLogRepository(database: database)
        self.agentCredentialRepository = AgentCredentialRepository(database: database)
        self.projectAgentAssignmentRepository = ProjectAgentAssignmentRepository(database: database)
        self.agentSessionRepository = AgentSessionRepository(database: database)
        self.skillDefinitionRepository = SkillDefinitionRepository(database: database)
        self.agentSkillAssignmentRepository = AgentSkillAssignmentRepository(database: database)
        self.eventRecorder = EventRecorder(database: database)
        self.mcpDaemonManager = MCPDaemonManager()
        self.webServerManager = WebServerManager()
        self.skillArchiveService = SkillArchiveService()

        // File Storage (ファイルベースストレージ)
        self.projectDirectoryManager = ProjectDirectoryManager()
        self.chatRepository = ChatFileRepository(
            directoryManager: projectDirectoryManager,
            projectRepository: projectRepository
        )

        // App Settings (アプリケーション設定)
        self.appSettingsRepository = AppSettingsRepository(database: database)

        // Set coordinator token provider for MCPDaemonManager
        // This allows the daemon to read the token from the database
        let settingsRepo = self.appSettingsRepository
        self.mcpDaemonManager.coordinatorTokenProvider = {
            try? settingsRepo.get().coordinatorToken
        }
    }

    /// デフォルトのデータベースパスを使用して初期化
    /// AppConfig.databasePath を使用（環境変数で切り替え可能）
    public convenience init() throws {
        try self.init(databasePath: AppConfig.databasePath)
    }
}
