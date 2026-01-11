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

// MARK: - DateProvider Protocol

/// 時刻提供プロトコル（テスト時にモック可能）
public protocol DateProvider: Sendable {
    func now() -> Date
}

/// システム時刻を提供するデフォルト実装
public struct SystemDateProvider: DateProvider {
    public init() {}
    public func now() -> Date { Date() }
}

/// 起動待ちエージェントの理由を管理
///
/// ユーザーがチャットメッセージを送信すると、このテーブルに
/// purpose="chat" が記録される。Coordinator がエージェントを
/// 起動し、authenticate 時に purpose が設定され、このレコードは削除される。
///
/// ## 起動制御フロー
/// 1. createdAtから5分経過 → TTL超過として削除、エラー返却
/// 2. startedAtがnull → エージェント起動指示、startedAtを現在時刻に更新
/// 3. startedAtがある → 既に起動済み、hold返却（認証完了待ち）
public struct PendingAgentPurpose: Identifiable, Equatable, Sendable {
    /// TTL（Time To Live）: 5分
    public static let ttlSeconds: TimeInterval = 5 * 60

    /// (agentId, projectId) の複合キー
    public var id: String {
        "\(agentId.value)_\(projectId.value)"
    }

    public let agentId: AgentID
    public let projectId: ProjectID
    public let purpose: AgentPurpose
    public let createdAt: Date
    /// Coordinatorがエージェント起動を開始した時刻（nilなら未起動）
    public let startedAt: Date?

    public init(
        agentId: AgentID,
        projectId: ProjectID,
        purpose: AgentPurpose,
        createdAt: Date = Date(),
        startedAt: Date? = nil
    ) {
        self.agentId = agentId
        self.projectId = projectId
        self.purpose = purpose
        self.createdAt = createdAt
        self.startedAt = startedAt
    }

    /// 起動済みとしてマークした新しいインスタンスを返す
    public func markAsStarted(at date: Date) -> PendingAgentPurpose {
        PendingAgentPurpose(
            agentId: agentId,
            projectId: projectId,
            purpose: purpose,
            createdAt: createdAt,
            startedAt: date
        )
    }

    /// TTLを超過しているかどうか
    public func isExpired(now: Date) -> Bool {
        now.timeIntervalSince(createdAt) > Self.ttlSeconds
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

    /// 起動済みとしてマーク（started_atを更新）
    func markAsStarted(agentId: AgentID, projectId: ProjectID, startedAt: Date) throws
}
