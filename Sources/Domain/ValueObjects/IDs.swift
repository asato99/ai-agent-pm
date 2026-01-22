// Sources/Domain/ValueObjects/IDs.swift
// 参照: docs/architecture/DOMAIN_MODEL.md - Value Objects セクション

import Foundation

// MARK: - AgentID

public struct AgentID: Hashable, Codable, Sendable, CustomStringConvertible {
    public let value: String

    public init(value: String) {
        self.value = value
    }

    public static func generate() -> AgentID {
        AgentID(value: "agt_\(UUID().uuidString.prefix(12).lowercased())")
    }

    public var description: String { value }

    // MARK: - System Identifiers
    /// ユーザー（UI）からの操作を示す特別な識別子
    public static let systemUser = AgentID(value: "system:user")
    /// システム自動処理を示す特別な識別子
    public static let systemAuto = AgentID(value: "system:auto")

    /// システム識別子かどうかを判定
    public var isSystemIdentifier: Bool {
        value.hasPrefix("system:")
    }

    /// ユーザー操作による識別子かどうかを判定
    public var isUserAction: Bool {
        self == .systemUser
    }
}

// MARK: - ProjectID

public struct ProjectID: Hashable, Codable, Sendable, CustomStringConvertible {
    public let value: String

    public init(value: String) {
        self.value = value
    }

    public static func generate() -> ProjectID {
        ProjectID(value: "prj_\(UUID().uuidString.prefix(12).lowercased())")
    }

    public var description: String { value }
}

// MARK: - TaskID

public struct TaskID: Hashable, Codable, Sendable, CustomStringConvertible {
    public let value: String

    public init(value: String) {
        self.value = value
    }

    public static func generate() -> TaskID {
        TaskID(value: "tsk_\(UUID().uuidString.prefix(12).lowercased())")
    }

    public var description: String { value }
}

// MARK: - SessionID

public struct SessionID: Hashable, Codable, Sendable, CustomStringConvertible {
    public let value: String

    public init(value: String) {
        self.value = value
    }

    public static func generate() -> SessionID {
        SessionID(value: "ses_\(UUID().uuidString.prefix(12).lowercased())")
    }

    public var description: String { value }
}

// MARK: - ContextID

public struct ContextID: Hashable, Codable, Sendable, CustomStringConvertible {
    public let value: String

    public init(value: String) {
        self.value = value
    }

    public static func generate() -> ContextID {
        ContextID(value: "ctx_\(UUID().uuidString.prefix(12).lowercased())")
    }

    public var description: String { value }
}

// MARK: - HandoffID

public struct HandoffID: Hashable, Codable, Sendable, CustomStringConvertible {
    public let value: String

    public init(value: String) {
        self.value = value
    }

    public static func generate() -> HandoffID {
        HandoffID(value: "hnd_\(UUID().uuidString.prefix(12).lowercased())")
    }

    public var description: String { value }
}

// MARK: - EventID

public struct EventID: Hashable, Codable, Sendable, CustomStringConvertible {
    public let value: String

    public init(value: String) {
        self.value = value
    }

    public static func generate() -> EventID {
        EventID(value: "evt_\(UUID().uuidString.prefix(12).lowercased())")
    }

    public var description: String { value }
}

// MARK: - WorkflowTemplateID

public struct WorkflowTemplateID: Hashable, Codable, Sendable, CustomStringConvertible {
    public let value: String

    public init(value: String) {
        self.value = value
    }

    public static func generate() -> WorkflowTemplateID {
        WorkflowTemplateID(value: "wft_\(UUID().uuidString.prefix(12).lowercased())")
    }

    public var description: String { value }
}

// MARK: - TemplateTaskID

public struct TemplateTaskID: Hashable, Codable, Sendable, CustomStringConvertible {
    public let value: String

    public init(value: String) {
        self.value = value
    }

    public static func generate() -> TemplateTaskID {
        TemplateTaskID(value: "ttk_\(UUID().uuidString.prefix(12).lowercased())")
    }

    public var description: String { value }
}

// MARK: - InternalAuditID

/// Internal Audit の一意識別子
/// 参照: docs/requirements/AUDIT.md
public struct InternalAuditID: Hashable, Codable, Sendable, CustomStringConvertible {
    public let value: String

    public init(value: String) {
        self.value = value
    }

    public static func generate() -> InternalAuditID {
        InternalAuditID(value: "aud_\(UUID().uuidString.prefix(12).lowercased())")
    }

    public var description: String { value }
}

// MARK: - AuditRuleID

/// Audit Rule の一意識別子
/// 参照: docs/requirements/AUDIT.md
public struct AuditRuleID: Hashable, Codable, Sendable, CustomStringConvertible {
    public let value: String

    public init(value: String) {
        self.value = value
    }

    public static func generate() -> AuditRuleID {
        AuditRuleID(value: "arl_\(UUID().uuidString.prefix(12).lowercased())")
    }

    public var description: String { value }
}

// MARK: - AgentCredentialID

/// エージェント認証情報の一意識別子
/// 参照: docs/plan/PHASE3_PULL_ARCHITECTURE.md
public struct AgentCredentialID: Hashable, Codable, Sendable, CustomStringConvertible {
    public let value: String

    public init(value: String) {
        self.value = value
    }

    public static func generate() -> AgentCredentialID {
        AgentCredentialID(value: "crd_\(UUID().uuidString.prefix(12).lowercased())")
    }

    public var description: String { value }
}

// MARK: - AgentSessionID

/// エージェントセッションの一意識別子（認証後のセッション管理用）
/// 参照: docs/plan/PHASE3_PULL_ARCHITECTURE.md
public struct AgentSessionID: Hashable, Codable, Sendable, CustomStringConvertible {
    public let value: String

    public init(value: String) {
        self.value = value
    }

    public static func generate() -> AgentSessionID {
        AgentSessionID(value: "asn_\(UUID().uuidString.prefix(12).lowercased())")
    }

    public var description: String { value }
}

// MARK: - ExecutionLogID

/// 実行ログの一意識別子
/// 参照: docs/plan/PHASE3_PULL_ARCHITECTURE.md - Phase 3-3
public struct ExecutionLogID: Hashable, Codable, Sendable, CustomStringConvertible {
    public let value: String

    public init(value: String) {
        self.value = value
    }

    public static func generate() -> ExecutionLogID {
        ExecutionLogID(value: "exec_\(UUID().uuidString.prefix(12).lowercased())")
    }

    public var description: String { value }
}

// MARK: - ChatMessageID

/// チャットメッセージの一意識別子
/// 参照: docs/design/CHAT_FEATURE.md
public struct ChatMessageID: Hashable, Codable, Sendable, CustomStringConvertible {
    public let value: String

    public init(value: String) {
        self.value = value
    }

    public static func generate() -> ChatMessageID {
        ChatMessageID(value: "msg_\(UUID().uuidString.prefix(12).lowercased())")
    }

    public var description: String { value }
}

// MARK: - AgentWorkingDirectoryID

/// エージェントのワーキングディレクトリ設定の一意識別子
/// 参照: docs/design/MULTI_DEVICE_IMPLEMENTATION_PLAN.md
public struct AgentWorkingDirectoryID: Hashable, Codable, Sendable, CustomStringConvertible {
    public let value: String

    public init(value: String) {
        self.value = value
    }

    public static func generate() -> AgentWorkingDirectoryID {
        AgentWorkingDirectoryID(value: "awd_\(UUID().uuidString.prefix(12).lowercased())")
    }

    public var description: String { value }
}

// MARK: - NotificationID

/// 通知の一意識別子
/// 参照: docs/design/NOTIFICATION_SYSTEM.md
public struct NotificationID: Hashable, Codable, Sendable, CustomStringConvertible {
    public let value: String

    public init(value: String) {
        self.value = value
    }

    public static func generate() -> NotificationID {
        NotificationID(value: "ntf_\(UUID().uuidString.prefix(12).lowercased())")
    }

    public var description: String { value }
}
