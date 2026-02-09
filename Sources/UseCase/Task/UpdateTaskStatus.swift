// Sources/UseCase/Task/UpdateTaskStatus.swift
// タスクステータス更新ユースケース

import Foundation
import Domain

// MARK: - UpdateTaskStatusUseCase

/// タスクステータス更新ユースケース
/// 要件: TASKS.md - 依存関係の遵守、リソース可用性の遵守（アプリで強制ブロック）
/// 要件: AUDIT.md - タスク完了時のAudit Ruleトリガー発動
public struct UpdateTaskStatusUseCase: Sendable {
    private let taskRepository: any TaskRepositoryProtocol
    private let agentRepository: any AgentRepositoryProtocol
    private let eventRepository: any EventRepositoryProtocol
    // Audit Trigger用（オプション）
    private let internalAuditRepository: (any InternalAuditRepositoryProtocol)?
    private let auditRuleRepository: (any AuditRuleRepositoryProtocol)?

    public init(
        taskRepository: any TaskRepositoryProtocol,
        agentRepository: any AgentRepositoryProtocol,
        eventRepository: any EventRepositoryProtocol
    ) {
        self.taskRepository = taskRepository
        self.agentRepository = agentRepository
        self.eventRepository = eventRepository
        self.internalAuditRepository = nil
        self.auditRuleRepository = nil
    }

    /// Audit Trigger機能付きの初期化
    /// 設計: AuditRuleはインラインでauditTasksを保持（WorkflowTemplateはプロジェクトスコープのため参照不要）
    public init(
        taskRepository: any TaskRepositoryProtocol,
        agentRepository: any AgentRepositoryProtocol,
        eventRepository: any EventRepositoryProtocol,
        internalAuditRepository: any InternalAuditRepositoryProtocol,
        auditRuleRepository: any AuditRuleRepositoryProtocol
    ) {
        self.taskRepository = taskRepository
        self.agentRepository = agentRepository
        self.eventRepository = eventRepository
        self.internalAuditRepository = internalAuditRepository
        self.auditRuleRepository = auditRuleRepository
    }

    /// ステータス更新結果
    public struct Result: Sendable {
        public let task: Task
        public let previousStatus: TaskStatus
        public let firedAuditRules: [FiredAuditRule]

        public struct FiredAuditRule: Sendable {
            public let ruleName: String
            public let createdTaskCount: Int
        }
    }

    public func execute(
        taskId: TaskID,
        newStatus: TaskStatus,
        agentId: AgentID?,
        sessionId: SessionID?,
        reason: String?
    ) throws -> Task {
        let result = try executeWithResult(
            taskId: taskId,
            newStatus: newStatus,
            agentId: agentId,
            sessionId: sessionId,
            reason: reason
        )
        return result.task
    }

    /// 詳細な結果を返すバージョン
    public func executeWithResult(
        taskId: TaskID,
        newStatus: TaskStatus,
        agentId: AgentID?,
        sessionId: SessionID?,
        reason: String?
    ) throws -> Result {
        guard var task = try taskRepository.findById(taskId) else {
            throw UseCaseError.taskNotFound(taskId)
        }

        let previousStatus = task.status

        // ロック中のタスクはステータス変更不可
        // 参照: AUDIT.md - タスクロック: 状態変更を禁止
        guard !task.isLocked else {
            throw UseCaseError.validationFailed("Task is locked and cannot change status")
        }

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

        // ステータス変更権限チェック
        // 参照: docs/plan/BLOCKED_TASK_RECOVERY.md
        // 前回の更新者が自身または下位ワーカー以外の場合は変更不可
        try validateStatusChangePermission(task: task, requestingAgentId: agentId)

        task.status = newStatus
        task.updatedAt = Date()

        // ステータス変更追跡情報を記録
        // agentIdがnilの場合はUIからの操作として system:user を設定
        task.statusChangedByAgentId = agentId ?? AgentID.systemUser
        task.statusChangedAt = Date()

        // blockedReason の処理
        if newStatus != .blocked {
            task.blockedReason = nil
        } else if task.blockedReason == nil {
            task.blockedReason = reason
        }

        if newStatus == .done {
            task.completedAt = Date()
        }

        try taskRepository.save(task)

        // UC008: ブロック時のカスケード処理
        // 親タスクがblockedになった場合、全サブタスクもblockedにカスケード
        if newStatus == .blocked {
            try cascadeBlockingToSubtasks(parentTask: task, agentId: agentId, sessionId: sessionId)
        }

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

        // タスク完了時のAudit Ruleトリガーチェック
        // 参照: AUDIT.md - 自動トリガー機能
        var firedRules: [Result.FiredAuditRule] = []
        if newStatus == .done {
            firedRules = try checkAndFireAuditTriggers(for: task)
        }

        return Result(task: task, previousStatus: previousStatus, firedAuditRules: firedRules)
    }

    /// Audit Ruleトリガーをチェックし、マッチするルールを発火
    private func checkAndFireAuditTriggers(for task: Task) throws -> [Result.FiredAuditRule] {
        // Audit機能が設定されていない場合はスキップ
        guard let internalAuditRepo = internalAuditRepository,
              let auditRuleRepo = auditRuleRepository else {
            return []
        }

        var firedRules: [Result.FiredAuditRule] = []

        // 全てのアクティブなInternal Auditを取得
        let activeAudits = try internalAuditRepo.findAll(includeInactive: false)
            .filter { $0.status == .active }

        // 各Auditのルールをチェック
        for audit in activeAudits {
            // 有効なルールのみ取得
            let enabledRules = try auditRuleRepo.findEnabled(auditId: audit.id)

            // タスク完了トリガーにマッチするルールを発火
            for rule in enabledRules where rule.triggerType == .taskCompleted {
                let createdTasks = try fireAuditRule(rule: rule, sourceTask: task)
                firedRules.append(Result.FiredAuditRule(ruleName: rule.name, createdTaskCount: createdTasks.count))
            }
        }

        return firedRules
    }

    /// Audit Ruleを発火してタスクを生成
    /// 設計: AuditRuleはインラインでauditTasksを保持（WorkflowTemplateはプロジェクトスコープのため参照不要）
    private func fireAuditRule(
        rule: AuditRule,
        sourceTask: Task
    ) throws -> [Task] {
        // auditTasksが空の場合はスキップ
        guard rule.hasTasks else {
            return []
        }

        // タスクを生成
        var createdTasks: [Task] = []
        var orderToTaskIdMap: [Int: TaskID] = [:]

        for auditTask in rule.auditTasks {
            let taskId = TaskID.generate()
            orderToTaskIdMap[auditTask.order] = taskId

            // 依存関係をTaskIDに変換
            let dependencies = auditTask.dependsOnOrders.compactMap { orderToTaskIdMap[$0] }

            // タイトルにソースタスク情報を含める
            let titleWithContext = "\(auditTask.title) [Audit: \(sourceTask.title)]"

            let newTask = Task(
                id: taskId,
                projectId: sourceTask.projectId,
                title: titleWithContext,
                description: auditTask.description,
                status: .backlog,
                priority: auditTask.priority,
                assigneeId: auditTask.assigneeId,
                dependencies: dependencies
            )
            try taskRepository.save(newTask)
            createdTasks.append(newTask)

            // イベント記録
            let event = StateChangeEvent(
                id: EventID.generate(),
                projectId: sourceTask.projectId,
                entityType: .task,
                entityId: newTask.id.value,
                eventType: .created,
                newState: newTask.status.rawValue,
                metadata: [
                    "auditRuleId": rule.id.value,
                    "auditId": rule.auditId.value,
                    "sourceTaskId": sourceTask.id.value,
                    "triggerType": TriggerType.taskCompleted.rawValue
                ]
            )
            try eventRepository.save(event)
        }

        return createdTasks
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
    /// 注意: maxParallelTasksは「起動数」を表す。サブタスクはカウント対象外。
    ///       親タスク（parentTaskId == nil）のみがカウントされる。
    private func checkResourceAvailability(for task: Task) throws {
        guard let assigneeId = task.assigneeId else {
            throw UseCaseError.validationFailed("in_progress への遷移にはエージェントの割り当て（assignee_id）が必要です")
        }

        guard let agent = try agentRepository.findById(assigneeId) else {
            // エージェントが存在しない場合はエラー
            throw UseCaseError.agentNotFound(assigneeId)
        }

        // サブタスク（parentTaskIdあり）の場合はリソースチェックをスキップ
        // サブタスクは親タスクの起動の一部として扱われる
        if task.parentTaskId != nil {
            return
        }

        // 現在そのエージェントがin_progressで持っている親タスク数をカウント
        // サブタスク（parentTaskId != nil）は除外
        let currentInProgressParentTasks = try taskRepository.findByAssignee(assigneeId)
            .filter { $0.status == .inProgress && $0.parentTaskId == nil }
            .count

        if currentInProgressParentTasks >= agent.maxParallelTasks {
            throw UseCaseError.maxParallelTasksReached(
                agentId: assigneeId,
                maxParallel: agent.maxParallelTasks,
                currentCount: currentInProgressParentTasks
            )
        }
    }

    /// ステータス変更権限チェック
    /// 参照: docs/plan/BLOCKED_TASK_RECOVERY.md
    /// 前回の更新者が自身または下位ワーカー以外の場合は変更不可
    private func validateStatusChangePermission(task: Task, requestingAgentId: AgentID?) throws {
        // statusChangedByAgentId が未設定の場合は許可（後方互換性）
        guard let lastChangedBy = task.statusChangedByAgentId else {
            return
        }

        // リクエスト元エージェントが指定されていない場合も許可
        // （UI操作など、エージェント以外からの変更を許可するため）
        guard let requestingAgent = requestingAgentId else {
            return
        }

        // 1. 自己変更の場合 → 許可
        if lastChangedBy == requestingAgent {
            return
        }

        // 2. 変更者が自身の下位ワーカーの場合 → 許可
        let subordinates = try agentRepository.findByParent(requestingAgent)
        if subordinates.contains(where: { $0.id == lastChangedBy }) {
            return
        }

        // 3. それ以外 → 拒否
        throw UseCaseError.validationFailed(
            "Cannot change task status. Last status change by \(lastChangedBy.value). Only self or subordinate workers can modify."
        )
    }

    /// UC008: サブタスクへのブロックカスケード
    /// 親タスクがblockedになった場合、全サブタスクもblockedにカスケードする
    /// 参照: docs/usecases/UC008_TaskBlocking.md
    private func cascadeBlockingToSubtasks(
        parentTask: Task,
        agentId: AgentID?,
        sessionId: SessionID?
    ) throws {
        // プロジェクト内の全タスクを取得してサブタスクをフィルタリング
        let allTasks = try taskRepository.findByProject(parentTask.projectId, status: nil)
        let subtasks = allTasks.filter { $0.parentTaskId == parentTask.id }

        for var subtask in subtasks {
            // 既にblockedまたは完了状態のタスクはスキップ
            guard subtask.status != .blocked && !subtask.status.isCompleted else {
                continue
            }

            // previousStateを保存してからステータス変更
            let previousStatus = subtask.status

            // サブタスクをblockedに更新
            subtask.status = .blocked
            subtask.updatedAt = Date()
            try taskRepository.save(subtask)

            // イベント記録
            let event = StateChangeEvent(
                id: EventID.generate(),
                projectId: subtask.projectId,
                entityType: .task,
                entityId: subtask.id.value,
                eventType: .statusChanged,
                agentId: agentId,
                sessionId: sessionId,
                previousState: previousStatus.rawValue,
                newState: TaskStatus.blocked.rawValue,
                reason: "Cascaded from parent task: \(parentTask.id.value)"
            )
            try eventRepository.save(event)

            // 再帰的にサブタスクのサブタスクもブロック
            try cascadeBlockingToSubtasks(parentTask: subtask, agentId: agentId, sessionId: sessionId)
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
        // Feature 12: 作業コンテキスト破棄防止
        // in_progress → todo/backlog は禁止（ExecutionLogが作成済みのため）
        case (.inProgress, .done), (.inProgress, .blocked):
            return true
        // Feature 12: blocked → todo/backlog は禁止（BlockLogが作成済みのため）
        case (.blocked, .inProgress), (.blocked, .cancelled):
            return true
        case (.done, _), (.cancelled, _):
            return false // 完了・キャンセル済みからは遷移不可
        default:
            return false
        }
    }
}
