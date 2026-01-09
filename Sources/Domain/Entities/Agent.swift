// Sources/Domain/Entities/Agent.swift
// 参照: docs/architecture/DOMAIN_MODEL.md - Agent Entity
// 参照: docs/prd/AGENT_CONCEPT.md - エージェント概念

import Foundation

/// AIエージェントまたは人間を表すエンティティ
/// 要件: エージェントはトップレベルエンティティ（プロジェクト非依存）、階層構造をサポート
public struct Agent: Identifiable, Equatable, Sendable {
    public let id: AgentID
    public var name: String
    public var role: String
    public var type: AgentType
    public var aiType: AIType?                    // AIプロバイダー種別（AI agentの場合）
    public var hierarchyType: AgentHierarchyType  // 階層タイプ（Manager/Worker）
    public var roleType: AgentRoleType
    public var parentAgentId: AgentID?      // 階層構造（親エージェント）
    public var maxParallelTasks: Int        // 同時実行可能タスク数
    public var capabilities: [String]
    public var systemPrompt: String?
    public var kickMethod: KickMethod
    public var kickCommand: String?
    public var authLevel: AuthLevel
    public var passkey: String?
    public var status: AgentStatus
    public let createdAt: Date
    public var updatedAt: Date

    // MARK: - Lock Fields (Internal Audit)
    /// ロック状態（監査エージェントによる強制ロック）
    /// 参照: docs/requirements/AUDIT.md - ロック機能
    public var isLocked: Bool
    /// ロックを行った Internal Audit の ID
    public var lockedByAuditId: InternalAuditID?
    /// ロック日時
    public var lockedAt: Date?

    public init(
        id: AgentID,
        name: String,
        role: String,
        type: AgentType = .ai,
        aiType: AIType? = nil,
        hierarchyType: AgentHierarchyType = .worker,
        roleType: AgentRoleType = .developer,
        parentAgentId: AgentID? = nil,
        maxParallelTasks: Int = 1,
        capabilities: [String] = [],
        systemPrompt: String? = nil,
        kickMethod: KickMethod = .cli,
        kickCommand: String? = nil,
        authLevel: AuthLevel = .level0,
        passkey: String? = nil,
        status: AgentStatus = .active,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        isLocked: Bool = false,
        lockedByAuditId: InternalAuditID? = nil,
        lockedAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.role = role
        self.type = type
        self.aiType = aiType
        self.hierarchyType = hierarchyType
        self.roleType = roleType
        self.parentAgentId = parentAgentId
        self.maxParallelTasks = maxParallelTasks
        self.capabilities = capabilities
        self.systemPrompt = systemPrompt
        self.kickMethod = kickMethod
        self.kickCommand = kickCommand
        self.authLevel = authLevel
        self.passkey = passkey
        self.status = status
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isLocked = isLocked
        self.lockedByAuditId = lockedByAuditId
        self.lockedAt = lockedAt
    }

    /// 操作が可能かどうか（ロックされていない場合のみ）
    public var canOperate: Bool {
        !isLocked
    }
}

// MARK: - AuthLevel

/// エージェントの認証レベル
/// 参照: docs/requirements/AGENTS.md - エージェント認証
public enum AuthLevel: String, Codable, Sendable, CaseIterable {
    case level0
    case level1
    case level2

    public var displayName: String {
        switch self {
        case .level0: return "Level 0 (ID only)"
        case .level1: return "Level 1 (ID + Passkey)"
        case .level2: return "Level 2 (+ IP restriction)"
        }
    }
}

// MARK: - KickMethod

/// エージェントの起動方式
/// 参照: docs/requirements/AGENTS.md - 活動のキック
public enum KickMethod: String, Codable, Sendable, CaseIterable {
    case cli
    case script
    case api
    case notification

    public var displayName: String {
        switch self {
        case .cli: return "CLI"
        case .script: return "Script"
        case .api: return "API"
        case .notification: return "Notification"
        }
    }
}

// MARK: - AgentType

/// エージェントの種別
public enum AgentType: String, Codable, Sendable, CaseIterable {
    case human
    case ai

    public var displayName: String {
        switch self {
        case .human: return "Human"
        case .ai: return "AI"
        }
    }
}

// MARK: - AIType

/// AIエージェントのモデル種別
/// 参照: docs/plan/MULTI_AGENT_USE_CASES.md - AIタイプ
public enum AIType: String, Codable, Sendable, CaseIterable {
    // Claude models
    case claudeOpus4 = "claude-opus-4"
    case claudeSonnet4_5 = "claude-sonnet-4-5"
    case claudeSonnet4 = "claude-sonnet-4"

    // Gemini models
    case gemini2Flash = "gemini-2.0-flash"
    case gemini2Pro = "gemini-2.0-pro"

    // OpenAI models
    case gpt4o = "gpt-4o"
    case gpt4oMini = "gpt-4o-mini"

    // Custom model
    case custom = "custom"

    /// 表示名
    public var displayName: String {
        switch self {
        case .claudeOpus4: return "Claude Opus 4"
        case .claudeSonnet4_5: return "Claude Sonnet 4.5"
        case .claudeSonnet4: return "Claude Sonnet 4"
        case .gemini2Flash: return "Gemini 2.0 Flash"
        case .gemini2Pro: return "Gemini 2.0 Pro"
        case .gpt4o: return "GPT-4o"
        case .gpt4oMini: return "GPT-4o Mini"
        case .custom: return "Custom"
        }
    }

    /// プロバイダー名（Coordinator設定用）
    public var provider: String {
        switch self {
        case .claudeOpus4, .claudeSonnet4_5, .claudeSonnet4:
            return "claude"
        case .gemini2Flash, .gemini2Pro:
            return "gemini"
        case .gpt4o, .gpt4oMini:
            return "openai"
        case .custom:
            return "custom"
        }
    }

    /// CLIコマンド名（Runner用）
    public var cliCommand: String {
        switch self {
        case .claudeOpus4, .claudeSonnet4_5, .claudeSonnet4:
            return "claude"
        case .gemini2Flash, .gemini2Pro:
            return "gemini"
        case .gpt4o, .gpt4oMini:
            return "openai"
        case .custom:
            return "claude"  // fallback
        }
    }

    /// モデルID（API呼び出し用）
    public var modelId: String {
        switch self {
        case .claudeOpus4: return "claude-opus-4-20250514"
        case .claudeSonnet4_5: return "claude-sonnet-4-5-20250514"
        case .claudeSonnet4: return "claude-sonnet-4-20250514"
        case .gemini2Flash: return "gemini-2.0-flash"
        case .gemini2Pro: return "gemini-2.0-pro"
        case .gpt4o: return "gpt-4o"
        case .gpt4oMini: return "gpt-4o-mini"
        case .custom: return "custom"
        }
    }
}

// MARK: - AgentRoleType

/// エージェントの役割タイプ
public enum AgentRoleType: String, Codable, Sendable, CaseIterable {
    case developer
    case reviewer
    case tester
    case architect
    case manager
    case writer
    case designer
    case analyst

    public var displayName: String {
        switch self {
        case .developer: return "Developer"
        case .reviewer: return "Reviewer"
        case .tester: return "Tester"
        case .architect: return "Architect"
        case .manager: return "Manager"
        case .writer: return "Writer"
        case .designer: return "Designer"
        case .analyst: return "Analyst"
        }
    }
}

// MARK: - AgentHierarchyType

/// エージェントの階層タイプ（タスク作成・割り当て権限）
/// 参照: docs/requirements/AGENTS.md - エージェントタイプ
public enum AgentHierarchyType: String, Codable, Sendable, CaseIterable {
    case manager  // タスク作成・割り当て可能、実行不可
    case worker   // タスク実行のみ、下位エージェントなし

    public var displayName: String {
        switch self {
        case .manager: return "Manager"
        case .worker: return "Worker"
        }
    }

    public var canCreateTasks: Bool {
        self == .manager
    }

    public var canAssignToOthers: Bool {
        self == .manager
    }

    public var canExecuteTasks: Bool {
        self == .worker
    }

    public var canHaveSubordinates: Bool {
        self == .manager
    }
}

// MARK: - AgentStatus

/// エージェントのステータス
/// PRD: AGENT_CONCEPT.md - Active / Inactive / Archived
public enum AgentStatus: String, Codable, Sendable, CaseIterable {
    case active
    case inactive
    case suspended  // 一時停止
    case archived   // アーカイブ済み（削除済み、履歴保持）

    public var displayName: String {
        switch self {
        case .active: return "Active"
        case .inactive: return "Inactive"
        case .suspended: return "Suspended"
        case .archived: return "Archived"
        }
    }
}
