// Sources/Domain/Entities/Project.swift
// 参照: docs/architecture/DOMAIN_MODEL.md - Project Entity

import Foundation

/// プロジェクトを表すエンティティ
public struct Project: Identifiable, Equatable, Sendable {
    public let id: ProjectID
    public var name: String
    public var description: String
    public var status: ProjectStatus
    /// Claude Codeエージェントがタスク実行時に使用する作業ディレクトリ（絶対パス）
    public var workingDirectory: String?
    public let createdAt: Date
    public var updatedAt: Date
    /// Feature 14: pausedからactiveに変更された時刻（復帰検知用）
    public var resumedAt: Date?

    public init(
        id: ProjectID,
        name: String,
        description: String = "",
        status: ProjectStatus = .active,
        workingDirectory: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        resumedAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.status = status
        self.workingDirectory = workingDirectory
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.resumedAt = resumedAt
    }
}

// MARK: - ProjectStatus

/// プロジェクトのステータス
/// 要件: active, paused, archived
/// Feature 14: paused を追加（タスク処理のみ停止、チャット・管理操作は継続）
public enum ProjectStatus: String, Codable, Sendable, CaseIterable {
    case active
    case paused    // Feature 14: 一時停止状態
    case archived

    public var displayName: String {
        switch self {
        case .active: return "Active"
        case .paused: return "Paused"
        case .archived: return "Archived"
        }
    }
}
