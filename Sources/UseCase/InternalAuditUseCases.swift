// Sources/UseCase/InternalAuditUseCases.swift
// Internal Audit関連のユースケース
// 参照: docs/requirements/AUDIT.md

import Foundation
import Domain

// MARK: - CreateInternalAuditUseCase

/// Internal Audit作成ユースケース
public struct CreateInternalAuditUseCase: Sendable {
    private let internalAuditRepository: any InternalAuditRepositoryProtocol

    public init(internalAuditRepository: any InternalAuditRepositoryProtocol) {
        self.internalAuditRepository = internalAuditRepository
    }

    public func execute(name: String, description: String? = nil) throws -> InternalAudit {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            throw UseCaseError.validationFailed("Name cannot be empty")
        }
        guard trimmedName.count <= 100 else {
            throw UseCaseError.validationFailed("Name must be 100 characters or less")
        }

        let audit = InternalAudit(
            id: InternalAuditID.generate(),
            name: trimmedName,
            description: description
        )
        try internalAuditRepository.save(audit)
        return audit
    }
}

// MARK: - ListInternalAuditsUseCase

/// Internal Audit一覧取得ユースケース
public struct ListInternalAuditsUseCase: Sendable {
    private let internalAuditRepository: any InternalAuditRepositoryProtocol

    public init(internalAuditRepository: any InternalAuditRepositoryProtocol) {
        self.internalAuditRepository = internalAuditRepository
    }

    public func execute(includeInactive: Bool = false) throws -> [InternalAudit] {
        try internalAuditRepository.findAll(includeInactive: includeInactive)
    }
}

// MARK: - GetInternalAuditUseCase

/// Internal Audit詳細取得ユースケース
public struct GetInternalAuditUseCase: Sendable {
    private let internalAuditRepository: any InternalAuditRepositoryProtocol

    public init(internalAuditRepository: any InternalAuditRepositoryProtocol) {
        self.internalAuditRepository = internalAuditRepository
    }

    public func execute(auditId: InternalAuditID) throws -> InternalAudit {
        guard let audit = try internalAuditRepository.findById(auditId) else {
            throw UseCaseError.internalAuditNotFound(auditId)
        }
        return audit
    }
}

// MARK: - UpdateInternalAuditUseCase

/// Internal Audit更新ユースケース
public struct UpdateInternalAuditUseCase: Sendable {
    private let internalAuditRepository: any InternalAuditRepositoryProtocol

    public init(internalAuditRepository: any InternalAuditRepositoryProtocol) {
        self.internalAuditRepository = internalAuditRepository
    }

    public func execute(
        auditId: InternalAuditID,
        name: String? = nil,
        description: String? = nil
    ) throws -> InternalAudit {
        guard var audit = try internalAuditRepository.findById(auditId) else {
            throw UseCaseError.internalAuditNotFound(auditId)
        }

        if let name = name {
            let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedName.isEmpty else {
                throw UseCaseError.validationFailed("Name cannot be empty")
            }
            guard trimmedName.count <= 100 else {
                throw UseCaseError.validationFailed("Name must be 100 characters or less")
            }
            audit.name = trimmedName
        }

        if let description = description {
            audit.description = description
        }

        audit.updatedAt = Date()
        try internalAuditRepository.save(audit)
        return audit
    }
}

// MARK: - SuspendInternalAuditUseCase

/// Internal Audit一時停止ユースケース
public struct SuspendInternalAuditUseCase: Sendable {
    private let internalAuditRepository: any InternalAuditRepositoryProtocol

    public init(internalAuditRepository: any InternalAuditRepositoryProtocol) {
        self.internalAuditRepository = internalAuditRepository
    }

    public func execute(auditId: InternalAuditID) throws -> InternalAudit {
        guard var audit = try internalAuditRepository.findById(auditId) else {
            throw UseCaseError.internalAuditNotFound(auditId)
        }

        audit.status = .suspended
        audit.updatedAt = Date()
        try internalAuditRepository.save(audit)
        return audit
    }
}

// MARK: - ActivateInternalAuditUseCase

/// Internal Audit有効化ユースケース
public struct ActivateInternalAuditUseCase: Sendable {
    private let internalAuditRepository: any InternalAuditRepositoryProtocol

    public init(internalAuditRepository: any InternalAuditRepositoryProtocol) {
        self.internalAuditRepository = internalAuditRepository
    }

    public func execute(auditId: InternalAuditID) throws -> InternalAudit {
        guard var audit = try internalAuditRepository.findById(auditId) else {
            throw UseCaseError.internalAuditNotFound(auditId)
        }

        audit.status = .active
        audit.updatedAt = Date()
        try internalAuditRepository.save(audit)
        return audit
    }
}

// MARK: - CreateAuditRuleUseCase

/// Audit Rule作成ユースケース
public struct CreateAuditRuleUseCase: Sendable {
    private let auditRuleRepository: any AuditRuleRepositoryProtocol
    private let internalAuditRepository: any InternalAuditRepositoryProtocol
    private let workflowTemplateRepository: any WorkflowTemplateRepositoryProtocol

    public init(
        auditRuleRepository: any AuditRuleRepositoryProtocol,
        internalAuditRepository: any InternalAuditRepositoryProtocol,
        workflowTemplateRepository: any WorkflowTemplateRepositoryProtocol
    ) {
        self.auditRuleRepository = auditRuleRepository
        self.internalAuditRepository = internalAuditRepository
        self.workflowTemplateRepository = workflowTemplateRepository
    }

    public func execute(
        auditId: InternalAuditID,
        name: String,
        triggerType: TriggerType,
        triggerConfig: [String: Any]? = nil,
        workflowTemplateId: WorkflowTemplateID,
        taskAssignments: [TaskAssignment]
    ) throws -> AuditRule {
        // Audit存在確認
        guard try internalAuditRepository.findById(auditId) != nil else {
            throw UseCaseError.internalAuditNotFound(auditId)
        }

        // テンプレート存在確認
        guard try workflowTemplateRepository.findById(workflowTemplateId) != nil else {
            throw UseCaseError.templateNotFound(workflowTemplateId)
        }

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            throw UseCaseError.validationFailed("Rule name cannot be empty")
        }

        let rule = AuditRule(
            id: AuditRuleID.generate(),
            auditId: auditId,
            name: trimmedName,
            triggerType: triggerType,
            triggerConfig: triggerConfig,
            workflowTemplateId: workflowTemplateId,
            taskAssignments: taskAssignments
        )
        try auditRuleRepository.save(rule)
        return rule
    }
}

// MARK: - ListAuditRulesUseCase

/// Audit Rule一覧取得ユースケース
public struct ListAuditRulesUseCase: Sendable {
    private let auditRuleRepository: any AuditRuleRepositoryProtocol

    public init(auditRuleRepository: any AuditRuleRepositoryProtocol) {
        self.auditRuleRepository = auditRuleRepository
    }

    public func execute(auditId: InternalAuditID, enabledOnly: Bool = false) throws -> [AuditRule] {
        if enabledOnly {
            return try auditRuleRepository.findEnabled(auditId: auditId)
        } else {
            return try auditRuleRepository.findByAudit(auditId)
        }
    }
}

// MARK: - EnableDisableAuditRuleUseCase

/// Audit Rule有効/無効化ユースケース
public struct EnableDisableAuditRuleUseCase: Sendable {
    private let auditRuleRepository: any AuditRuleRepositoryProtocol

    public init(auditRuleRepository: any AuditRuleRepositoryProtocol) {
        self.auditRuleRepository = auditRuleRepository
    }

    public func execute(ruleId: AuditRuleID, isEnabled: Bool) throws -> AuditRule {
        guard var rule = try auditRuleRepository.findById(ruleId) else {
            throw UseCaseError.auditRuleNotFound(ruleId)
        }

        rule.isEnabled = isEnabled
        rule.updatedAt = Date()
        try auditRuleRepository.save(rule)
        return rule
    }
}

// MARK: - GetAuditWithRulesUseCase

/// Audit詳細（ルール含む）取得ユースケース
public struct GetAuditWithRulesUseCase: Sendable {
    private let internalAuditRepository: any InternalAuditRepositoryProtocol
    private let auditRuleRepository: any AuditRuleRepositoryProtocol

    public init(
        internalAuditRepository: any InternalAuditRepositoryProtocol,
        auditRuleRepository: any AuditRuleRepositoryProtocol
    ) {
        self.internalAuditRepository = internalAuditRepository
        self.auditRuleRepository = auditRuleRepository
    }

    public struct Result: Sendable {
        public let audit: InternalAudit
        public let rules: [AuditRule]
    }

    public func execute(auditId: InternalAuditID) throws -> Result? {
        guard let audit = try internalAuditRepository.findById(auditId) else {
            return nil
        }

        let rules = try auditRuleRepository.findByAudit(auditId)
        return Result(audit: audit, rules: rules)
    }
}

// MARK: - DeleteAuditRuleUseCase

/// Audit Rule削除ユースケース
public struct DeleteAuditRuleUseCase: Sendable {
    private let auditRuleRepository: any AuditRuleRepositoryProtocol

    public init(auditRuleRepository: any AuditRuleRepositoryProtocol) {
        self.auditRuleRepository = auditRuleRepository
    }

    public func execute(ruleId: AuditRuleID) throws {
        guard try auditRuleRepository.findById(ruleId) != nil else {
            throw UseCaseError.auditRuleNotFound(ruleId)
        }
        try auditRuleRepository.delete(ruleId)
    }
}

// MARK: - UpdateAuditRuleUseCase

/// Audit Rule更新ユースケース
public struct UpdateAuditRuleUseCase: Sendable {
    private let auditRuleRepository: any AuditRuleRepositoryProtocol

    public init(auditRuleRepository: any AuditRuleRepositoryProtocol) {
        self.auditRuleRepository = auditRuleRepository
    }

    public func execute(
        ruleId: AuditRuleID,
        name: String? = nil,
        triggerConfig: [String: Any]? = nil,
        taskAssignments: [TaskAssignment]? = nil
    ) throws -> AuditRule {
        guard var rule = try auditRuleRepository.findById(ruleId) else {
            throw UseCaseError.auditRuleNotFound(ruleId)
        }

        if let name = name {
            let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedName.isEmpty else {
                throw UseCaseError.validationFailed("Rule name cannot be empty")
            }
            rule.name = trimmedName
        }

        if let triggerConfig = triggerConfig {
            rule.triggerConfig = triggerConfig
        }

        if let taskAssignments = taskAssignments {
            rule.taskAssignments = taskAssignments
        }

        rule.updatedAt = Date()
        try auditRuleRepository.save(rule)
        return rule
    }
}

// MARK: - DeleteInternalAuditUseCase

/// Internal Audit削除ユースケース
public struct DeleteInternalAuditUseCase: Sendable {
    private let internalAuditRepository: any InternalAuditRepositoryProtocol

    public init(internalAuditRepository: any InternalAuditRepositoryProtocol) {
        self.internalAuditRepository = internalAuditRepository
    }

    public func execute(auditId: InternalAuditID) throws {
        guard try internalAuditRepository.findById(auditId) != nil else {
            throw UseCaseError.internalAuditNotFound(auditId)
        }
        try internalAuditRepository.delete(auditId)
    }
}

// MARK: - LockTaskUseCase

/// タスクロックユースケース
/// 参照: docs/requirements/AUDIT.md - ロック機能
public struct LockTaskUseCase: Sendable {
    private let taskRepository: any TaskRepositoryProtocol
    private let internalAuditRepository: any InternalAuditRepositoryProtocol

    public init(
        taskRepository: any TaskRepositoryProtocol,
        internalAuditRepository: any InternalAuditRepositoryProtocol
    ) {
        self.taskRepository = taskRepository
        self.internalAuditRepository = internalAuditRepository
    }

    public func execute(taskId: TaskID, auditId: InternalAuditID) throws -> Task {
        // Audit存在確認
        guard let audit = try internalAuditRepository.findById(auditId) else {
            throw UseCaseError.internalAuditNotFound(auditId)
        }

        // Auditがアクティブかどうか確認
        guard audit.status == .active else {
            throw UseCaseError.validationFailed("Only active audits can lock tasks")
        }

        // タスク取得
        guard var task = try taskRepository.findById(taskId) else {
            throw UseCaseError.taskNotFound(taskId)
        }

        // 既にロック済みの場合はエラー
        guard !task.isLocked else {
            throw UseCaseError.validationFailed("Task is already locked")
        }

        // ロック実行
        task.isLocked = true
        task.lockedByAuditId = auditId
        task.lockedAt = Date()
        task.updatedAt = Date()

        try taskRepository.save(task)
        return task
    }
}

// MARK: - UnlockTaskUseCase

/// タスクロック解除ユースケース
/// 参照: docs/requirements/AUDIT.md - ロック解除（監査エージェントのみ解除可能）
public struct UnlockTaskUseCase: Sendable {
    private let taskRepository: any TaskRepositoryProtocol
    private let internalAuditRepository: any InternalAuditRepositoryProtocol

    public init(
        taskRepository: any TaskRepositoryProtocol,
        internalAuditRepository: any InternalAuditRepositoryProtocol
    ) {
        self.taskRepository = taskRepository
        self.internalAuditRepository = internalAuditRepository
    }

    /// ロック解除（ロックをかけた監査のみ解除可能）
    public func execute(taskId: TaskID, auditId: InternalAuditID) throws -> Task {
        // タスク取得
        guard var task = try taskRepository.findById(taskId) else {
            throw UseCaseError.taskNotFound(taskId)
        }

        // ロックされていない場合はエラー
        guard task.isLocked else {
            throw UseCaseError.validationFailed("Task is not locked")
        }

        // ロックをかけた監査のみ解除可能
        guard task.lockedByAuditId == auditId else {
            throw UseCaseError.validationFailed("Only the audit that locked the task can unlock it")
        }

        // ロック解除
        task.isLocked = false
        task.lockedByAuditId = nil
        task.lockedAt = nil
        task.updatedAt = Date()

        try taskRepository.save(task)
        return task
    }
}

// MARK: - LockAgentUseCase

/// エージェントロックユースケース
/// 参照: docs/requirements/AUDIT.md - ロック機能
public struct LockAgentUseCase: Sendable {
    private let agentRepository: any AgentRepositoryProtocol
    private let internalAuditRepository: any InternalAuditRepositoryProtocol

    public init(
        agentRepository: any AgentRepositoryProtocol,
        internalAuditRepository: any InternalAuditRepositoryProtocol
    ) {
        self.agentRepository = agentRepository
        self.internalAuditRepository = internalAuditRepository
    }

    public func execute(agentId: AgentID, auditId: InternalAuditID) throws -> Agent {
        // Audit存在確認
        guard let audit = try internalAuditRepository.findById(auditId) else {
            throw UseCaseError.internalAuditNotFound(auditId)
        }

        // Auditがアクティブかどうか確認
        guard audit.status == .active else {
            throw UseCaseError.validationFailed("Only active audits can lock agents")
        }

        // エージェント取得
        guard var agent = try agentRepository.findById(agentId) else {
            throw UseCaseError.agentNotFound(agentId)
        }

        // 既にロック済みの場合はエラー
        guard !agent.isLocked else {
            throw UseCaseError.validationFailed("Agent is already locked")
        }

        // ロック実行
        agent.isLocked = true
        agent.lockedByAuditId = auditId
        agent.lockedAt = Date()
        agent.updatedAt = Date()

        try agentRepository.save(agent)
        return agent
    }
}

// MARK: - UnlockAgentUseCase

/// エージェントロック解除ユースケース
/// 参照: docs/requirements/AUDIT.md - ロック解除（監査エージェントのみ解除可能）
public struct UnlockAgentUseCase: Sendable {
    private let agentRepository: any AgentRepositoryProtocol
    private let internalAuditRepository: any InternalAuditRepositoryProtocol

    public init(
        agentRepository: any AgentRepositoryProtocol,
        internalAuditRepository: any InternalAuditRepositoryProtocol
    ) {
        self.agentRepository = agentRepository
        self.internalAuditRepository = internalAuditRepository
    }

    /// ロック解除（ロックをかけた監査のみ解除可能）
    public func execute(agentId: AgentID, auditId: InternalAuditID) throws -> Agent {
        // エージェント取得
        guard var agent = try agentRepository.findById(agentId) else {
            throw UseCaseError.agentNotFound(agentId)
        }

        // ロックされていない場合はエラー
        guard agent.isLocked else {
            throw UseCaseError.validationFailed("Agent is not locked")
        }

        // ロックをかけた監査のみ解除可能
        guard agent.lockedByAuditId == auditId else {
            throw UseCaseError.validationFailed("Only the audit that locked the agent can unlock it")
        }

        // ロック解除
        agent.isLocked = false
        agent.lockedByAuditId = nil
        agent.lockedAt = nil
        agent.updatedAt = Date()

        try agentRepository.save(agent)
        return agent
    }
}

// MARK: - GetLockedTasksUseCase

/// ロック中のタスク一覧取得ユースケース
public struct GetLockedTasksUseCase: Sendable {
    private let taskRepository: any TaskRepositoryProtocol

    public init(taskRepository: any TaskRepositoryProtocol) {
        self.taskRepository = taskRepository
    }

    public func execute(auditId: InternalAuditID? = nil) throws -> [Task] {
        try taskRepository.findLocked(byAuditId: auditId)
    }
}

// MARK: - GetLockedAgentsUseCase

/// ロック中のエージェント一覧取得ユースケース
public struct GetLockedAgentsUseCase: Sendable {
    private let agentRepository: any AgentRepositoryProtocol

    public init(agentRepository: any AgentRepositoryProtocol) {
        self.agentRepository = agentRepository
    }

    public func execute(auditId: InternalAuditID? = nil) throws -> [Agent] {
        try agentRepository.findLocked(byAuditId: auditId)
    }
}

// MARK: - Audit Trigger System

// MARK: - FireAuditRuleUseCase

/// Audit Rule発火ユースケース
/// 参照: docs/requirements/AUDIT.md - ワークフロー実行フロー
/// トリガー条件にマッチしたルールのワークフローをインスタンス化する
public struct FireAuditRuleUseCase: Sendable {
    private let auditRuleRepository: any AuditRuleRepositoryProtocol
    private let templateRepository: any WorkflowTemplateRepositoryProtocol
    private let templateTaskRepository: any TemplateTaskRepositoryProtocol
    private let taskRepository: any TaskRepositoryProtocol
    private let eventRepository: any EventRepositoryProtocol

    public init(
        auditRuleRepository: any AuditRuleRepositoryProtocol,
        templateRepository: any WorkflowTemplateRepositoryProtocol,
        templateTaskRepository: any TemplateTaskRepositoryProtocol,
        taskRepository: any TaskRepositoryProtocol,
        eventRepository: any EventRepositoryProtocol
    ) {
        self.auditRuleRepository = auditRuleRepository
        self.templateRepository = templateRepository
        self.templateTaskRepository = templateTaskRepository
        self.taskRepository = taskRepository
        self.eventRepository = eventRepository
    }

    /// ルール発火結果
    public struct Result: Sendable {
        public let rule: AuditRule
        public let sourceTask: Task
        public let createdTasks: [Task]
    }

    /// Audit Ruleを発火し、ワークフローをインスタンス化する
    /// - Parameters:
    ///   - ruleId: 発火するルールのID
    ///   - sourceTask: トリガーとなったタスク
    /// - Returns: 生成されたタスク群
    public func execute(ruleId: AuditRuleID, sourceTask: Task) throws -> Result {
        // ルール取得
        guard let rule = try auditRuleRepository.findById(ruleId) else {
            throw UseCaseError.auditRuleNotFound(ruleId)
        }

        // テンプレート取得
        guard let template = try templateRepository.findById(rule.workflowTemplateId) else {
            throw UseCaseError.templateNotFound(rule.workflowTemplateId)
        }

        // アクティブなテンプレートのみ使用可能
        guard template.isActive else {
            throw UseCaseError.validationFailed("Cannot use archived template for audit rule")
        }

        // テンプレートタスクを取得（order順）
        let templateTasks = try templateTaskRepository.findByTemplate(rule.workflowTemplateId)

        // タスク割り当てマップを構築（templateTaskOrder -> agentId）
        let assignmentMap = Dictionary(
            uniqueKeysWithValues: rule.taskAssignments.map { ($0.templateTaskOrder, $0.agentId) }
        )

        // タスクを生成
        var createdTasks: [Task] = []
        var orderToTaskIdMap: [Int: TaskID] = [:]

        for templateTask in templateTasks {
            let taskId = TaskID.generate()
            orderToTaskIdMap[templateTask.order] = taskId

            // 依存関係をTaskIDに変換
            let dependencies = templateTask.dependsOnOrders.compactMap { orderToTaskIdMap[$0] }

            // ルールの割り当てからエージェントを取得
            let assigneeId = assignmentMap[templateTask.order]

            // タイトルにソースタスク情報を含める
            let titleWithContext = "\(templateTask.title) [Audit: \(sourceTask.title)]"

            let task = Task(
                id: taskId,
                projectId: sourceTask.projectId,
                title: titleWithContext,
                description: templateTask.description,
                status: .backlog,
                priority: templateTask.defaultPriority,
                assigneeId: assigneeId,
                dependencies: dependencies,
                estimatedMinutes: templateTask.estimatedMinutes
            )
            try taskRepository.save(task)
            createdTasks.append(task)

            // イベント記録
            let event = StateChangeEvent(
                id: EventID.generate(),
                projectId: sourceTask.projectId,
                entityType: .task,
                entityId: task.id.value,
                eventType: .created,
                newState: task.status.rawValue,
                metadata: [
                    "auditRuleId": rule.id.value,
                    "auditId": rule.auditId.value,
                    "sourceTaskId": sourceTask.id.value,
                    "templateId": template.id.value
                ]
            )
            try eventRepository.save(event)
        }

        return Result(rule: rule, sourceTask: sourceTask, createdTasks: createdTasks)
    }
}

// MARK: - CheckAuditTriggersUseCase

/// Audit Triggerチェックユースケース
/// 参照: docs/requirements/AUDIT.md - 自動トリガー機能
/// イベント発生時にマッチするAudit Ruleを検索し、発火する
public struct CheckAuditTriggersUseCase: Sendable {
    private let internalAuditRepository: any InternalAuditRepositoryProtocol
    private let auditRuleRepository: any AuditRuleRepositoryProtocol
    private let fireAuditRuleUseCase: FireAuditRuleUseCase

    public init(
        internalAuditRepository: any InternalAuditRepositoryProtocol,
        auditRuleRepository: any AuditRuleRepositoryProtocol,
        fireAuditRuleUseCase: FireAuditRuleUseCase
    ) {
        self.internalAuditRepository = internalAuditRepository
        self.auditRuleRepository = auditRuleRepository
        self.fireAuditRuleUseCase = fireAuditRuleUseCase
    }

    /// トリガーチェック結果
    public struct Result: Sendable {
        public let triggerType: TriggerType
        public let sourceTask: Task
        public let firedRules: [FireAuditRuleUseCase.Result]
    }

    /// トリガーイベントを処理し、マッチするルールを発火する
    /// - Parameters:
    ///   - triggerType: トリガー種別
    ///   - sourceTask: トリガーとなったタスク
    /// - Returns: 発火結果一覧
    public func execute(triggerType: TriggerType, sourceTask: Task) throws -> Result {
        var firedRules: [FireAuditRuleUseCase.Result] = []

        // 全てのアクティブなInternal Auditを取得
        let activeAudits = try internalAuditRepository.findAll(includeInactive: false)
            .filter { $0.status == .active }

        // 各Auditのルールをチェック
        for audit in activeAudits {
            // 有効なルールのみ取得
            let enabledRules = try auditRuleRepository.findEnabled(auditId: audit.id)

            // トリガータイプがマッチするルールを発火
            for rule in enabledRules where rule.triggerType == triggerType {
                let result = try fireAuditRuleUseCase.execute(ruleId: rule.id, sourceTask: sourceTask)
                firedRules.append(result)
            }
        }

        return Result(triggerType: triggerType, sourceTask: sourceTask, firedRules: firedRules)
    }
}
