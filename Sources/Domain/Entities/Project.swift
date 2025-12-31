// Sources/Domain/Entities/Project.swift
// 参照: docs/architecture/DOMAIN_MODEL.md - Project Entity

import Foundation

/// プロジェクトを表すエンティティ
/// Phase 1では最小限のプロパティのみ実装
public struct Project: Identifiable, Equatable, Sendable {
    public let id: ProjectID
    public var name: String

    public init(
        id: ProjectID,
        name: String
    ) {
        self.id = id
        self.name = name
    }
}
