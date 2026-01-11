// Sources/Domain/Entities/PendingAgentPurpose.swift
// 参照: docs/design/CHAT_FEATURE.md - 起動理由管理
//
// エージェントの起動理由（タスク実行 or チャット応答）を管理するエンティティ

import Foundation

/// エージェントの起動理由
public enum AgentPurpose: String, Codable, Sendable {
    /// タスク実行のため
    case task
    /// チャット応答のため
    case chat
}

/// 起動待ちエージェントの理由を管理
///
/// ユーザーがチャットメッセージを送信すると、このテーブルに
/// purpose="chat" が記録される。Coordinator がエージェントを
/// 起動し、authenticate 時に purpose が設定され、このレコードは削除される。
public struct PendingAgentPurpose: Identifiable, Equatable, Sendable {
    /// (agentId, projectId) の複合キー
    public var id: String {
        "\(agentId.value)_\(projectId.value)"
    }

    public let agentId: AgentID
    public let projectId: ProjectID
    public let purpose: AgentPurpose
    public let createdAt: Date

    public init(
        agentId: AgentID,
        projectId: ProjectID,
        purpose: AgentPurpose,
        createdAt: Date = Date()
    ) {
        self.agentId = agentId
        self.projectId = projectId
        self.purpose = purpose
        self.createdAt = createdAt
    }
}

// MARK: - Repository Protocol

/// PendingAgentPurpose リポジトリプロトコル
public protocol PendingAgentPurposeRepositoryProtocol: Sendable {
    /// 起動理由を検索
    func find(agentId: AgentID, projectId: ProjectID) throws -> PendingAgentPurpose?

    /// 起動理由を保存（既存があれば上書き）
    func save(_ purpose: PendingAgentPurpose) throws

    /// 起動理由を削除
    func delete(agentId: AgentID, projectId: ProjectID) throws

    /// 期限切れレコードを削除（TTL: デフォルト5分）
    func deleteExpired(olderThan: Date) throws
}
