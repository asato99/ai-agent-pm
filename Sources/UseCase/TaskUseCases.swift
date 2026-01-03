// Sources/UseCase/TaskUseCases.swift
// タスク関連のユースケース

import Foundation
import Domain

// MARK: - UpdateTaskStatusUseCase

/// タスクステータス更新ユースケース
/// 要件: TASKS.md - 依存関係の遵守、リソース可用性の遵守（アプリで強制ブロック）
public struct UpdateTaskStatusUseCase: Sendable {
    private let taskRepository: any TaskRepositoryProtocol
    private let agentRepository: any AgentRepositoryProtocol
    private let eventRepository: any EventRepositoryProtocol

    public init(
        taskRepository: any TaskRepositoryProtocol,
        agentRepository: any AgentRepositoryProtocol,
        eventRepository: any EventRepositoryProtocol
    ) {
        self.taskRepository = taskRepository
        self.agentRepository = agentRepository
        self.eventRepository = eventRepository
    }

    public func execute(
        taskId: TaskID,
        newStatus: TaskStatus,
        agentId: AgentID?,
        sessionId: SessionID?,
        reason: String?
    ) throws -> Task {
        guard var task = try taskRepository.findById(taskId) else {
            throw UseCaseError.taskNotFound(taskId)
        }

        let previousStatus = task.status

        // ステータス遷移の検証
        guard Self.canTransition(from: previousStatus, to: newStatus) else {
            throw UseCaseError.invalidStatusTransition(from: previousStatus, to: newStatus)
        }

        // in_progressへの遷移時は依存関係とリソース可用性をチェック
        if newStatus == .inProgress {
            // 依存関係チェック: 全ての依存タスクがdoneである必要がある
            try checkDependencies(for: task)

            // リソース可用性チェック: エージェントの並列上限を超えていないか
            try checkResourceAvailability(for: task)
        }

        task.status = newStatus
        task.updatedAt = Date()

        if newStatus == .done {
            task.completedAt = Date()
        }

        try taskRepository.save(task)

        // イベント記録
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
        try eventRepository.save(event)

        return task
    }

    /// 依存関係チェック: 全ての依存タスクがdoneである必要がある
    /// 要件: 先行タスクが done になるまで in_progress に移行不可
    private func checkDependencies(for task: Task) throws {
        guard !task.dependencies.isEmpty else { return }

        var blockedByTasks: [TaskID] = []

        for dependencyId in task.dependencies {
            if let depTask = try taskRepository.findById(dependencyId) {
                if depTask.status != .done {
                    blockedByTasks.append(dependencyId)
                }
            }
            // 存在しない依存タスクは無視（削除済みなど）
        }

        if !blockedByTasks.isEmpty {
            throw UseCaseError.dependencyNotComplete(taskId: task.id, blockedByTasks: blockedByTasks)
        }
    }

    /// リソース可用性チェック: エージェントの並列上限を超えていないか
    /// 要件: アサイン先エージェントの並列実行可能数を超える場合、in_progress に移行不可
    private func checkResourceAvailability(for task: Task) throws {
        guard let assigneeId = task.assigneeId else {
            // アサインされていないタスクはリソースチェック不要
            return
        }

        guard let agent = try agentRepository.findById(assigneeId) else {
            // エージェントが存在しない場合はエラー
            throw UseCaseError.agentNotFound(assigneeId)
        }

        // 現在そのエージェントがin_progressで持っているタスク数をカウント
        let currentInProgressTasks = try taskRepository.findByAssignee(assigneeId)
            .filter { $0.status == .inProgress }
            .count

        if currentInProgressTasks >= agent.maxParallelTasks {
            throw UseCaseError.maxParallelTasksReached(
                agentId: assigneeId,
                maxParallel: agent.maxParallelTasks,
                currentCount: currentInProgressTasks
            )
        }
    }

    /// ステータス遷移が有効かどうかを検証
    /// 要件: inReview は削除。遷移フロー: backlog ↔ todo → in_progress ↔ blocked → done
    public static func canTransition(from: TaskStatus, to: TaskStatus) -> Bool {
        // 同じステータスへの遷移は不可
        if from == to { return false }

        switch (from, to) {
        case (.backlog, .todo), (.backlog, .cancelled):
            return true
        case (.todo, .inProgress), (.todo, .backlog), (.todo, .cancelled):
            return true
        case (.inProgress, .done), (.inProgress, .blocked), (.inProgress, .todo):
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

// MARK: - AssignTaskUseCase

/// タスク割り当てユースケース
public struct AssignTaskUseCase: Sendable {
    private let taskRepository: any TaskRepositoryProtocol
    private let agentRepository: any AgentRepositoryProtocol
    private let eventRepository: any EventRepositoryProtocol

    public init(
        taskRepository: any TaskRepositoryProtocol,
        agentRepository: any AgentRepositoryProtocol,
        eventRepository: any EventRepositoryProtocol
    ) {
        self.taskRepository = taskRepository
        self.agentRepository = agentRepository
        self.eventRepository = eventRepository
    }

    public func execute(
        taskId: TaskID,
        assigneeId: AgentID?,
        actorAgentId: AgentID?,
        sessionId: SessionID?
    ) throws -> Task {
        guard var task = try taskRepository.findById(taskId) else {
            throw UseCaseError.taskNotFound(taskId)
        }

        // 割り当て先エージェントの存在確認
        if let assigneeId = assigneeId {
            guard try agentRepository.findById(assigneeId) != nil else {
                throw UseCaseError.agentNotFound(assigneeId)
            }
        }

        let previousAssignee = task.assigneeId
        task.assigneeId = assigneeId
        task.updatedAt = Date()

        try taskRepository.save(task)

        // イベント記録
        let eventType: EventType = assigneeId != nil ? .assigned : .unassigned
        let event = StateChangeEvent(
            id: EventID.generate(),
            projectId: task.projectId,
            entityType: .task,
            entityId: task.id.value,
            eventType: eventType,
            agentId: actorAgentId,
            sessionId: sessionId,
            previousState: previousAssignee?.value,
            newState: assigneeId?.value
        )
        try eventRepository.save(event)

        return task
    }
}

// MARK: - CreateTaskUseCase

/// タスク作成ユースケース
public struct CreateTaskUseCase: Sendable {
    private let taskRepository: any TaskRepositoryProtocol
    private let projectRepository: any ProjectRepositoryProtocol
    private let eventRepository: any EventRepositoryProtocol

    public init(
        taskRepository: any TaskRepositoryProtocol,
        projectRepository: any ProjectRepositoryProtocol,
        eventRepository: any EventRepositoryProtocol
    ) {
        self.taskRepository = taskRepository
        self.projectRepository = projectRepository
        self.eventRepository = eventRepository
    }

    public func execute(
        projectId: ProjectID,
        title: String,
        description: String = "",
        priority: TaskPriority = .medium,
        assigneeId: AgentID? = nil,
        actorAgentId: AgentID?,
        sessionId: SessionID?
    ) throws -> Task {
        // プロジェクトの存在確認
        guard try projectRepository.findById(projectId) != nil else {
            throw UseCaseError.projectNotFound(projectId)
        }

        // バリデーション
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw UseCaseError.validationFailed("Title cannot be empty")
        }

        let task = Task(
            id: TaskID.generate(),
            projectId: projectId,
            title: title,
            description: description,
            status: .backlog,
            priority: priority,
            assigneeId: assigneeId
        )

        try taskRepository.save(task)

        // イベント記録
        let event = StateChangeEvent(
            id: EventID.generate(),
            projectId: projectId,
            entityType: .task,
            entityId: task.id.value,
            eventType: .created,
            agentId: actorAgentId,
            sessionId: sessionId,
            newState: task.status.rawValue
        )
        try eventRepository.save(event)

        return task
    }
}

// MARK: - GetMyTasksUseCase

/// 自分のタスク取得ユースケース
public struct GetMyTasksUseCase: Sendable {
    private let taskRepository: any TaskRepositoryProtocol

    public init(taskRepository: any TaskRepositoryProtocol) {
        self.taskRepository = taskRepository
    }

    public func execute(agentId: AgentID) throws -> [Task] {
        try taskRepository.findByAssignee(agentId)
    }
}

// MARK: - KickAgentUseCase

/// エージェントキックユースケース
/// タスクのアサイン先エージェントをキック（Claude Code CLI等を起動）する
public struct KickAgentUseCase: Sendable {
    private let taskRepository: any TaskRepositoryProtocol
    private let agentRepository: any AgentRepositoryProtocol
    private let projectRepository: any ProjectRepositoryProtocol
    private let eventRepository: any EventRepositoryProtocol
    private let kickService: any AgentKickServiceProtocol

    public init(
        taskRepository: any TaskRepositoryProtocol,
        agentRepository: any AgentRepositoryProtocol,
        projectRepository: any ProjectRepositoryProtocol,
        eventRepository: any EventRepositoryProtocol,
        kickService: any AgentKickServiceProtocol
    ) {
        self.taskRepository = taskRepository
        self.agentRepository = agentRepository
        self.projectRepository = projectRepository
        self.eventRepository = eventRepository
        self.kickService = kickService
    }

    /// エージェントをキックする
    /// - Parameters:
    ///   - taskId: キック対象のタスクID
    /// - Returns: キック結果
    public func execute(taskId: TaskID) async throws -> AgentKickResult {
        // タスクを取得
        guard let task = try taskRepository.findById(taskId) else {
            throw UseCaseError.taskNotFound(taskId)
        }

        // アサイン先エージェントを確認
        guard let assigneeId = task.assigneeId else {
            throw AgentKickError.taskNotAssigned(taskId)
        }

        guard let agent = try agentRepository.findById(assigneeId) else {
            throw UseCaseError.agentNotFound(assigneeId)
        }

        // プロジェクトを取得
        guard let project = try projectRepository.findById(task.projectId) else {
            throw UseCaseError.projectNotFound(task.projectId)
        }

        // キックを実行
        let result = try await kickService.kick(agent: agent, task: task, project: project)

        // キックイベントを記録
        let event = StateChangeEvent(
            id: EventID.generate(),
            projectId: task.projectId,
            entityType: .task,
            entityId: task.id.value,
            eventType: .kicked,
            agentId: agent.id,
            newState: result.success ? "success" : "failed",
            reason: result.message,
            metadata: result.processId.map { ["processId": String($0)] }
        )
        try eventRepository.save(event)

        return result
    }
}
