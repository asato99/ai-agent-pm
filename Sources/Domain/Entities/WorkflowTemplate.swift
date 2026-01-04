// Sources/Domain/Entities/WorkflowTemplate.swift
// 参照: docs/requirements/WORKFLOW_TEMPLATES.md

import Foundation

// MARK: - TemplateStatus

/// ワークフローテンプレートのステータス
public enum TemplateStatus: String, Codable, Sendable, CaseIterable {
    case active = "active"
    case archived = "archived"
}

// MARK: - WorkflowTemplate

/// ワークフローテンプレートを表すエンティティ
/// 一連のタスクをテンプレートとして定義し、繰り返し適用できる
/// 設計方針: テンプレートはプロジェクトに紐づく
public struct WorkflowTemplate: Identifiable, Equatable, Sendable {
    public let id: WorkflowTemplateID
    public let projectId: ProjectID  // 所属プロジェクト
    public var name: String
    public var description: String
    public var variables: [String]
    public var status: TemplateStatus
    public let createdAt: Date
    public var updatedAt: Date

    public init(
        id: WorkflowTemplateID,
        projectId: ProjectID,
        name: String,
        description: String = "",
        variables: [String] = [],
        status: TemplateStatus = .active,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.projectId = projectId
        self.name = name
        self.description = description
        self.variables = variables
        self.status = status
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// テンプレートがアクティブかどうか
    public var isActive: Bool {
        status == .active
    }

    /// 変数名が有効かどうかを検証
    /// 有効な変数名: 英字またはアンダースコアで始まり、英数字とアンダースコアのみ
    public static func isValidVariableName(_ name: String) -> Bool {
        let pattern = "^[a-zA-Z_][a-zA-Z0-9_]*$"
        return name.range(of: pattern, options: .regularExpression) != nil
    }

    /// テンプレート内の全変数が有効かどうか
    public var hasValidVariables: Bool {
        variables.allSatisfy { Self.isValidVariableName($0) }
    }
}

// MARK: - TemplateTask

/// テンプレート内の個別タスク定義
public struct TemplateTask: Identifiable, Equatable, Sendable {
    public let id: TemplateTaskID
    public let templateId: WorkflowTemplateID
    public var title: String
    public var description: String
    public var order: Int
    public var dependsOnOrders: [Int]
    public var defaultAssigneeRole: AgentRoleType?
    public var defaultPriority: TaskPriority
    public var estimatedMinutes: Int?

    public init(
        id: TemplateTaskID,
        templateId: WorkflowTemplateID,
        title: String,
        description: String = "",
        order: Int,
        dependsOnOrders: [Int] = [],
        defaultAssigneeRole: AgentRoleType? = nil,
        defaultPriority: TaskPriority = .medium,
        estimatedMinutes: Int? = nil
    ) {
        self.id = id
        self.templateId = templateId
        self.title = title
        self.description = description
        self.order = order
        self.dependsOnOrders = dependsOnOrders
        self.defaultAssigneeRole = defaultAssigneeRole
        self.defaultPriority = defaultPriority
        self.estimatedMinutes = estimatedMinutes
    }

    /// 依存関係が有効かどうか（自己参照なし）
    public var hasValidDependencies: Bool {
        !dependsOnOrders.contains(order)
    }

    /// 変数を置換したタイトルを生成
    public func resolveTitle(with values: [String: String]) -> String {
        resolve(title, with: values)
    }

    /// 変数を置換した説明を生成
    public func resolveDescription(with values: [String: String]) -> String {
        resolve(description, with: values)
    }

    /// 文字列内の変数を置換
    private func resolve(_ text: String, with values: [String: String]) -> String {
        var result = text
        for (key, value) in values {
            result = result.replacingOccurrences(of: "{{\(key)}}", with: value)
        }
        return result
    }
}

// MARK: - InstantiationResult

/// テンプレートインスタンス化の結果
public struct InstantiationResult: Sendable {
    public let templateId: WorkflowTemplateID
    public let projectId: ProjectID
    public let createdTasks: [Task]
    public let timestamp: Date

    public init(
        templateId: WorkflowTemplateID,
        projectId: ProjectID,
        createdTasks: [Task],
        timestamp: Date = Date()
    ) {
        self.templateId = templateId
        self.projectId = projectId
        self.createdTasks = createdTasks
        self.timestamp = timestamp
    }

    /// 生成されたタスク数
    public var taskCount: Int {
        createdTasks.count
    }
}
