// Sources/Domain/Entities/Project.swift
// 参照: docs/architecture/DOMAIN_MODEL.md - Project Entity

import Foundation

/// プロジェクトを表すエンティティ
public struct Project: Identifiable, Equatable, Sendable {
    public let id: ProjectID
    public var name: String
    public var description: String
    public var status: ProjectStatus
    public let createdAt: Date
    public var updatedAt: Date

    public init(
        id: ProjectID,
        name: String,
        description: String = "",
        status: ProjectStatus = .active,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.status = status
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

// MARK: - ProjectStatus

/// プロジェクトのステータス
/// 要件: active, archived のみ（completed は削除）
public enum ProjectStatus: String, Codable, Sendable, CaseIterable {
    case active
    case archived

    public var displayName: String {
        switch self {
        case .active: return "Active"
        case .archived: return "Archived"
        }
    }
}
