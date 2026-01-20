// Sources/Domain/Entities/AgentWorkingDirectory.swift
// 参照: docs/design/MULTI_DEVICE_IMPLEMENTATION_PLAN.md

import Foundation

/// エージェントのプロジェクト別ワーキングディレクトリ設定
///
/// マルチデバイス環境でエージェントが異なるマシンで動作する場合に、
/// プロジェクトごとのワーキングディレクトリを管理します。
public struct AgentWorkingDirectory: Identifiable, Equatable, Sendable {
    public let id: AgentWorkingDirectoryID
    public let agentId: AgentID
    public let projectId: ProjectID
    public var workingDirectory: String
    public let createdAt: Date
    public var updatedAt: Date

    public init(
        id: AgentWorkingDirectoryID,
        agentId: AgentID,
        projectId: ProjectID,
        workingDirectory: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.agentId = agentId
        self.projectId = projectId
        self.workingDirectory = workingDirectory
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// 新しいワーキングディレクトリ設定を作成
    public static func create(
        agentId: AgentID,
        projectId: ProjectID,
        workingDirectory: String
    ) -> AgentWorkingDirectory {
        AgentWorkingDirectory(
            id: .generate(),
            agentId: agentId,
            projectId: projectId,
            workingDirectory: workingDirectory
        )
    }

    /// ワーキングディレクトリを更新
    public mutating func updateWorkingDirectory(_ newDirectory: String) {
        self.workingDirectory = newDirectory
        self.updatedAt = Date()
    }
}
