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
