// Sources/UseCase/Audit/AuditRuleUseCases.swift
// Audit Rule CRUD + Trigger系ユースケース
// 参照: docs/requirements/AUDIT.md

import Foundation
import Domain

// MARK: - CreateAuditRuleUseCase

/// Audit Rule作成ユースケース
/// 設計変更: AuditRuleはauditTasksをインラインで保持（WorkflowTemplateはプロジェクトスコープのため）
public struct CreateAuditRuleUseCase: Sendable {
    private let auditRuleRepository: any AuditRuleRepositoryProtocol
    private let internalAuditRepository: any InternalAuditRepositoryProtocol

    public init(
        auditRuleRepository: any AuditRuleRepositoryProtocol,
        internalAuditRepository: any InternalAuditRepositoryProtocol
    ) {
        self.auditRuleRepository = auditRuleRepository
        self.internalAuditRepository = internalAuditRepository
    }

    public func execute(
        auditId: InternalAuditID,
        name: String,
        triggerType: TriggerType,
        triggerConfig: [String: Any]? = nil,
        auditTasks: [AuditTask]
    ) throws -> AuditRule {
        // Audit存在確認
        guard try internalAuditRepository.findById(auditId) != nil else {
            throw UseCaseError.internalAuditNotFound(auditId)
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
            auditTasks: auditTasks
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
        auditTasks: [AuditTask]? = nil
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

        if let auditTasks = auditTasks {
            rule.auditTasks = auditTasks
        }

        rule.updatedAt = Date()
        try auditRuleRepository.save(rule)
        return rule
    }
}

// MARK: - FireAuditRuleUseCase

/// Audit Rule発火ユースケース
/// 参照: docs/requirements/AUDIT.md - ワークフロー実行フロー
/// 設計変更: AuditRuleはインラインでauditTasksを保持（WorkflowTemplateはプロジェクトスコープのため）
public struct FireAuditRuleUseCase: Sendable {
    private let auditRuleRepository: any AuditRuleRepositoryProtocol
    private let taskRepository: any TaskRepositoryProtocol
    private let eventRepository: any EventRepositoryProtocol

    public init(
        auditRuleRepository: any AuditRuleRepositoryProtocol,
        taskRepository: any TaskRepositoryProtocol,
        eventRepository: any EventRepositoryProtocol
    ) {
        self.auditRuleRepository = auditRuleRepository
        self.taskRepository = taskRepository
        self.eventRepository = eventRepository
    }

    /// ルール発火結果
    public struct Result: Sendable {
        public let rule: AuditRule
        public let sourceTask: Task
        public let createdTasks: [Task]
    }

    /// Audit Ruleを発火し、auditTasksからタスクを生成する
    /// - Parameters:
    ///   - ruleId: 発火するルールのID
    ///   - sourceTask: トリガーとなったタスク
    /// - Returns: 生成されたタスク群
    public func execute(ruleId: AuditRuleID, sourceTask: Task) throws -> Result {
        // ルール取得
        guard let rule = try auditRuleRepository.findById(ruleId) else {
            throw UseCaseError.auditRuleNotFound(ruleId)
        }

        // auditTasksが空の場合はエラー
        guard rule.hasTasks else {
            throw UseCaseError.validationFailed("Audit rule has no tasks defined")
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

            let task = Task(
                id: taskId,
                projectId: sourceTask.projectId,
                title: titleWithContext,
                description: auditTask.description,
                status: .backlog,
                priority: auditTask.priority,
                assigneeId: auditTask.assigneeId,
                dependencies: dependencies
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
                    "sourceTaskId": sourceTask.id.value
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
